#!/usr/bin/env bash
# Creates the Devportal MCP server from the curated OpenAPI definition, deploys and
# publishes it, and sets up the application the agent uses to call it.
# Safe to re-run: existing resources are reused. Run teardown.sh first to rebuild.
. "$(dirname "$0")/lib.sh"

log "Building curated OpenAPI definition"
(cd "$MCP_DIR" && npm run -s build:spec >&2)

TOKEN="$(admin_token)"
AUTH=(-H "Authorization: Bearer $TOKEN")
JSON=(-H "Content-Type: application/json")

MCP_ID="$(find_mcp_server_id "$TOKEN")"
if [ -z "$MCP_ID" ]; then
    log "Creating MCP server $MCP_SERVER_NAME"
    backend="$APIM_MGT_URL/api/am/devportal/v3"
    jq -n --arg name "$MCP_SERVER_NAME" --arg version "$MCP_SERVER_VERSION" \
        --arg context "$MCP_SERVER_CONTEXT" --arg backend "$backend" \
        --arg header "$MCP_GATEWAY_AUTH_HEADER" --slurpfile operations "$MCP_DIR/build/operations.json" '{
            name: $name, displayName: "Devportal MCP", version: $version, context: $context,
            description: "Developer Portal operations exposed as MCP tools for the Devportal AI agent.",
            gatewayType: "wso2/synapse", policies: ["Unlimited"],
            authorizationHeader: $header,
            endpointConfig: {
                endpoint_type: "http",
                production_endpoints: {url: $backend},
                sandbox_endpoints: {url: $backend}
            },
            operations: $operations[0]
        }' > "$STATE_DIR/mcp-server-request.json"
    MCP_ID="$(http "${AUTH[@]}" -F "file=@$MCP_DIR/build/devportal-curated.yaml" \
        -F "additionalProperties=<$STATE_DIR/mcp-server-request.json" \
        "$PUBLISHER_API/mcp-servers/generate-from-openapi" | jq -r .id)"

    log "Deploying revision to the Default gateway"
    REVISION_ID="$(http "${AUTH[@]}" "${JSON[@]}" -d '{"description":"Initial revision"}' \
        "$PUBLISHER_API/mcp-servers/$MCP_ID/revisions" | jq -r .id)"
    http "${AUTH[@]}" "${JSON[@]}" -o /dev/null \
        -d '[{"name":"Default","vhost":"localhost","displayOnDevportal":true}]' \
        "$PUBLISHER_API/mcp-servers/$MCP_ID/deploy-revision?revisionId=$REVISION_ID"

    log "Publishing"
    http "${AUTH[@]}" -X POST -o /dev/null \
        "$PUBLISHER_API/mcp-servers/change-lifecycle?action=Publish&mcpServerId=$MCP_ID"
else
    log "MCP server $MCP_SERVER_NAME already exists ($MCP_ID); reusing"
fi

APP_ID="$(find_agent_app_id "$TOKEN")"
if [ -z "$APP_ID" ]; then
    log "Creating application $AGENT_APP_NAME"
    APP_ID="$(http "${AUTH[@]}" "${JSON[@]}" \
        -d '{"name":"'"$AGENT_APP_NAME"'","throttlingPolicy":"Unlimited","tokenType":"JWT","description":"Used by the Devportal AI agent to call the Devportal MCP server"}' \
        "$DEVPORTAL_API/applications" | jq -r .applicationId)"
    log "Subscribing it to the MCP server"
    http "${AUTH[@]}" "${JSON[@]}" -o /dev/null \
        -d '{"applicationId":"'"$APP_ID"'","apiId":"'"$MCP_ID"'","throttlingPolicy":"Unlimited"}' \
        "$DEVPORTAL_API/subscriptions"
    log "Generating application keys"
    http "${AUTH[@]}" "${JSON[@]}" \
        -d '{"keyType":"PRODUCTION","keyManager":"Resident Key Manager","grantTypesToBeSupported":["client_credentials"],"validityTime":3600}' \
        "$DEVPORTAL_API/applications/$APP_ID/generate-keys" \
        | jq '{consumerKey, consumerSecret}' > "$STATE_DIR/agent-app-keys.json"
else
    log "Application $AGENT_APP_NAME already exists ($APP_ID); reusing"
    [ -s "$STATE_DIR/agent-app-keys.json" ] || fail "Application exists but $STATE_DIR/agent-app-keys.json is missing; run teardown.sh and provision again"
fi

# Gateway deployment is asynchronous; the endpoint answers 404 until the artifact is live.
log "Waiting for the gateway to serve $MCP_URL"
for _ in $(seq 1 30); do
    status="$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$MCP_URL" || true)"
    [ "$status" != "404" ] && [ "$status" != "000" ] && break
    sleep 2
done
[ "$status" != "404" ] && [ "$status" != "000" ] || fail "MCP server is not reachable on the gateway (HTTP $status)"

echo "MCP server:  $MCP_URL"
echo "Gateway auth header: $MCP_GATEWAY_AUTH_HEADER (agent application token)"
echo "Agent application keys: $STATE_DIR/agent-app-keys.json"
