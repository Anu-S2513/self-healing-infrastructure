# Project Screenshots & Demonstration Evidence Guide

This folder is designed to store visual screenshots for presentation and project report submission.

## Recommended Screenshots to Capture:

1. **`01_nginx_running.png`**:
   - URL: `http://localhost:8081`
   - Description: The active NGINX landing page showing **Status: Service Running**.

2. **`02_prometheus_targets.png`**:
   - URL: `http://localhost:9090/targets`
   - Description: Prometheus targets dashboard showing both `blackbox` and `prometheus` endpoints in green **UP** status.

3. **`03_prometheus_probe_metric.png`**:
   - URL: `http://localhost:9090/graph?g0.expr=probe_success`
   - Description: PromQL query graph of `probe_success` transitioning from `1` -> `0` (during failure) -> `1` (after recovery).

4. **`04_prometheus_alert_firing.png`**:
   - URL: `http://localhost:9090/alerts`
   - Description: Alert rule `NginxDown` in active **FIRING** state (red badge).

5. **`05_alertmanager_active.png`**:
   - URL: `http://localhost:9093`
   - Description: Alertmanager UI displaying grouped `NginxDown` notification routed to `fastapi-webhook`.

6. **`06_fastapi_swagger_docs.png`**:
   - URL: `http://localhost:8000/docs`
   - Description: FastAPI interactive OpenAPI Swagger documentation for `/webhook`, `/health`, and `/recovery/status`.

7. **`07_fastapi_recovery_status.png`**:
   - URL: `http://localhost:8000/recovery/status`
   - Description: JSON telemetry showing `total_recoveries_triggered`, `duration_seconds`, and Ansible play recap.

8. **`08_powershell_test_execution.png`**:
   - Shell Output: Execution of `.\scripts\test_failure.ps1` with all 6 steps passed in 54 seconds.
