# Autonomous Self-Healing Lifecycle & Workflow

## 1. Overview

The Self-Healing Infrastructure functions as a continuous closed feedback loop. This document walks through the 7-phase operational lifecycle, tracing what occurs from the instant an outage is introduced to full automatic recovery.

---

## 2. Remediation Sequence Diagram

```
[ NGINX Service ]     [ Blackbox Exporter ]     [ Prometheus ]     [ Alertmanager ]     [ FastAPI Receiver ]     [ Ansible Engine ]     [ Docker Socket ]
       |                       |                       |                  |                      |                       |                       |
       |  -- Service Fails --  |                       |                  |                      |                       |                       |
       |   (Crash / Stopped)   |                       |                  |                      |                       |                       |
       |                       |                       |                  |                      |                       |                       |
       | <--- HTTP GET Probe --|                       |                  |                      |                       |                       |
       |      (Connection Refused)                     |                  |                      |                       |                       |
       |                       |                       |                  |                      |                       |                       |
       |                       | (probe_success == 0)  |                  |                      |                       |                       |
       |                       |---------------------->|                  |                      |                       |                       |
       |                       |  Scraped every 10s    |                  |                      |                       |                       |
       |                       |                       |                  |                      |                       |                       |
       |                       |                       | Evaluates rule   |                      |                       |                       |
       |                       |                       | NginxDown for 30s|                      |                       |                       |
       |                       |                       | Alert: FIRING    |                      |                       |                       |
       |                       |                       |----------------->|                      |                       |                       |
       |                       |                       | Dispatches alert |                      |                       |                       |
       |                       |                       |                  |                      |                       |                       |
       |                       |                       |                  | Groups & routes      |                       |                       |
       |                       |                       |                  | POST /webhook        |                       |                       |
       |                       |                       |                  |--------------------->|                       |                       |
       |                       |                       |                  |                      |                       |                       |
       |                       |                       |                  |                      | Validates JSON        |                       |
       |                       |                       |                  |                      | Checks Cooldown (30s) |                       |
       |                       |                       |                  |                      | Runs playbook         |                       |
       |                       |                       |                  |                      |---------------------->|                       |
       |                       |                       |                  |                      |                       |                       |
       |                       |                       |                  |                      |                       | docker_container_info |
       |                       |                       |                  |                      |                       |---------------------->|
       |                       |                       |                  |                      |                       |<----------------------|
       |                       |                       |                  |                      |                       | Container Stopped     |
       |                       |                       |                  |                      |                       |                       |
       |                       |                       |                  |                      |                       | docker_container      |
       |                       |                       |                  |                      |                       | (state: started)      |
       |                       |                       |                  |                      |                       |---------------------->|
       |<----------------------------------------------------------------------------------------------------------------| Restarts Container    |
       |                       |                       |                  |                      |                       |                       |
       |                       |                       |                  |                      |                       | Asserts Running: True |
       |                       |                       |                  |                      | Playbook SUCCESS      |                       |
       |                       |                       |                  |                      |<----------------------|                       |
       |                       |                       |                  |                      |                       |                       |
       | <--- HTTP GET Probe --|                       |                  | Logs audit & updates |                       |                       |
       |      (HTTP 200 OK)    |                       |                  | recovery stats       |                       |                       |
       |---------------------->|                       |                  |                      |                       |                       |
       |                       | (probe_success == 1)  |                  |                      |                       |                       |
       |                       |---------------------->|                  |                      |                       |                       |
       |                       | Scraped by Prometheus |                  |                      |                       |                       |
       |                       |                       | Alert CLEARED    |                      |                       |                       |
       |                       |                       | (Resolved)       |                      |                       |                       |
       |                       |                       |----------------->|                      |                       |                       |
       |                       |                       |                  | POST /webhook        |                       |                       |
       |                       |                       |                  | (status: resolved)   |                       |                       |
       |                       |                       |                  |--------------------->|                       |                       |
       |                       |                       |                  |                      | Logged (No action)    |                       |
```

---

## 3. Step-by-Step Phase Breakdown

### Phase 1: Failure Injected
*   The NGINX web server container stops unexpectedly (or is intentionally stopped via `docker stop self-healing-nginx`).
*   TCP port 8081 stops accepting connections on the host, and port 80 becomes unreachable on the internal Docker bridge network `self-healing-net`.

### Phase 2: Synthetic Probing & Failure Detection
*   Blackbox Exporter periodically sends HTTP GET requests to `http://nginx:80` with a 5-second timeout.
*   Upon connection failure or refusal, Blackbox Exporter immediately registers:
    *   `probe_success = 0`
    *   `probe_http_status_code = 0`

### Phase 3: Prometheus Alert Evaluation
*   Prometheus scrapes the Blackbox Exporter metrics endpoint (`/probe?target=http://nginx:80&module=http_2xx`) every 10 seconds.
*   Prometheus detects that `probe_success{job="blackbox"} == 0`.
*   The alert rule `NginxDown` transitions from **INACTIVE** to **PENDING**.
*   After the condition persists for 30 seconds (`for: 30s`), Prometheus transitions `NginxDown` to **FIRING**.
*   Prometheus immediately delivers the firing alert payload to Alertmanager (`alertmanager:9093`).

### Phase 4: Alertmanager Grouping & Dispatch
*   Alertmanager receives the alert and evaluates routing rules defined in `alertmanager.yml`.
*   Alertmanager groups alerts by `alertname` and `service`, waits `group_wait: 5s` for any related alerts, and dispatches an HTTP POST payload to `http://auto-healer:8000/webhook`.

### Phase 5: FastAPI Webhook Handling & Validation
*   The FastAPI application listens on port 8000.
*   The request body is parsed and validated against the `AlertmanagerWebhook` Pydantic model.
*   The handler iterates through the alerts:
    *   If `alert.status == "resolved"`: logs as informational and takes no action.
    *   If `alert.status == "firing"` and `alert.labels.alertname == "NginxDown"`:
        *   Checks cooldown lock. If less than 30 seconds have elapsed since the last recovery, skips to prevent flapping.
        *   If cooldown has passed, initiates asynchronous Ansible execution.

### Phase 6: Ansible Remediation Execution
*   FastAPI invokes:
    ```bash
    ansible-playbook -i ansible/inventory.ini ansible/restart_nginx.yml -e "container_name=self-healing-nginx"
    ```
*   The Ansible playbook executes tasks in sequence:
    1.  Inspects container `self-healing-nginx` via `community.docker.docker_container_info`.
    2.  Observes container `State.Running == false`.
    3.  Issues `community.docker.docker_container` with `state: started`.
    4.  Pauses for 2 seconds to allow the entrypoint script to initialize NGINX.
    5.  Re-inspects and validates with `ansible.builtin.assert` that `State.Running == true`.
    6.  Emits structured output containing the container ID, start timestamp, and exit code.

### Phase 7: Verification & Alert Resolution
*   The NGINX container is now healthy and serving HTTP 200 on port 80 (and host port 8081).
*   Blackbox Exporter probes `http://nginx:80` and records `probe_success = 1`.
*   Prometheus scrapes the updated metric and clears the `NginxDown` alert.
*   Alertmanager notifies FastAPI of resolution (`status: resolved`), concluding the self-healing cycle.
