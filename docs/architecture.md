# System Architecture & Design

## 1. Executive Summary

The **Self-Healing Infrastructure** project is an automated, closed-loop resilience framework designed to detect service degradations or outages in real time and automatically remediate them without human intervention.

Built using industry-standard DevOps tools—**Docker, NGINX, Prometheus, Blackbox Exporter, Alertmanager, Python FastAPI, and Ansible**—the system provides autonomous failure recovery while maintaining complete observability.

---

## 2. High-Level Architecture Diagram

```
+----------------------------------------------------------------------------------------------------+
|                                  DOCKER BRIDGE NETWORK (self-healing-net)                          |
|                                                                                                    |
|    +-----------------------------+                                                                 |
|    |      Target Web Server      |                                                                 |
|    |      (self-healing-nginx)   |<---------------+                                                |
|    |      Port 8081:80           |                |                                                |
|    +-----------------------------+                |                                                |
|                   |                               |                                                |
|                   | (HTTP Probe)                  |                                                |
|                   v                               |                                                |
|    +-----------------------------+                |                                                |
|    |      Blackbox Exporter      |                |                                                |
|    |   (self-healing-blackbox)   |                |                                                |
|    |          Port 9115          |                |                                                |
|    +-----------------------------+                |                                                |
|                   |                               |                                                |
|                   | (Scrapes probe_success metric)|                                                |
|                   v                               |                                                |
|    +-----------------------------+                |                                                |
|    |      Prometheus Server      |                |                                                |
|    |  (self-healing-prometheus)  |                |                                                |
|    |          Port 9090          |                |                                                |
|    +-----------------------------+                |                                                |
|                   |                               |                                                |
|                   | (Evaluates NginxDown alert)   |                                                |
|                   v                               |                                                |
|    +-----------------------------+                |                                                |
|    |         Alertmanager        |                |                                                |
|    | (self-healing-alertmanager) |                |                                                |
|    |          Port 9093          |                |                                                |
|    +-----------------------------+                |                                                |
|                   |                               |                                                |
|                   | (Webhook POST /webhook)       |                                                |
|                   v                               |                                                |
|    +-----------------------------+                |                                                |
|    |   FastAPI AutoHealer Engine |                |                                                |
|    | (self-healing-automation)   |                | (Executes Ansible Playbook)                    |
|    |          Port 8000          |----------------+                                                |
|    +-----------------------------+                                                                 |
|                   |                                                                                |
|                   | (Controlled socket access via /var/run/docker.sock)                            |
|                   v                                                                                |
|          [ Docker Daemon Engine ]                                                                  |
+----------------------------------------------------------------------------------------------------+
```

---

## 3. Component Breakdown & Responsibilities

### 3.1 NGINX Web Server (`self-healing-nginx`)
*   **Base Image:** `nginx:1.27-alpine`
*   **Role:** Acts as the mission-critical business application endpoint.
*   **Configuration:** Exposes port `8081` externally (mapped to internal container port `80`). Serves a customized, modern status landing page from a read-only mounted volume (`./nginx/index.html`).
*   **Health Check:** Runs `wget -q -O /dev/null http://127.0.0.1:80/` every 5 seconds.

### 3.2 Prometheus Blackbox Exporter (`self-healing-blackbox`)
*   **Base Image:** `prom/blackbox-exporter:v0.25.0`
*   **Role:** Performs synthetic active probing against HTTP endpoints from the outside.
*   **Configuration:** Configured with an `http_2xx` module. Issues periodic HTTP GET requests to `http://nginx:80` and exposes detailed probe telemetry, including:
    *   `probe_success`: Returns `1` if HTTP 2xx received; returns `0` upon failure, timeout, or connection refusal.
    *   `probe_duration_seconds`: Response latency across DNS, connect, TLS, and transfer phases.

### 3.3 Prometheus Monitoring Server (`self-healing-prometheus`)
*   **Base Image:** `prom/prometheus:v2.54.1`
*   **Role:** Time-series database, metrics scraper, and rule evaluation engine.
*   **Configuration:**
    *   Scrapes Blackbox Exporter probe metrics every 10 seconds.
    *   Evaluates alert rules declared in `/etc/prometheus/alert_rules.yml`.
    *   Maintains persistent storage via Docker volume `prometheus_data`.
    *   Forwards firing alerts to Alertmanager on `alertmanager:9093`.

### 3.4 Alertmanager (`self-healing-alertmanager`)
*   **Base Image:** `prom/alertmanager:v0.27.0`
*   **Role:** Alert deduplication, grouping, routing, and notification dispatch.
*   **Configuration:**
    *   Groups alerts by `alertname` and `service`.
    *   `group_wait: 5s` allows grouping related alerts before sending.
    *   Routes alert notifications via HTTP POST to `http://auto-healer:8000/webhook`.
    *   Includes `send_resolved: true` so the webhook receiver knows when the alert clears.

### 3.5 Automation Engine: FastAPI + Ansible (`self-healing-automation`)
*   **Base Image:** Custom image built on `python:3.11-slim` with static Docker CLI and Ansible installed.
*   **Role:** Webhook ingestion, security validation, idempotency/cooldown management, and Ansible orchestration.
*   **Core Endpoints:**
    *   `POST /webhook`: Validates incoming Alertmanager JSON payloads. Identifies firing `NginxDown` alerts, enforces cooldown limits (default: 30s) to prevent race conditions, and triggers Ansible remediation.
    *   `GET /health`: Returns service health and verifies Docker daemon socket connectivity.
    *   `GET /recovery/status`: Exposes telemetry on total alerts received, recoveries triggered/succeeded, cooldown status, and recent audit logs.
    *   `GET /docs`: Interactive Swagger UI documentation.

### 3.6 Ansible Remediation Engine
*   **Playbook:** `automation/ansible/restart_nginx.yml`
*   **Inventory:** `automation/ansible/inventory.ini` (`localhost ansible_connection=local`)
*   **Role:** The muscle of the self-healing system.
*   **Playbook Workflow:**
    1.  Inspects target container state using `community.docker.docker_container_info`.
    2.  Verifies if the container is stopped or unhealthy.
    3.  Issues a clean start/restart command via `community.docker.docker_container`.
    4.  Re-inspects and strictly asserts that `State.Running == true` and `State.Status == 'running'`.
    5.  Logs detailed recovery metadata (container ID, status, start timestamp).

---

## 4. Security Considerations: Docker Socket Access

### Why Docker Socket Access is Required
The automation container requires communication with `/var/run/docker.sock` to inspect container health and execute restart commands against `self-healing-nginx`.

### Security Implications & Risks
1.  **Host Root Equivalent:** Access to `/var/run/docker.sock` grants root-level privileges over the Docker daemon. A malicious process inside the container could potentially create privileged containers, mount host volumes, or interfere with other containers on the host.
2.  **Blast Radius:** In a multi-tenant environment, granting direct Docker socket access breaks container isolation.

### Mitigations Implemented in this Project
1.  **Controlled Subprocess Execution:** The FastAPI receiver does NOT accept arbitrary shell commands or container names from the webhook request. The target container name is strictly bound to an internal constant (`self-healing-nginx`).
2.  **No Public Socket Exposure:** The Docker socket is mounted strictly into the internal `auto-healer` container and is never published or exposed to external networks.
3.  **Strict Pydantic Validation:** All incoming payloads are structurally validated against strict Pydantic schemas.
4.  **Cooldown Protection:** Rate-limiting prevents denial-of-service or fork-bombing attempts that could exhaust system resources through repeated restarts.
5.  **Production Alternative Note:** In production enterprise environments, Docker socket mounting is typically replaced by:
    *   Kubernetes Operator pattern / Custom Resource Definitions (CRDs).
    *   Role-Based Access Control (RBAC) via the Kubernetes API server.
    *   Remote Docker API secured with TLS client certificate authentication and restricted authorization plugins.
