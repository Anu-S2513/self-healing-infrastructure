# status.ps1 - Comprehensive Infrastructure Status Check
$ErrorActionPreference = "Continue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Self-Healing Infrastructure - Environment Status        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Docker Container Status
Write-Host "`n[1/5] Docker Container States:" -ForegroundColor Yellow
docker compose ps

# 2. NGINX Endpoint Test
Write-Host "`n[2/5] Testing NGINX Web Server (http://localhost:8081):" -ForegroundColor Yellow
try {
    $nginxRes = Invoke-WebRequest -Uri "http://localhost:8081" -UseBasicParsing -TimeoutSec 3
    Write-Host "  [✓] NGINX Status: $($nginxRes.StatusCode) $($nginxRes.StatusDescription)" -ForegroundColor Green
} catch {
    Write-Host "  [!] NGINX is unreachable: $($_.Exception.Message)" -ForegroundColor Red
}

# 3. Prometheus Blackbox Probe Metric
Write-Host "`n[3/5] Checking Prometheus Blackbox Metric (probe_success):" -ForegroundColor Yellow
try {
    $promRes = Invoke-RestMethod -Uri "http://localhost:9090/api/v1/query?query=probe_success" -TimeoutSec 3
    if ($promRes.status -eq "success") {
        $val = $promRes.data.result[0].value[1]
        if ($val -eq "1") {
            Write-Host "  [✓] probe_success = 1 (NGINX probe is UP and healthy)" -ForegroundColor Green
        } else {
            Write-Host "  [!] probe_success = $val (NGINX probe is FAILING)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "  [!] Prometheus is unreachable: $($_.Exception.Message)" -ForegroundColor Red
}

# 4. Alertmanager Active Alerts
Write-Host "`n[4/5] Checking Alertmanager Alerts (http://localhost:9093):" -ForegroundColor Yellow
try {
    $alerts = Invoke-RestMethod -Uri "http://localhost:9093/api/v2/alerts" -TimeoutSec 3
    if ($alerts.Count -gt 0) {
        Write-Host "  Active alerts count: $($alerts.Count)" -ForegroundColor Yellow
        foreach ($a in $alerts) {
            Write-Host "  - Alert: $($a.labels.alertname) | State: $($a.status.state) | Service: $($a.labels.service)" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [✓] No active alerts firing in Alertmanager (System Healthy)." -ForegroundColor Green
    }
} catch {
    Write-Host "  [!] Alertmanager is unreachable: $($_.Exception.Message)" -ForegroundColor Red
}

# 5. FastAPI Auto-Healer Status
Write-Host "`n[5/5] Checking FastAPI Automation Engine (http://localhost:8000):" -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:8000/health" -TimeoutSec 3
    Write-Host "  AutoHealer Status: $($health.status) | Docker Socket Connected: $($health.docker_socket_connected)" -ForegroundColor Green
    $rec = Invoke-RestMethod -Uri "http://localhost:8000/recovery/status" -TimeoutSec 3
    Write-Host "  Total Recoveries Triggered: $($rec.metrics.total_recoveries_triggered) | Succeeded: $($rec.metrics.total_recoveries_succeeded)" -ForegroundColor Cyan
    Write-Host "  Cooldown Active: $($rec.cooldown.cooldown_active)" -ForegroundColor Cyan
} catch {
    Write-Host "  [!] FastAPI AutoHealer is unreachable: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
