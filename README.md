# Self-Healing Infrastructure Using Prometheus, Alertmanager, and Ansible

[![Docker](https://img.shields.io/badge/Docker-29.8.0-blue.svg?logo=docker)](https://www.docker.com/)
[![Prometheus](https://img.shields.io/badge/Prometheus-v2.54.1-orange.svg?logo=prometheus)](https://prometheus.io/)
[![Alertmanager](https://img.shields.io/badge/Alertmanager-v0.27.0-red.svg)](https://prometheus.io/docs/alerting/latest/alertmanager/)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.115.0-009688.svg?logo=fastapi)](https://fastapi.tiangolo.com/)
[![Ansible](https://img.shields.io/badge/Ansible-2.17.5-EE0000.svg?logo=ansible)](https://www.ansible.com/)
[![NGINX](https://img.shields.io/badge/NGINX-1.27--alpine-009639.svg?logo=nginx)](https://nginx.org/)

---

## 1. Project Introduction

In modern cloud computing and mission-critical production environments, high availability and low Mean Time to Recovery (MTTR) are vital engineering goals. Manual incident triage and human intervention during service disruptions are slow, error-prone, and costly.

**Self-Healing Infrastructure** is an enterprise-grade DevOps automation project that establishes a closed-loop, self-contained remediation pipeline. When a target service (NGINX) experiences degradation, crash, or stoppage, the system autonomously:
1. **Detects** the failure in real time via synthetic active probes.
2. **Alerts** the monitoring stack with deduplicated, grouped alerts.
3. **Dispatches** an authenticated webhook to a dedicated remediation engine.
4. **Remediates** the service using automated Ansible playbooks over the Docker daemon.
5. **Verifies** service restoration and closes the incident loop without human intervention.

---

## 2. Problem Statement

Traditional operations models rely on human on-call engineers responding to pager alerts (e.g., via SMS, Slack, or PagerDuty). Even in well-tuned environments:
*   Alert generation, triage, routing, and engineer context-switching introduces 5 to 30 minutes of downtime.
*   Transient crashes or hung container states frequently repeat, burning out engineering teams.
*   Manual container restarts are repetitive tasks that are prime candidates for deterministic automation.

**The Solution:** An autonomous self-healing controller that bridges synthetic monitoring with infrastructure-as-code automation, reducing MTTR from minutes down to seconds.

---

## 3. Key Objectives

*   **Continuous Active Probing:** Continuously monitor HTTP endpoint health using Blackbox Exporter rather than relying solely on passive container process metrics.
*   **Zero-Flapping Alerting:** Implement Prometheus alerting rules with deterministic thresholds and failure duration filters.
*   **Secure Webhook Ingestion:** Implement a Python FastAPI microservice that validates payloads, enforces execution cooldowns, and prevents race conditions.
*   **Idempotent Infrastructure Remediation:** Use Ansible playbooks with `community.docker` modules to inspect, restart, and strictly assert container running status.
*   **Full Observability & Auditability:** Expose real-time telemetry, remediation audit logs, and Prometheus metrics throughout the entire incident lifecycle.

---

## 4. Technology Stack

| Technology | Version / Tag | Role in System Architecture |
| :--- | :--- | :--- |
| **NGINX** | `1.27-alpine` | Monitored primary web server serving production landing page. |
| **Blackbox Exporter** | `v0.25.0` | Active synthetic HTTP/TCP prober validating endpoint response codes. |
| **Prometheus** | `v2.54.1` | Time-series database, metrics scraper, and alert evaluation engine. |
| **Alertmanager** | `v0.27.0` | Alert grouping, deduplication, routing, and webhook dispatcher. |
| **Python / FastAPI** | `3.11 / 0.115.0` | High-performance asynchronous webhook controller and telemetry API. |
| **Ansible Core** | `2.17.5` | Automation engine executing real Docker container remediation. |
| **Docker Engine & Compose** | `29.8.0 / 5.5.1` | Container virtualization platform and service orchestration. |
| **PowerShell** | `7.x / 5.1` | Automation scripts for testing, failure injection, and health verification. |

---

## 5. System Architecture

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

## 6. Project Directory Structure

```
self-healing-infrastructure/
│
├── docker-compose.yml              # Multi-container orchestration definition
├── README.md                       # Comprehensive project documentation
├── .gitignore                      # Git repository exclusions
├── .env.example                    # Sample environment variables configuration
│
├── nginx/
│   └── index.html                  # Custom status web page served by NGINX
│
├── prometheus/
│   ├── prometheus.yml              # Prometheus scrape targets & alerting config
│   └── alert_rules.yml             # Alert rule definition (NginxDown)
│
├── blackbox/
│   └── blackbox.yml                # Blackbox Exporter HTTP 2xx prober module
│
├── alertmanager/
│   └── alertmanager.yml            # Alertmanager routing & webhook definition
│
├── automation/
│   ├── Dockerfile                  # Multi-stage image with Python, Docker CLI & Ansible
│   ├── requirements.txt            # Python dependencies (FastAPI, Docker, Ansible)
│   ├── app.py                      # FastAPI webhook receiver & cooldown engine
│   └── ansible/
│       ├── restart_nginx.yml       # Ansible recovery playbook
│       └── inventory.ini           # Ansible local connection inventory
│
├── scripts/
│   ├── start.ps1                   # Builds & launches the complete stack
│   ├── stop.ps1                    # Stops the stack cleanly
│   ├── status.ps1                  # Checks real-time health across all components
│   ├── test_failure.ps1            # Autonomous chaos failure & recovery test
│   └── test_recovery.ps1           # API-level recovery engine inspection
│
├── docs/
│   ├── architecture.md             # Deep-dive architecture & security analysis
│   ├── workflow.md                 # 7-phase operational remediation lifecycle
│   ├── installation.md             # Setup guide & prerequisites
│   └── testing.md                  # Complete testing guide & PromQL references
│
└── screenshots/                    # Dashboard verification evidence
```

---

## 7. Installation & Quick Start

### Prerequisites
*   Windows 10/11 with WSL 2 backend.
*   Docker Desktop running in Linux containers mode.
*   PowerShell 5.1+ or PowerShell 7+.

### Setup Instructions
1. Navigate to the project root:
   ```powershell
   cd C:\Users\ANUPRIYA\self-healing-infrastructure
   ```
2. Build and start the entire stack:
   ```powershell
   .\scripts\start.ps1
   ```
3. Verify running services:
   ```powershell
   .\scripts\status.ps1
   ```

---

## 8. Dashboard URLs & Access Points

| Service | Port | Host URL | Description |
| :--- | :--- | :--- | :--- |
| **NGINX Web Server** | `8081` | [http://localhost:8081](http://localhost:8081) | Production Webpage |
| **Prometheus Dashboard** | `9090` | [http://localhost:9090](http://localhost:9090) | Time-series query interface |
| **Prometheus Targets** | `9090` | [http://localhost:9090/targets](http://localhost:9090/targets) | Active scrape target health |
| **Prometheus Alerts** | `9090` | [http://localhost:9090/alerts](http://localhost:9090/alerts) | Alert rule evaluation states |
| **Blackbox Exporter** | `9115` | [http://localhost:9115](http://localhost:9115) | Active probe telemetry |
| **Alertmanager UI** | `9093` | [http://localhost:9093](http://localhost:9093) | Alert routing and grouping |
| **FastAPI Health** | `8000` | [http://localhost:8000/health](http://localhost:8000/health) | Controller & Docker health |
| **FastAPI Swagger Docs**| `8000` | [http://localhost:8000/docs](http://localhost:8000/docs) | Interactive API Explorer |
| **FastAPI Recovery Status**| `8000` | [http://localhost:8000/recovery/status](http://localhost:8000/recovery/status) | Audit metrics & history |

---

## 9. Key Prometheus Queries

*   `probe_success`: Returns `1` when NGINX is reachable and returning HTTP 2xx; returns `0` upon failure.
*   `up`: Confirms that Prometheus scrapers (`prometheus`, `blackbox`) are actively executing.
*   `ALERTS`: Tracks active Prometheus alerts and their lifecycle state (`pending`, `firing`).
*   `probe_duration_seconds`: Response latency in seconds across all probe phases.

---

## 10. End-to-End Failure Simulation & Verification

To run the automated chaos test that deliberately kills NGINX, detects the outage, triggers Alertmanager and FastAPI, executes Ansible, and verifies recovery:

```powershell
.\scripts\test_failure.ps1
```

### The 11 Verification Gates
1. **Gate 1:** Baseline HTTP 200 response on `http://localhost:8081`.
2. **Gate 2:** Blackbox Exporter reports `probe_success = 1`.
3. **Gate 3:** Prometheus reports all targets `UP`.
4. **Gate 4:** NGINX deliberately stopped (`docker stop self-healing-nginx`).
5. **Gate 5:** `probe_success` drops to `0`.
6. **Gate 6:** Prometheus transitions alert `NginxDown` to **FIRING**.
7. **Gate 7:** Alertmanager routes webhook to FastAPI on `POST /webhook`.
8. **Gate 8:** FastAPI validates alert and initiates Ansible execution.
9. **Gate 9:** Ansible playbook starts container and asserts `running` state.
10. **Gate 10:** NGINX responds with HTTP 200 on port 8081 again.
11. **Gate 11:** Prometheus registers `probe_success = 1` and resolves alert.

---

## 11. Security Considerations

*   **Docker Socket Isolation:** The Docker daemon socket (`/var/run/docker.sock`) is mounted exclusively into the internal `auto-healer` container and is never published to host networks.
*   **Command Injection Prevention:** The FastAPI receiver uses fixed commands and rigid parameter binding. Arbitrary shell commands cannot be injected via webhook payloads.
*   **Cooldown Rate Limiting:** A 30-second cooldown window prevents flapping, race conditions, or denial-of-service from repeated webhook triggers.

---

## 12. Conclusion

This project demonstrates a production-grade implementation of autonomous self-healing infrastructure. By integrating synthetic monitoring with automated Ansible remediation, system resilience is significantly increased while human operational burden is eliminated.
