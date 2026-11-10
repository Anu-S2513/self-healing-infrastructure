# Installation, Setup & Operational Guide

## 1. Prerequisites

Before running the Self-Healing Infrastructure, ensure your host environment meets the following minimum requirements:

*   **Operating System:** Windows 10/11 (64-bit), macOS, or Linux.
*   **Virtualization:** WSL 2 (Windows Subsystem for Linux) backend enabled.
*   **Container Platform:** Docker Desktop (v20.10+ or v24+) with Linux containers mode active.
*   **Compose:** Docker Compose v2.0+.
*   **Shell:** PowerShell 5.1+ (or PowerShell 7+) on Windows, or Bash on Linux/macOS.
*   **Ports Available:** Verify that ports `8081`, `9090`, `9115`, `9093`, and `8000` are free on the host.

---

## 2. Quick-Start Setup Procedure

### Step 1: Open Terminal in Project Root
Open PowerShell and navigate to the project directory:
```powershell
cd C:\Users\ANUPRIYA\self-healing-infrastructure
```

### Step 2: Review Environment Variables
Copy and inspect `.env.example` if custom port overrides are required:
```powershell
Copy-Item .env.example .env
```

### Step 3: Launch the Infrastructure Stack
Execute the provided automated initialization script:
```powershell
.\scripts\start.ps1
```
*Or execute directly with Docker Compose:*
```powershell
docker compose up -d --build
```

### Step 4: Validate Service Health
Check the operational status of all containers and endpoints:
```powershell
.\scripts\status.ps1
```

---

## 3. Accessible Dashboards & Interfaces

Once the stack is started, the following web interfaces are available:

| Service | Host URL | Description |
| :--- | :--- | :--- |
| **NGINX Web Server** | [http://localhost:8081](http://localhost:8081) | Custom Self-Healing status web page |
| **Prometheus Dashboard** | [http://localhost:9090](http://localhost:9090) | Time-series query interface and graphs |
| **Prometheus Targets** | [http://localhost:9090/targets](http://localhost:9090/targets) | Active scrape targets (`prometheus`, `blackbox`) |
| **Prometheus Alerts** | [http://localhost:9090/alerts](http://localhost:9090/alerts) | Rule status (`NginxDown`: Inactive / Pending / Firing) |
| **Blackbox Exporter** | [http://localhost:9115](http://localhost:9115) | Probe metrics and debugging interface |
| **Alertmanager UI** | [http://localhost:9093](http://localhost:9093) | Alert routing, grouping, and active alerts |
| **FastAPI Health** | [http://localhost:8000/health](http://localhost:8000/health) | Automation engine health & Docker socket status |
| **FastAPI Swagger Docs**| [http://localhost:8000/docs](http://localhost:8000/docs) | Interactive OpenAPI / Swagger UI |
| **FastAPI Recovery Info**| [http://localhost:8000/recovery/status](http://localhost:8000/recovery/status) | Audit metrics, cooldown state, and event history |

---

## 4. Stopping the Infrastructure

To stop all services cleanly without deleting persistent Prometheus data:
```powershell
.\scripts\stop.ps1
```

To remove containers and volumes completely:
```powershell
docker compose down -v
```
