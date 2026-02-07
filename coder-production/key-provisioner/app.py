"""
Key Provisioner Service

Isolates the LiteLLM master key from workspace containers.
Workspaces authenticate with PROVISIONER_SECRET and receive
scoped virtual keys with budget/rate-limit constraints.

Endpoints:
  POST /api/v1/keys/workspace     - Auto-provision workspace key (idempotent)
  POST /api/v1/keys/self-service  - Generate personal key (Coder token auth)
  GET  /api/v1/keys/info          - Get key usage/budget info
  POST /api/v1/keys/reset-user    - Reset user spend (admin-only)
  GET  /api/v1/keys/list          - List all keys (admin-only)
  GET  /health                    - Health check
"""

import json
import logging
import os
from datetime import datetime, timezone
from functools import wraps

import requests
from flask import Flask, jsonify, request

app = Flask(__name__)
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

LITELLM_URL = os.environ.get("LITELLM_URL", "http://litellm:4000")
LITELLM_MASTER_KEY = os.environ.get("LITELLM_MASTER_KEY", "")
PROVISIONER_SECRET = os.environ.get("PROVISIONER_SECRET", "")
CODER_URL = os.environ.get("CODER_URL", "http://coder-server:7080")

# Scope defaults (budget USD, RPM, duration days)
SCOPE_DEFAULTS = {
    "workspace": {"budget": 10.0, "rpm": 60, "duration_days": 30},
    "user":      {"budget": 20.0, "rpm": 100, "duration_days": 90},
    "ci":        {"budget": 5.0,  "rpm": 30, "duration_days": 365},
    "agent:review": {"budget": 15.0, "rpm": 40, "duration_days": 365},
    "agent:write":  {"budget": 30.0, "rpm": 60, "duration_days": 365},
}

# ---------------------------------------------------------------------------
# Auth helpers
# ---------------------------------------------------------------------------


def require_provisioner_secret(f):
    """Require Bearer <PROVISIONER_SECRET> on the request."""
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer ") or auth[7:] != PROVISIONER_SECRET:
            return jsonify({"error": "unauthorized"}), 401
        return f(*args, **kwargs)
    return decorated


def require_litellm_key(f):
    """Require any valid LiteLLM key on the request (validated via LiteLLM)."""
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            return jsonify({"error": "unauthorized"}), 401
        # Store the key for downstream use
        request.litellm_key = auth[7:]
        return f(*args, **kwargs)
    return decorated


# ---------------------------------------------------------------------------
# LiteLLM helpers
# ---------------------------------------------------------------------------


def _litellm_headers():
    return {
        "Authorization": f"Bearer {LITELLM_MASTER_KEY}",
        "Content-Type": "application/json",
    }


def _find_existing_key(alias):
    """Check if a key with the given alias already exists. Return key token or None."""
    try:
        resp = requests.post(
            f"{LITELLM_URL}/key/info",
            headers=_litellm_headers(),
            json={"key_alias": alias},
            timeout=10,
        )
        if resp.status_code == 200:
            data = resp.json()
            info = data.get("info", data.get("key_info", {}))
            if isinstance(info, dict) and info.get("token"):
                return info["token"]
    except Exception as e:
        log.warning("Error checking existing key alias=%s: %s", alias, e)
    return None


def _generate_key(alias, user_id, budget, rpm, metadata, models=None):
    """Generate a new LiteLLM virtual key."""
    payload = {
        "key_alias": alias,
        "user_id": user_id,
        "max_budget": budget,
        "tpm_limit": None,
        "rpm_limit": rpm,
        "metadata": metadata,
    }
    if models:
        payload["models"] = models

    resp = requests.post(
        f"{LITELLM_URL}/key/generate",
        headers=_litellm_headers(),
        json=payload,
        timeout=15,
    )
    if resp.status_code not in (200, 201):
        log.error("LiteLLM /key/generate failed: %s %s", resp.status_code, resp.text)
        return None, resp.text
    data = resp.json()
    return data.get("key"), None


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@app.route("/health", methods=["GET"])
def health():
    """Health check — also verifies LiteLLM connectivity."""
    try:
        resp = requests.get(f"{LITELLM_URL}/health/readiness", timeout=5)
        litellm_ok = resp.status_code == 200
    except Exception:
        litellm_ok = False

    status = "ok" if litellm_ok else "degraded"
    code = 200 if litellm_ok else 503
    return jsonify({"status": status, "litellm": litellm_ok}), code


@app.route("/api/v1/keys/workspace", methods=["POST"])
@require_provisioner_secret
def create_workspace_key():
    """
    Auto-provision a workspace key. Idempotent — returns existing key on restart.

    Body:
      workspace_id (required): Coder workspace ID
      username (required): Workspace owner username
      workspace_name (optional): Human-readable workspace name
    """
    body = request.get_json(silent=True) or {}
    workspace_id = body.get("workspace_id", "").strip()
    username = body.get("username", "").strip()
    workspace_name = body.get("workspace_name", "")

    if not workspace_id or not username:
        return jsonify({"error": "workspace_id and username are required"}), 400

    alias = f"workspace-{workspace_id}"
    defaults = SCOPE_DEFAULTS["workspace"]

    # Idempotent: check if key already exists
    existing = _find_existing_key(alias)
    if existing:
        log.info("Reusing existing key for workspace=%s user=%s", workspace_id, username)
        return jsonify({"key": existing, "reused": True})

    metadata = {
        "scope": f"workspace:{workspace_id}",
        "key_type": "workspace",
        "created_by": "key-provisioner",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "workspace_id": workspace_id,
        "workspace_owner": username,
        "workspace_name": workspace_name,
        "purpose": "auto-provisioned workspace key",
    }

    key, err = _generate_key(
        alias=alias,
        user_id=username,
        budget=defaults["budget"],
        rpm=defaults["rpm"],
        metadata=metadata,
    )
    if not key:
        return jsonify({"error": f"Failed to generate key: {err}"}), 502

    log.info("Generated workspace key for workspace=%s user=%s", workspace_id, username)
    return jsonify({"key": key, "reused": False}), 201


@app.route("/api/v1/keys/self-service", methods=["POST"])
def create_self_service_key():
    """
    Generate a personal key. Authenticated via Coder session token.

    Headers:
      Authorization: Bearer <coder-session-token>
    Body:
      purpose (optional): Description of key usage
    """
    auth = request.headers.get("Authorization", "")
    if not auth.startswith("Bearer "):
        return jsonify({"error": "unauthorized"}), 401
    coder_token = auth[7:]

    # Validate Coder session token and get username
    try:
        resp = requests.get(
            f"{CODER_URL}/api/v2/users/me",
            headers={"Coder-Session-Token": coder_token},
            timeout=10,
            verify=False,
        )
        if resp.status_code != 200:
            return jsonify({"error": "invalid Coder session token"}), 401
        user_info = resp.json()
        username = user_info.get("username", "")
        if not username:
            return jsonify({"error": "could not determine username"}), 401
    except Exception as e:
        log.error("Coder auth failed: %s", e)
        return jsonify({"error": "failed to validate Coder token"}), 502

    body = request.get_json(silent=True) or {}
    purpose = body.get("purpose", "personal experimentation")
    alias = f"user-{username}"
    defaults = SCOPE_DEFAULTS["user"]

    # Idempotent
    existing = _find_existing_key(alias)
    if existing:
        log.info("Reusing existing self-service key for user=%s", username)
        return jsonify({"key": existing, "reused": True})

    metadata = {
        "scope": f"user:{username}",
        "key_type": "user",
        "created_by": "key-provisioner",
        "created_at": datetime.now(timezone.utc).isoformat(),
        "username": username,
        "purpose": purpose,
    }

    key, err = _generate_key(
        alias=alias,
        user_id=username,
        budget=defaults["budget"],
        rpm=defaults["rpm"],
        metadata=metadata,
    )
    if not key:
        return jsonify({"error": f"Failed to generate key: {err}"}), 502

    log.info("Generated self-service key for user=%s", username)
    return jsonify({"key": key, "reused": False}), 201


@app.route("/api/v1/keys/info", methods=["GET"])
@require_litellm_key
def get_key_info():
    """
    Get key usage/budget info. Authenticated via any valid LiteLLM key.
    """
    try:
        resp = requests.get(
            f"{LITELLM_URL}/user/info",
            headers={"Authorization": f"Bearer {request.litellm_key}"},
            timeout=10,
        )
        if resp.status_code != 200:
            return jsonify({"error": "failed to get key info"}), resp.status_code
        return jsonify(resp.json())
    except Exception as e:
        log.error("Failed to get key info: %s", e)
        return jsonify({"error": "failed to contact LiteLLM"}), 502


# ---------------------------------------------------------------------------
# Admin endpoints
# ---------------------------------------------------------------------------


@app.route("/api/v1/keys/reset-user", methods=["POST"])
@require_provisioner_secret
def reset_user_spend():
    """Reset a user's spend counter (admin-only, called from Platform Admin)."""
    body = request.get_json(silent=True) or {}
    user_id = body.get("user_id", "").strip()
    if not user_id:
        return jsonify({"error": "user_id required"}), 400

    # Call LiteLLM /user/update to reset spend to 0
    resp = requests.post(
        f"{LITELLM_URL}/user/update",
        headers=_litellm_headers(),
        json={"user_id": user_id, "spend": 0},
        timeout=10,
    )
    if resp.status_code not in (200, 201):
        log.error("Failed to reset spend for user=%s: %s %s", user_id, resp.status_code, resp.text)
        return jsonify({"error": f"LiteLLM error: {resp.text}"}), resp.status_code

    log.info("Reset spend for user=%s", user_id)
    return jsonify({"status": "ok", "user_id": user_id, "spend_reset": True})


@app.route("/api/v1/keys/list", methods=["GET"])
@require_provisioner_secret
def list_keys():
    """List all virtual keys with budget/rate-limit status."""
    resp = requests.get(
        f"{LITELLM_URL}/key/list",
        headers=_litellm_headers(),
        timeout=15,
    )
    if resp.status_code != 200:
        log.error("Failed to list keys: %s %s", resp.status_code, resp.text)
        return jsonify({"error": "failed to list keys"}), resp.status_code
    return jsonify(resp.json())


# ---------------------------------------------------------------------------
# Startup validation
# ---------------------------------------------------------------------------

if not LITELLM_MASTER_KEY:
    log.warning("LITELLM_MASTER_KEY is not set — key generation will fail")
if not PROVISIONER_SECRET:
    log.warning("PROVISIONER_SECRET is not set — workspace endpoint is unprotected")


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8100, debug=True)
