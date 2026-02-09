#!/bin/sh
# ECS Init Container: Docker Workspace Authorization Check
#
# Defense-in-depth validation — runs BEFORE the workspace container starts.
# Even if someone bypasses the Terraform precondition, this blocks unauthorized
# ECS tasks from running.
#
# Required environment variables:
#   WORKSPACE_OWNER    - Coder workspace owner username
#   WORKSPACE_NAME     - Coder workspace name
#   AUTH_SERVICE_URL    - Authorization service endpoint (key-provisioner or dedicated)
#   PROVISIONER_SECRET  - Shared secret for auth service
#
# Exit codes:
#   0 = authorized, workspace may start
#   1 = unauthorized or error, workspace blocked

set -e

echo "[auth-check] Docker workspace authorization validation"
echo "[auth-check] Owner: ${WORKSPACE_OWNER:-unknown}"
echo "[auth-check] Workspace: ${WORKSPACE_NAME:-unknown}"

# Validate required env vars
if [ -z "$WORKSPACE_OWNER" ] || [ -z "$AUTH_SERVICE_URL" ]; then
  echo "[auth-check] ERROR: Missing required environment variables"
  exit 1
fi

# Call authorization service
# The service checks if the user is in the "docker-users" group
RESPONSE=$(curl -sf -X POST "${AUTH_SERVICE_URL}/api/v1/authorize/docker-workspace" \
  -H "Authorization: Bearer ${PROVISIONER_SECRET}" \
  -H "Content-Type: application/json" \
  -d "{
    \"username\": \"${WORKSPACE_OWNER}\",
    \"workspace_name\": \"${WORKSPACE_NAME}\",
    \"resource_type\": \"docker-workspace\"
  }" \
  2>/dev/null) || {
  echo "[auth-check] ERROR: Authorization service unreachable at ${AUTH_SERVICE_URL}"
  # Fail closed — if we can't verify, block the workspace
  exit 1
}

# Parse response
ALLOWED=$(echo "$RESPONSE" | grep -o '"allowed":[^,}]*' | cut -d: -f2 | tr -d ' ')
REASON=$(echo "$RESPONSE" | grep -o '"reason":"[^"]*"' | cut -d'"' -f4)

if [ "$ALLOWED" = "true" ]; then
  echo "[auth-check] AUTHORIZED: ${REASON:-user is in docker-users group}"
  exit 0
else
  echo "[auth-check] DENIED: ${REASON:-user not authorized for Docker workspaces}"
  echo "[auth-check] Contact your platform admin to request docker-users group membership."
  exit 1
fi
