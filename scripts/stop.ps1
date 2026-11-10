# stop.ps1 - Gracefully stop Self-Healing Infrastructure
$ErrorActionPreference = "Stop"

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "   Stopping Self-Healing Infrastructure Stack              " -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

docker compose down

if ($LASTEXITCODE -eq 0) {
    Write-Host "[✓] All project services stopped successfully." -ForegroundColor Green
} else {
    Write-Error "Failed to stop services."
}
