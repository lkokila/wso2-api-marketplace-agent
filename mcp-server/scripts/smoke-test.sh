#!/usr/bin/env bash
# End-to-end check of the Devportal MCP server through the gateway:
# tool listing, per-user identity pass-through, a write, and credential enforcement.
. "$(dirname "$0")/lib.sh"

KEYS="$STATE_DIR/agent-app-keys.json"
[ -s "$KEYS" ] || fail "Run provision.sh first"

GATEWAY_TOKEN="$(http -u "$(jq -r .consumerKey "$KEYS"):$(jq -r .consumerSecret "$KEYS")" \
    -d "grant_type=client_credentials" "$TOKEN_URL" | jq -r .access_token)"
ADMIN_USER_TOKEN="$(password_token "$APIM_ADMIN_USER" "$APIM_ADMIN_PASSWORD" "$USER_SCOPES")"
TEST_USER_TOKEN="$(password_token "$TEST_USER" "$TEST_USER_PASSWORD" "$USER_SCOPES")"

failures=0
check() { # check <description> <actual> <expected>
    if [ "$2" == "$3" ]; then
        echo "PASS  $1"
    else
        echo "FAIL  $1"; echo "        expected: $3"; echo "        actual:   $2"
        failures=$((failures + 1))
    fi
}

# rpc <json-rpc body> [curl args...]; prints "<http status> <response body>"
rpc() {
    local body="$1"; shift
    curl -sk -m 30 -o "$STATE_DIR/rpc-response.json" -w "%{http_code}" "$@" \
        -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
        -d "$body" "$MCP_URL"
}
# call_tool <name> <arguments json> [curl args...]; prints the HTTP status
call_tool() {
    local name="$1" arguments="$2"; shift 2
    rpc '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"'"$name"'","arguments":'"$arguments"'}}' "$@"
}
tool_text() { jq -r '.result.content[0].text' "$STATE_DIR/rpc-response.json"; }
gateway=(-H "$MCP_GATEWAY_AUTH_HEADER: Bearer $GATEWAY_TOKEN")
as_admin=("${gateway[@]}" -H "Authorization: Bearer $ADMIN_USER_TOKEN")
as_test_user=("${gateway[@]}" -H "Authorization: Bearer $TEST_USER_TOKEN")

status="$(rpc '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' "${as_test_user[@]}")"
check "tools/list succeeds" "$status" "200"
expected_tools="$(jq -r '.[].backendOperationMapping.backendOperation | "\(.verb) \(.target)"' "$MCP_DIR/build/operations.json" | wc -l | tr -d ' ')"
check "tools/list returns every curated tool" "$(jq '.result.tools | length' "$STATE_DIR/rpc-response.json")" "$expected_tools"
check "no HTTP header parameters leak into tool inputs" \
    "$(jq '[.result.tools[].inputSchema.properties // {} | keys[] | select(test("^(If-None-Match|X-WSO2-Tenant)$"))] | length' "$STATE_DIR/rpc-response.json")" "0"

call_tool list_applications '{}' "${as_admin[@]}" > /dev/null
check "admin sees only admin-owned applications" "$(tool_text | jq -c '[.list[].owner] | unique')" "[\"$APIM_ADMIN_USER\"]"

call_tool list_applications '{}' "${as_test_user[@]}" > /dev/null
check "$TEST_USER sees only their own applications" "$(tool_text | jq -c '[.list[].owner] | unique')" "[\"$TEST_USER\"]"

app_name="SmokeTest$(date +%s)"
call_tool create_application '{"requestBody":{"name":"'"$app_name"'","throttlingPolicy":"Unlimited"}}' "${as_test_user[@]}" > /dev/null
created_id="$(tool_text | jq -r '.applicationId // empty')"
check "create_application works as $TEST_USER" "$(jq -r .result.isError "$STATE_DIR/rpc-response.json")" "false"
call_tool get_application '{"applicationId":"'"$created_id"'"}' "${as_test_user[@]}" > /dev/null
check "path parameter is mapped (get_application)" "$(tool_text | jq -r .name)" "$app_name"
call_tool get_application '{"applicationId":"'"$created_id"'"}' "${as_admin[@]}" > /dev/null
check "another user's token cannot read that application" "$(jq -r .result.isError "$STATE_DIR/rpc-response.json")" "true"
if [ -n "$created_id" ]; then
    http -X DELETE -o /dev/null -H "Authorization: Bearer $TEST_USER_TOKEN" "$DEVPORTAL_API/applications/$created_id"
fi

call_tool list_throttling_policies '{"policyLevel":"application"}' "${as_test_user[@]}" > /dev/null
check "list_throttling_policies returns the Unlimited tier" "$(tool_text | jq '[.list[].name] | index("Unlimited") != null')" "true"

call_tool list_mcp_servers '{"query":"'"$MCP_SERVER_NAME"'"}' "${as_test_user[@]}" > /dev/null
check "query parameter is mapped (list_mcp_servers)" "$(tool_text | jq -r '.list[0].name')" "$MCP_SERVER_NAME"

call_tool list_applications '{}' "${gateway[@]}" > /dev/null
check "missing user token is rejected by the Devportal API" "$(tool_text | jq -r .code)" "401"

status="$(call_tool list_applications '{}' -H "Authorization: Bearer $TEST_USER_TOKEN")"
check "missing agent application token is rejected by the gateway" "$status" "401"

rm -f "$STATE_DIR/rpc-response.json"
[ "$failures" -eq 0 ] && echo "All checks passed" || { echo "$failures check(s) failed"; exit 1; }
