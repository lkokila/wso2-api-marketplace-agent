#!/usr/bin/env bash
# Writes .env.local (git-ignored) with the endpoints and sign-in client the UI uses.
. "$(dirname "$0")/../../mcp-server/scripts/lib.sh"

UI_CLIENT="$(ui_client)"
cat > "$REPO_DIR/ui/.env.local" <<ENV
VITE_AGENT_URL=http://localhost:$AGENT_PORT/agent
VITE_AUTHORIZE_URL=$APIM_MGT_URL/oauth2/authorize
VITE_LOGOUT_URL=$APIM_MGT_URL/oidc/logout
VITE_CLIENT_ID=$(jq -r .clientId "$UI_CLIENT")
ENV
log "Wrote ui/.env.local"
