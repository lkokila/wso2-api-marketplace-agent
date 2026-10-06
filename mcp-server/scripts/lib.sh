#!/usr/bin/env bash
# Shared helpers for the provisioning scripts. Source this file; do not execute it.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MCP_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_DIR="$(cd "$MCP_DIR/.." && pwd)"
STATE_DIR="$REPO_DIR/.local"
mkdir -p "$STATE_DIR"

if [ ! -f "$REPO_DIR/.env" ]; then
    echo "Missing $REPO_DIR/.env (copy .env.example)" >&2
    exit 1
fi
set -a
# shellcheck disable=SC1091
. "$REPO_DIR/.env"
set +a

PUBLISHER_API="$APIM_MGT_URL/api/am/publisher/v4"
DEVPORTAL_API="$APIM_MGT_URL/api/am/devportal/v3"
TOKEN_URL="$APIM_MGT_URL/oauth2/token"
MCP_URL="$APIM_GW_URL$MCP_SERVER_CONTEXT/$MCP_SERVER_VERSION/mcp"
AGENT_PORT="${AGENT_PORT:-9090}"
UI_ORIGIN="${UI_ORIGIN:-http://localhost:5173}"

ADMIN_SCOPES="apim:mcp_server_create apim:mcp_server_manage apim:mcp_server_view apim:mcp_server_publish apim:subscribe apim:app_manage apim:sub_manage"
USER_SCOPES="apim:subscribe apim:app_manage apim:sub_manage apim:api_key apim:store_settings"

log() { echo "==> $*" >&2; }
fail() { echo "ERROR: $*" >&2; exit 1; }

# -k: the local server uses a self-signed certificate.
http() { curl -sk --fail-with-body "$@"; }

# Registers (or returns the cached) OAuth client used for management and user logins.
# Tokens from this client are opaque and resolve to the user's username at the REST APIs.
dcr_client() {
    local file="$STATE_DIR/dcr-client.json"
    if [ ! -s "$file" ]; then
        http -u "$APIM_ADMIN_USER:$APIM_ADMIN_PASSWORD" -H "Content-Type: application/json" \
            -d '{"callbackUrl":"http://localhost:5173/callback","clientName":"devportal_agent_tooling","owner":"'"$APIM_ADMIN_USER"'","grantType":"password refresh_token","saasApp":true}' \
            "$APIM_MGT_URL/client-registration/v0.17/register" > "$file"
    fi
    echo "$file"
}

# password_token <username> <password> <scopes>
password_token() {
    local client
    client="$(dcr_client)"
    http -u "$(jq -r .clientId "$client"):$(jq -r .clientSecret "$client")" \
        --data-urlencode "grant_type=password" --data-urlencode "username=$1" \
        --data-urlencode "password=$2" --data-urlencode "scope=$3" "$TOKEN_URL" | jq -r .access_token
}

# Registers (or returns the cached) OAuth client the UI signs users in with:
# authorization code grant, redirecting to the UI's callback.
ui_client() {
    local file="$STATE_DIR/ui-client.json"
    if [ ! -s "$file" ]; then
        http -u "$APIM_ADMIN_USER:$APIM_ADMIN_PASSWORD" -H "Content-Type: application/json" \
            -d '{"callbackUrl":"'"$UI_ORIGIN"'/callback","clientName":"devportal_agent_ui","owner":"'"$APIM_ADMIN_USER"'","grantType":"authorization_code refresh_token","saasApp":true}' \
            "$APIM_MGT_URL/client-registration/v0.17/register" > "$file"
    fi
    echo "$file"
}

admin_token() { password_token "$APIM_ADMIN_USER" "$APIM_ADMIN_PASSWORD" "$ADMIN_SCOPES"; }

# Prints the MCP server id, or nothing if it does not exist.
find_mcp_server_id() {
    http -H "Authorization: Bearer $1" "$PUBLISHER_API/mcp-servers?limit=100" \
        | jq -r --arg n "$MCP_SERVER_NAME" --arg v "$MCP_SERVER_VERSION" \
            '.list[] | select(.name == $n and .version == $v) | .id'
}

# Prints the agent application id, or nothing if it does not exist.
find_agent_app_id() {
    http -H "Authorization: Bearer $1" "$DEVPORTAL_API/applications?limit=100" \
        | jq -r --arg n "$AGENT_APP_NAME" '.list[] | select(.name == $n) | .applicationId'
}
