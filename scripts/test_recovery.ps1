# test_recovery.ps1 - Directly inspect recovery engine metrics and simulate alert webhook payload
$ErrorActionPreference = "Continue"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Testing FastAPI AutoHealer Engine & Recovery API        " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Health check
Write-Host "`n[1] Checking /health endpoint..." -ForegroundColor Yellow
try {
    $health = Invoke-RestMethod -Uri "http://localhost:8000/health" -Method Get
    $health | ConvertTo-Json -Depth 3 | Write-Host -ForegroundColor Green
} catch {
    Write-Host "Failed to reach health endpoint: $($_.Exception.Message)" -ForegroundColor Red
}

# 2. Status & metrics check
Write-Host "`n[2] Checking /recovery/status telemetry..." -ForegroundColor Yellow
try {
    $status = Invoke-RestMethod -Uri "http://localhost:8000/recovery/status" -Method Get
    $status | ConvertTo-Json -Depth 4 | Write-Host -ForegroundColor Cyan
} catch {
    Write-Host "Failed to reach status endpoint: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host "`n==========================================================" -ForegroundColor Cyan
