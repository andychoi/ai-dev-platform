"""
Idle Workspace Monitor
Polls the Coder API for running workspaces and stops those idle beyond a threshold.

Fulfills FR-2.2 (P0): Auto-shutdown idle workspaces
Acceptance criteria (US-5):
  - Configurable idle timeout (default: 30 minutes)
  - Automatic workspace suspension
  - Quick resume (< 1 minute) when contractor returns
  - Cost reporting dashboard (via /status endpoint)

Environment variables:
  CODER_URL            - Coder API base URL (default: http://coder-server:7080)
  CODER_SESSION_TOKEN  - API token with Owner/admin privileges
  IDLE_TIMEOUT_MINUTES - Minutes before a workspace is considered idle (default: 30)
  CHECK_INTERVAL_SECONDS - Seconds between polling cycles (default: 300 = 5 min)
  DRY_RUN              - "true" to log without stopping (default: true)
  LOG_LEVEL            - Python log level (default: INFO)
  GRACE_PERIOD_MINUTES - Minutes after workspace start before idle checks apply (default: 15)
  EXCLUDED_OWNERS      - Comma-separated usernames to never auto-stop (default: "")
"""

import json
import logging
import os
import sys
import time
from datetime import datetime, timezone

import requests
from flask import Flask, jsonify

# =============================================================================
# Configuration
# =============================================================================

CODER_URL = os.environ.get("CODER_URL", "http://coder-server:7080")
CODER_SESSION_TOKEN = os.environ.get("CODER_SESSION_TOKEN", "")
IDLE_TIMEOUT_MINUTES = int(os.environ.get("IDLE_TIMEOUT_MINUTES", "30"))
CHECK_INTERVAL_SECONDS = int(os.environ.get("CHECK_INTERVAL_SECONDS", "300"))
DRY_RUN = os.environ.get("DRY_RUN", "true").lower() == "true"
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO").upper()
GRACE_PERIOD_MINUTES = int(os.environ.get("GRACE_PERIOD_MINUTES", "15"))
EXCLUDED_OWNERS = [
    o.strip()
    for o in os.environ.get("EXCLUDED_OWNERS", "").split(",")
    if o.strip()
]

# =============================================================================
# Logging — structured JSON for audit trail
# =============================================================================


class JsonFormatter(logging.Formatter):
    def format(self, record):
        log_entry = {
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "level": record.levelname,
            "message": record.getMessage(),
        }
        if hasattr(record, "extra"):
            log_entry.update(record.extra)
        return json.dumps(log_entry)


logger = logging.getLogger("idle-monitor")
logger.setLevel(getattr(logging, LOG_LEVEL, logging.INFO))
handler = logging.StreamHandler(sys.stdout)
handler.setFormatter(JsonFormatter())
logger.addHandler(handler)

# =============================================================================
# State — track what we've done for the /status endpoint
# =============================================================================

monitor_state = {
    "started_at": datetime.now(timezone.utc).isoformat(),
    "last_check": None,
    "total_checks": 0,
    "total_stops": 0,
    "recent_actions": [],  # last 50 actions
    "idle_workspaces": [],  # current idle workspace snapshot
    "config": {
        "idle_timeout_minutes": IDLE_TIMEOUT_MINUTES,
        "check_interval_seconds": CHECK_INTERVAL_SECONDS,
        "dry_run": DRY_RUN,
        "grace_period_minutes": GRACE_PERIOD_MINUTES,
        "excluded_owners": EXCLUDED_OWNERS,
    },
}

# =============================================================================
# Coder API helpers
# =============================================================================


def coder_headers():
    return {
        "Coder-Session-Token": CODER_SESSION_TOKEN,
        "Accept": "application/json",
    }


def get_running_workspaces():
    """Fetch all running workspaces from Coder API."""
    workspaces = []
    offset = 0
    limit = 50

    while True:
        resp = requests.get(
            f"{CODER_URL}/api/v2/workspaces",
            headers=coder_headers(),
            params={"offset": offset, "limit": limit},
            timeout=30,
        )
        resp.raise_for_status()
        data = resp.json()

        for ws in data.get("workspaces", []):
            latest_build = ws.get("latest_build", {})
            status = latest_build.get("status", "")
            if status == "running":
                workspaces.append(ws)

        total = data.get("count", 0)
        offset += limit
        if offset >= total:
            break

    return workspaces


def stop_workspace(workspace_id, workspace_name):
    """Stop a workspace by creating a new build with transition=stop."""
    resp = requests.post(
        f"{CODER_URL}/api/v2/workspaces/{workspace_id}/builds",
        headers=coder_headers(),
        json={"transition": "stop"},
        timeout=30,
    )
    resp.raise_for_status()
    return resp.json()


# =============================================================================
# Core idle detection logic
# =============================================================================


def parse_timestamp(ts_str):
    """Parse an ISO 8601 timestamp string into a timezone-aware datetime."""
    if not ts_str:
        return None
    ts_str = ts_str.replace("Z", "+00:00")
    return datetime.fromisoformat(ts_str)


def check_idle_workspaces():
    """
    Main check loop iteration:
    1. Fetch running workspaces
    2. Determine which are idle beyond threshold
    3. Stop them (or log if dry-run)
    """
    now = datetime.now(timezone.utc)
    monitor_state["last_check"] = now.isoformat()
    monitor_state["total_checks"] += 1

    try:
        running = get_running_workspaces()
    except requests.RequestException as e:
        logger.error(
            "Failed to fetch workspaces from Coder API",
            extra={"extra": {"error": str(e), "coder_url": CODER_URL}},
        )
        return

    logger.info(
        "Workspace check cycle",
        extra={"extra": {"running_count": len(running), "check_number": monitor_state["total_checks"]}},
    )

    idle_workspaces = []

    for ws in running:
        ws_id = ws.get("id", "")
        ws_name = ws.get("name", "")
        owner = ws.get("owner_name", "")
        last_used_at = parse_timestamp(ws.get("last_used_at"))
        latest_build = ws.get("latest_build", {})
        build_created = parse_timestamp(latest_build.get("created_at"))

        # Skip excluded owners
        if owner in EXCLUDED_OWNERS:
            continue

        # Grace period: don't stop recently started workspaces
        if build_created and (now - build_created).total_seconds() < GRACE_PERIOD_MINUTES * 60:
            continue

        # Determine idle duration
        if last_used_at:
            idle_seconds = (now - last_used_at).total_seconds()
            idle_minutes = idle_seconds / 60
        else:
            # No last_used_at — use build creation time as fallback
            if build_created:
                idle_seconds = (now - build_created).total_seconds()
                idle_minutes = idle_seconds / 60
            else:
                continue  # Can't determine idle time, skip

        if idle_minutes >= IDLE_TIMEOUT_MINUTES:
            idle_workspaces.append({
                "id": ws_id,
                "name": ws_name,
                "owner": owner,
                "idle_minutes": round(idle_minutes, 1),
                "last_used_at": ws.get("last_used_at", ""),
            })

    # Update state snapshot
    monitor_state["idle_workspaces"] = idle_workspaces

    if not idle_workspaces:
        logger.info("No idle workspaces found")
        return

    logger.info(
        "Idle workspaces detected",
        extra={"extra": {"count": len(idle_workspaces), "dry_run": DRY_RUN}},
    )

    for idle_ws in idle_workspaces:
        action_record = {
            "timestamp": now.isoformat(),
            "workspace_id": idle_ws["id"],
            "workspace_name": idle_ws["name"],
            "owner": idle_ws["owner"],
            "idle_minutes": idle_ws["idle_minutes"],
            "dry_run": DRY_RUN,
            "action": "stop" if not DRY_RUN else "would_stop",
        }

        if DRY_RUN:
            logger.info(
                f"[DRY-RUN] Would stop workspace '{idle_ws['name']}' "
                f"(owner={idle_ws['owner']}, idle={idle_ws['idle_minutes']}m)",
                extra={"extra": action_record},
            )
        else:
            try:
                stop_workspace(idle_ws["id"], idle_ws["name"])
                monitor_state["total_stops"] += 1
                logger.info(
                    f"Stopped workspace '{idle_ws['name']}' "
                    f"(owner={idle_ws['owner']}, idle={idle_ws['idle_minutes']}m)",
                    extra={"extra": action_record},
                )
            except requests.RequestException as e:
                action_record["action"] = "stop_failed"
                action_record["error"] = str(e)
                logger.error(
                    f"Failed to stop workspace '{idle_ws['name']}': {e}",
                    extra={"extra": action_record},
                )

        # Keep last 50 actions
        monitor_state["recent_actions"].append(action_record)
        if len(monitor_state["recent_actions"]) > 50:
            monitor_state["recent_actions"] = monitor_state["recent_actions"][-50:]


# =============================================================================
# Flask API — health, status, config endpoints
# =============================================================================

api = Flask(__name__)


@api.route("/health")
def health():
    """Health check for Docker/monitoring."""
    if not CODER_SESSION_TOKEN:
        return jsonify({"status": "unhealthy", "reason": "CODER_SESSION_TOKEN not set"}), 503
    return jsonify({"status": "healthy", "dry_run": DRY_RUN})


@api.route("/status")
def status():
    """Current monitor status: idle workspaces, recent actions, counters."""
    return jsonify(monitor_state)


@api.route("/config")
def config():
    """Current configuration (read-only)."""
    return jsonify(monitor_state["config"])


# =============================================================================
# Main loop
# =============================================================================


def run_monitor_loop():
    """Background thread: poll Coder API on interval."""
    if not CODER_SESSION_TOKEN:
        logger.error(
            "CODER_SESSION_TOKEN is not set. Cannot monitor workspaces. "
            "Set this to an admin/owner session token."
        )
        # Keep running so the health endpoint reports unhealthy
        while True:
            time.sleep(60)

    logger.info(
        "Idle monitor started",
        extra={
            "extra": {
                "idle_timeout_minutes": IDLE_TIMEOUT_MINUTES,
                "check_interval_seconds": CHECK_INTERVAL_SECONDS,
                "dry_run": DRY_RUN,
                "grace_period_minutes": GRACE_PERIOD_MINUTES,
                "excluded_owners": EXCLUDED_OWNERS,
                "coder_url": CODER_URL,
            }
        },
    )

    while True:
        try:
            check_idle_workspaces()
        except Exception:
            logger.exception("Unexpected error in check cycle")
        time.sleep(CHECK_INTERVAL_SECONDS)


if __name__ == "__main__":
    import threading

    # Start monitor loop in background thread
    monitor_thread = threading.Thread(target=run_monitor_loop, daemon=True)
    monitor_thread.start()

    # Start Flask API server
    api.run(host="0.0.0.0", port=8200, debug=False)
