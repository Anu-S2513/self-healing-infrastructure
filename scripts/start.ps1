# start.ps1 - Launch and initialize Self-Healing Infrastructure
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Starting Self-Healing Infrastructure Stack              " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Verify Docker Engine is reachable
try {
    docker info > $null 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Docker Desktop daemon is not running! Please start Docker Desktop first."
        exit 1
    }
} catch {
    Write-Error "Docker is not accessible. Please ensure Docker Desktop is running."
    exit 1
}

# 2. Build and launch services
Write-Host "[+] Building automation container and launching services with Docker Compose..." -ForegroundColor Yellow
docker compose up -d --build

if ($LASTEXITCODE -ne 0) {
    Write-Error "Docker Compose failed to start services."
    exit 1
}

Write-Host "[+] Waiting 10 seconds for services to initialize..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

# 3. Check health and connectivity
Write-Host "`n================== Service Endpoints ===================" -ForegroundColor Green
Write-Host "  NGINX Web Server:       http://localhost:8081" -ForegroundColor White
Write-Host "  Prometheus Dashboard:   http://localhost:9090" -ForegroundColor White
Write-Host "  Prometheus Targets:     http://localhost:9090/targets" -ForegroundColor White
Write-Host "  Prometheus Alerts:      http://localhost:9090/alerts" -ForegroundColor White
Write-Host "  Blackbox Exporter:      http://localhost:9115" -ForegroundColor White
Write-Host "  Alertmanager UI:        http://localhost:9093" -ForegroundColor White
Write-Host "  FastAPI Health:         http://localhost:8000/health" -ForegroundColor White
Write-Host "  FastAPI Swagger UI:     http://localhost:8000/docs" -ForegroundColor White
Write-Host "  FastAPI Recovery Info:  http://localhost:8000/recovery/status" -ForegroundColor White
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "[✓] Infrastructure successfully initialized!" -ForegroundColor Green
