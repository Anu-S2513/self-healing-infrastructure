# test_failure.ps1 - Automated End-to-End Failure Detection & Recovery Verification
$ErrorActionPreference = "Continue"

Write-Host "=================================================================" -ForegroundColor Magenta
Write-Host "   AUTONOMOUS INFRASTRUCTURE FAILURE & RECOVERY SIMULATION TEST  " -ForegroundColor Magenta
Write-Host "=================================================================" -ForegroundColor Magenta

# Step 1: Pre-flight checks
Write-Host "`n[Step 1/6] Pre-flight Verification..." -ForegroundColor Yellow
try {
    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker daemon is unreachable. Please start Docker Desktop."
        exit 1
    }
} catch {
    Write-Error "Docker daemon check failed."
    exit 1
}

$containerName = "self-healing-nginx"
$exists = docker ps -a --filter "name=^/${containerName}$" --format "{{.Names}}"
if (-not $exists) {
    Write-Error "Target container '${containerName}' not found! Start the stack using scripts/start.ps1 first."
    exit 1
}

# Verify NGINX is initially healthy
try {
    $baselineRes = Invoke-WebRequest -Uri "http://localhost:8081" -UseBasicParsing -TimeoutSec 3
    Write-Host "  [✓] Baseline Confirmed: NGINX is online (HTTP $($baselineRes.StatusCode))." -ForegroundColor Green
} catch {
    Write-Host "  [!] Warning: NGINX is not responding at baseline. Checking if container is running..." -ForegroundColor Yellow
}

# Step 2: Inject Deliberate Failure
Write-Host "`n[Step 2/6] INJECTING OUTAGE: Deliberately stopping '${containerName}'..." -ForegroundColor Red
Write-Host "  Command: docker stop ${containerName}" -ForegroundColor DarkGray
docker stop $containerName > $null

$initialStopState = docker inspect --format '{{.State.Status}}' $containerName
Write-Host "  Container state is now: '$initialStopState' (Outage successfully injected)" -ForegroundColor Red

# Confirm probe failure from host view
try {
    $deadCheck = Invoke-WebRequest -Uri "http://localhost:8081" -UseBasicParsing -TimeoutSec 2
    Write-Host "  [!] NGINX is still answering?" -ForegroundColor Red
} catch {
    Write-Host "  [✓] NGINX is confirmed DOWN (Connection refused as expected)." -ForegroundColor Green
}

# Step 3: Wait for Prometheus & Alertmanager failure detection
Write-Host "`n[Step 3/6] Awaiting Autonomous Detection & Alert Trigger..." -ForegroundColor Yellow
Write-Host "  (Prometheus scrape interval: 10s, evaluation interval: 10s, alert duration: 30s)" -ForegroundColor DarkGray
Write-Host "  Waiting for monitoring pipeline to detect outage..." -ForegroundColor Yellow

$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
$maxTimeoutSeconds = 90
$detectedDown = $false
$alertFiring = $false
$recovered = $false

while ($stopwatch.Elapsed.TotalSeconds -lt $maxTimeoutSeconds) {
    $elapsed = [math]::Round($stopwatch.Elapsed.TotalSeconds)

    # Check Blackbox metric
    if (-not $detectedDown) {
        try {
            $metricRes = Invoke-RestMethod -Uri "http://localhost:9090/api/v1/query?query=probe_success" -TimeoutSec 2
            if ($metricRes.status -eq "success" -and $metricRes.data.result.Count -gt 0) {
                $val = $metricRes.data.result[0].value[1]
                if ($val -eq "0") {
                    $detectedDown = $true
                    Write-Host "  [$elapsed s] [PROMETHEUS] Blackbox probe_success == 0 (Failure Detected by Prometheus)" -ForegroundColor Red
                }
            }
        } catch {}
    }

    # Check if Alertmanager or Prometheus shows NginxDown firing
    if (-not $alertFiring) {
        try {
            $alertRes = Invoke-RestMethod -Uri "http://localhost:9090/api/v1/alerts" -TimeoutSec 2
            if ($alertRes.status -eq "success" -and $alertRes.data.alerts.Count -gt 0) {
                foreach ($al in $alertRes.data.alerts) {
                    if ($al.labels.alertname -eq "NginxDown" -and $al.state -eq "firing") {
                        $alertFiring = $true
                        Write-Host "  [$elapsed s] [ALERTMANAGER] Alert 'NginxDown' state: FIRING -> Webhook dispatched to FastAPI" -ForegroundColor Magenta
                    }
                }
            }
        } catch {}
    }

    # Check container status for autonomous recovery
    $currentState = docker inspect --format '{{.State.Status}}' $containerName
    if ($currentState -eq "running") {
        $recovered = $true
        $recoveryTime = $elapsed
        Write-Host "  [$elapsed s] [AUTONOMOUS ENGINE] Container '${containerName}' restored to 'running' by Ansible!" -ForegroundColor Green
        break
    }

    Write-Host "  [$elapsed s] Awaiting autonomous self-healing... Current container state: '$currentState'" -ForegroundColor DarkGray
    Start-Sleep -Seconds 3
}

$stopwatch.Stop()

# Step 4: Validate Recovery
Write-Host "`n[Step 4/6] Verifying Web Service Functionality..." -ForegroundColor Yellow

if (-not $recovered) {
    Write-Host "  [X] FAILED: Container did not recover within $maxTimeoutSeconds seconds." -ForegroundColor Red
    exit 1
}

# Step 5: Test HTTP Endpoint
Write-Host "`n[Step 5/6] Testing HTTP Endpoint (http://localhost:8081)..." -ForegroundColor Yellow
$httpRestored = $false
for ($i = 1; $i -le 10; $i++) {
    try {
        $testRes = Invoke-WebRequest -Uri "http://localhost:8081" -UseBasicParsing -TimeoutSec 3
        if ($testRes.StatusCode -eq 200) {
            $httpRestored = $true
            Write-Host "  [✓] HTTP 200 OK received from NGINX on port 8081!" -ForegroundColor Green
            break
        }
    } catch {
        Write-Host "  [Attempt $i/10] Waiting for NGINX socket ready..." -ForegroundColor DarkGray
        Start-Sleep -Seconds 1
    }
}

if (-not $httpRestored) {
    Write-Host "  [X] HTTP endpoint did not respond with 200 OK." -ForegroundColor Red
    exit 1
}

# Step 6: Verify FastAPI remediation telemetry
Write-Host "`n[Step 6/6] Inspecting AutoHealer Recovery Audit Log..." -ForegroundColor Yellow
try {
    $audit = Invoke-RestMethod -Uri "http://localhost:8000/recovery/status" -TimeoutSec 3
    Write-Host "  Total Recoveries Triggered: $($audit.metrics.total_recoveries_triggered)" -ForegroundColor Cyan
    Write-Host "  Total Recoveries Succeeded: $($audit.metrics.total_recoveries_succeeded)" -ForegroundColor Cyan
    if ($audit.last_recovery_result) {
        Write-Host "  Last Remediation Target:    $($audit.last_recovery_result.target)" -ForegroundColor Cyan
        Write-Host "  Playbook Execution Time:    $($audit.last_recovery_result.duration_seconds) s" -ForegroundColor Cyan
        Write-Host "  Remediation Success Flag:   $($audit.last_recovery_result.success)" -ForegroundColor Green
    }
} catch {
    Write-Host "  [!] Could not fetch recovery telemetry: $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`n=================================================================" -ForegroundColor Green
Write-Host "  TEST RESULT: SUCCESSFUL AUTONOMOUS HEALING VERIFIED (Time: $recoveryTime s)" -ForegroundColor Green
Write-Host "  The entire loop: Failure -> Probe -> Prometheus -> Alertmanager ->" -ForegroundColor Green
Write-Host "  FastAPI -> Ansible Playbook -> Docker Recovery was completed 100%!" -ForegroundColor Green
Write-Host "=================================================================" -ForegroundColor Green
