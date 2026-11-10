import os
import time
import logging
import subprocess
from datetime import datetime, timezone
from typing import List, Dict, Any, Optional

import docker
from fastapi import FastAPI, HTTPException, Request, status
from fastapi.responses import JSONResponse
from pydantic import BaseModel, Field

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [AutoHealer] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("AutoHealer")

app = FastAPI(
    title="Self-Healing Infrastructure Automation Engine",
    description="Webhook Receiver and Automated Remediation Controller powered by FastAPI and Ansible.",
    version="1.0.0",
)

# Configuration & State Management
COOLDOWN_SECONDS = int(os.getenv("RECOVERY_COOLDOWN_SECONDS", "30"))
ANSIBLE_PLAYBOOK_PATH = os.getenv("ANSIBLE_PLAYBOOK_PATH", "ansible/restart_nginx.yml")
ANSIBLE_INVENTORY_PATH = os.getenv("ANSIBLE_INVENTORY_PATH", "ansible/inventory.ini")
TARGET_CONTAINER_DEFAULT = "self-healing-nginx"

# In-memory metrics & history tracking
recovery_state: Dict[str, Any] = {
    "total_webhooks_received": 0,
    "total_firing_alerts": 0,
    "total_resolved_alerts": 0,
    "total_recoveries_triggered": 0,
    "total_recoveries_succeeded": 0,
    "total_recoveries_failed": 0,
    "total_cooldown_skips": 0,
    "last_recovery_timestamp": None,
    "last_recovery_result": None,
    "in_progress": False,
    "history": [],
}


# Pydantic models for Alertmanager payload validation
class AlertItem(BaseModel):
    status: str
    labels: Dict[str, str] = Field(default_factory=dict)
    annotations: Dict[str, str] = Field(default_factory=dict)
    startsAt: Optional[str] = None
    endsAt: Optional[str] = None
    generatorURL: Optional[str] = None
    fingerprint: Optional[str] = None


class AlertmanagerWebhook(BaseModel):
    receiver: str
    status: str
    alerts: List[AlertItem] = Field(default_factory=list)
    groupLabels: Dict[str, str] = Field(default_factory=dict)
    commonLabels: Dict[str, str] = Field(default_factory=dict)
    commonAnnotations: Dict[str, str] = Field(default_factory=dict)
    externalURL: Optional[str] = None
    version: Optional[str] = None
    groupKey: Optional[str] = None


def check_docker_connectivity() -> bool:
    """Verifies that the Docker daemon socket is accessible inside the container."""
    try:
        client = docker.DockerClient(base_url="unix:///var/run/docker.sock")
        client.ping()
        return True
    except Exception as ex:
        logger.warning(f"Docker ping failed: {ex}")
        return False


def execute_ansible_recovery(target_container: str) -> Dict[str, Any]:
    """
    Executes the Ansible recovery playbook via a controlled, hardened subprocess.
    Arbitrary command execution is strictly prevented by using fixed commands and parameter binding.
    """
    cmd = [
        "ansible-playbook",
        "-i",
        ANSIBLE_INVENTORY_PATH,
        ANSIBLE_PLAYBOOK_PATH,
        "-e",
        f"container_name={target_container}",
    ]

    start_time = time.time()
    logger.info(f"Executing Ansible playbook: {' '.join(cmd)}")

    try:
        result = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
        )
        duration = round(time.time() - start_time, 2)
        success = (result.returncode == 0)

        record = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "target": target_container,
            "success": success,
            "returncode": result.returncode,
            "duration_seconds": duration,
            "stdout": result.stdout,
            "stderr": result.stderr,
        }

        if success:
            logger.info(f"Ansible playbook succeeded in {duration}s for container {target_container}")
        else:
            logger.error(f"Ansible playbook failed in {duration}s (code {result.returncode}): {result.stderr}")

        return record

    except subprocess.TimeoutExpired:
        duration = round(time.time() - start_time, 2)
        logger.error(f"Ansible playbook timed out after {duration}s")
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "target": target_container,
            "success": False,
            "returncode": -1,
            "duration_seconds": duration,
            "stdout": "",
            "stderr": "Execution timed out after 120 seconds",
        }
    except Exception as ex:
        duration = round(time.time() - start_time, 2)
        logger.error(f"Unexpected exception during Ansible run: {ex}")
        return {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "target": target_container,
            "success": False,
            "returncode": -2,
            "duration_seconds": duration,
            "stdout": "",
            "stderr": str(ex),
        }


@app.get("/health", summary="Health Check Endpoint")
def get_health():
    """Returns the operational status of the AutoHealer service and Docker socket connection."""
    docker_ok = check_docker_connectivity()
    return {
        "status": "healthy" if docker_ok else "degraded",
        "service": "self-healing-automation",
        "docker_socket_connected": docker_ok,
        "cooldown_seconds": COOLDOWN_SECONDS,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@app.get("/recovery/status", summary="Remediation Statistics & History")
def get_recovery_status():
    """Returns telemetry on webhook events, recovery executions, cooldown state, and event history."""
    now = time.time()
    last_ts = recovery_state["last_recovery_timestamp"]
    cooldown_remaining = 0

    if last_ts is not None:
        elapsed = now - last_ts
        if elapsed < COOLDOWN_SECONDS:
            cooldown_remaining = round(COOLDOWN_SECONDS - elapsed, 1)

    return {
        "metrics": {
            "total_webhooks_received": recovery_state["total_webhooks_received"],
            "total_firing_alerts": recovery_state["total_firing_alerts"],
            "total_resolved_alerts": recovery_state["total_resolved_alerts"],
            "total_recoveries_triggered": recovery_state["total_recoveries_triggered"],
            "total_recoveries_succeeded": recovery_state["total_recoveries_succeeded"],
            "total_recoveries_failed": recovery_state["total_recoveries_failed"],
            "total_cooldown_skips": recovery_state["total_cooldown_skips"],
        },
        "cooldown": {
            "configured_cooldown_seconds": COOLDOWN_SECONDS,
            "cooldown_active": cooldown_remaining > 0,
            "cooldown_remaining_seconds": cooldown_remaining,
        },
        "in_progress": recovery_state["in_progress"],
        "last_recovery_result": recovery_state["last_recovery_result"],
        "recent_history": recovery_state["history"][-10:],
    }


@app.post("/webhook", summary="Alertmanager Webhook Receiver")
async def receive_alert(webhook_data: AlertmanagerWebhook):
    """
    Receives alerts from Alertmanager.
    - Filters for firing NginxDown alerts.
    - Silently acknowledges resolved alerts without triggering actions.
    - Prevents race conditions and duplicate executions via cooldown tracking.
    - Dispatches Ansible playbook to restart the failed container.
    """
    recovery_state["total_webhooks_received"] += 1
    logger.info(
        f"Webhook received! Receiver: '{webhook_data.receiver}', "
        f"Status: '{webhook_data.status}', Total Alerts: {len(webhook_data.alerts)}"
    )

    remediation_results = []
    actions_taken = 0

    for alert in webhook_data.alerts:
        alert_name = alert.labels.get("alertname", "Unknown")
        service = alert.labels.get("service", "unknown")
        alert_status = alert.status.lower()

        logger.info(f"Evaluating Alert: name='{alert_name}', service='{service}', status='{alert_status}'")

        # 1. Ignore resolved alerts for remediation
        if alert_status == "resolved":
            recovery_state["total_resolved_alerts"] += 1
            logger.info(f"Alert '{alert_name}' is resolved. Skipping recovery action.")
            continue

        if alert_status == "firing":
            recovery_state["total_firing_alerts"] += 1

            # 2. Check if this alert targets NGINX
            if alert_name == "NginxDown" or service == "nginx":
                target_container = TARGET_CONTAINER_DEFAULT

                # 3. Check cooldown protection to prevent duplicate rapid executions
                now = time.time()
                last_ts = recovery_state["last_recovery_timestamp"]

                if last_ts is not None and (now - last_ts) < COOLDOWN_SECONDS:
                    elapsed = round(now - last_ts, 1)
                    recovery_state["total_cooldown_skips"] += 1
                    logger.warning(
                        f"Cooldown active ({elapsed}s < {COOLDOWN_SECONDS}s). "
                        f"Skipping duplicate recovery trigger for '{target_container}'."
                    )
                    remediation_results.append({
                        "alert": alert_name,
                        "action": "skipped_due_to_cooldown",
                        "cooldown_remaining": round(COOLDOWN_SECONDS - elapsed, 1),
                    })
                    continue

                if recovery_state["in_progress"]:
                    logger.warning("Another remediation is currently in progress. Skipping.")
                    remediation_results.append({
                        "alert": alert_name,
                        "action": "skipped_already_in_progress",
                    })
                    continue

                # 4. Trigger Ansible recovery
                recovery_state["in_progress"] = True
                recovery_state["total_recoveries_triggered"] += 1
                recovery_state["last_recovery_timestamp"] = now

                try:
                    record = execute_ansible_recovery(target_container)
                    if record["success"]:
                        recovery_state["total_recoveries_succeeded"] += 1
                    else:
                        recovery_state["total_recoveries_failed"] += 1

                    recovery_state["last_recovery_result"] = {
                        "timestamp": record["timestamp"],
                        "success": record["success"],
                        "target": record["target"],
                        "duration_seconds": record["duration_seconds"],
                    }

                    recovery_state["history"].append(record)
                    remediation_results.append({
                        "alert": alert_name,
                        "action": "remediation_executed",
                        "target": target_container,
                        "success": record["success"],
                        "duration": record["duration_seconds"],
                    })
                    actions_taken += 1

                finally:
                    recovery_state["in_progress"] = False

    return JSONResponse(
        status_code=status.HTTP_200_OK,
        content={
            "status": "processed",
            "actions_taken": actions_taken,
            "results": remediation_results,
            "server_time": datetime.now(timezone.utc).isoformat(),
        },
    )
