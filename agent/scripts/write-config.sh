#!/usr/bin/env bash
# Writes Config.toml and tests/Config.toml from ../.env and the state left by
# mcp-server/scripts/provision.sh. Both files are git-ignored.
# An existing [ballerina.ai.wso2ProviderConfig] section in Config.toml is kept.
. "$(dirname "$0")/../../mcp-server/scripts/lib.sh"

AGENT_DIR="$REPO_DIR/agent"
KEYS="$STATE_DIR/agent-app-keys.json"
UI_CLIENT="$(ui_client)"
[ -s "$KEYS" ] || fail "Run mcp-server/scripts/provision.sh first"
# The tests start their own copy of the agent, so it gets a port of its own.
AGENT_TEST_PORT="${AGENT_TEST_PORT:-9095}"

common_config() { # common_config <agent port>
    cat <<TOML
agentPort = $1
mcpServerUrl = "$MCP_URL"
gatewayAuthHeader = "$MCP_GATEWAY_AUTH_HEADER"
tokenUrl = "$TOKEN_URL"
userInfoUrl = "$APIM_MGT_URL/oauth2/userinfo"
agentClientId = "$(jq -r .consumerKey "$KEYS")"
agentClientSecret = "$(jq -r .consumerSecret "$KEYS")"
uiOrigin = "$UI_ORIGIN"
uiClientId = "$(jq -r .clientId "$UI_CLIENT")"
uiClientSecret = "$(jq -r .clientSecret "$UI_CLIENT")"
trustStorePath = "$APIM_HOME/repository/resources/security/client-truststore.jks"
trustStorePassword = "${APIM_TRUSTSTORE_PASSWORD:-wso2carbon}"
TOML
}

provider_section=""
if [ -f "$AGENT_DIR/Config.toml" ]; then
    provider_section="$(awk '/^\[ballerina\.ai\.wso2ProviderConfig\]/{keep=1; print; next} /^\[/{keep=0} keep' "$AGENT_DIR/Config.toml")"
fi
{
    common_config "$AGENT_PORT"
    echo
    if [ -n "$provider_section" ]; then
        echo "$provider_section"
    else
        echo "# Add the default model provider settings here. In VS Code, run the command"
        echo "# \"Ballerina: Configure default WSO2 model provider\" with this package open."
        echo "# [ballerina.ai.wso2ProviderConfig]"
        echo "# serviceUrl = \"\""
        echo "# accessToken = \"\""
    fi
} > "$AGENT_DIR/Config.toml"
log "Wrote agent/Config.toml"

LLM_STUB_PORT="${LLM_STUB_PORT:-9191}"
DCR="$(dcr_client)"
{
    common_config "$AGENT_TEST_PORT"
    cat <<TOML
llmStubPort = $LLM_STUB_PORT
testClientId = "$(jq -r .clientId "$DCR")"
testClientSecret = "$(jq -r .clientSecret "$DCR")"
adminUser = "$APIM_ADMIN_USER"
adminPassword = "$APIM_ADMIN_PASSWORD"
testUser = "$TEST_USER"
testUserPassword = "$TEST_USER_PASSWORD"
devportalApiUrl = "$DEVPORTAL_API"

# The tests replace the model service with a local stub.
[ballerina.ai.wso2ProviderConfig]
serviceUrl = "http://localhost:$LLM_STUB_PORT/llm"
accessToken = "stub"
TOML
} > "$AGENT_DIR/tests/Config.toml"
log "Wrote agent/tests/Config.toml"
