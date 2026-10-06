#!/usr/bin/env bash
# Removes the agent application and the Devportal MCP server created by provision.sh.
. "$(dirname "$0")/lib.sh"

TOKEN="$(admin_token)"
AUTH=(-H "Authorization: Bearer $TOKEN")

APP_ID="$(find_agent_app_id "$TOKEN")"
if [ -n "$APP_ID" ]; then
    log "Deleting application $AGENT_APP_NAME (and its subscriptions)"
    http "${AUTH[@]}" -X DELETE -o /dev/null "$DEVPORTAL_API/applications/$APP_ID"
fi
rm -f "$STATE_DIR/agent-app-keys.json"

MCP_ID="$(find_mcp_server_id "$TOKEN")"
if [ -n "$MCP_ID" ]; then
    log "Undeploying and deleting MCP server $MCP_SERVER_NAME"
    http "${AUTH[@]}" "$PUBLISHER_API/mcp-servers/$MCP_ID/deployments" \
        | jq -c '(if type == "array" then . else .list end)[]' | while read -r deployment; do
        revision="$(jq -r .revisionUuid <<<"$deployment")"
        body="$(jq -c '[{name, vhost, displayOnDevportal}]' <<<"$deployment")"
        http "${AUTH[@]}" -H "Content-Type: application/json" -o /dev/null -d "$body" \
            "$PUBLISHER_API/mcp-servers/$MCP_ID/undeploy-revision?revisionId=$revision"
    done
    http "${AUTH[@]}" -X DELETE -o /dev/null "$PUBLISHER_API/mcp-servers/$MCP_ID"
fi
log "Done"
