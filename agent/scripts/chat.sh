#!/usr/bin/env bash
# Talks to the running agent as the test user. For local testing only: it signs in
# with the password grant.
#   chat.sh <session id> <message>           send a message
#   chat.sh <session id> --approve|--reject  answer the approvals the last reply asked for
# Secrets in the reply are shown masked unless SHOW_SECRETS=1.
. "$(dirname "$0")/../../mcp-server/scripts/lib.sh"

[ $# -eq 2 ] || fail "Usage: chat.sh <session id> <message | --approve | --reject>"
SESSION_ID="$1"
CHAT_USER="${CHAT_USER:-$TEST_USER}"
CHAT_PASSWORD="${CHAT_PASSWORD:-$TEST_USER_PASSWORD}"
AGENT_URL="http://localhost:${AGENT_PORT:-9090}/agent"
LAST_REPLY="$STATE_DIR/chat-$SESSION_ID.json"
USER_TOKEN="$(password_token "$CHAT_USER" "$CHAT_PASSWORD" "openid $USER_SCOPES")"

post() { # post <path>; reads the JSON body from stdin
    curl -s -m 300 -H "Authorization: Bearer $USER_TOKEN" -H "Content-Type: application/json" -d @- "$AGENT_URL$1"
}

case "$2" in
    --approve|--reject)
        [ -s "$LAST_REPLY" ] || fail "No pending approvals recorded for session $SESSION_ID"
        approved=$([ "$2" == "--approve" ] && echo true || echo false)
        jq --arg sessionId "$SESSION_ID" --argjson approved "$approved" \
            '{sessionId: $sessionId, decisions: [.approvals[] | {id, approved: $approved}]}' "$LAST_REPLY" \
            | post /chat/decisions > "$LAST_REPLY.new"
        ;;
    *)
        jq -n --arg sessionId "$SESSION_ID" --arg message "$2" '{sessionId: $sessionId, message: $message}' \
            | post /chat > "$LAST_REPLY.new"
        ;;
esac
mv "$LAST_REPLY.new" "$LAST_REPLY"

jq -r --arg show "${SHOW_SECRETS:-0}" '
    if .status == null then .
    else
        (if .message != "" then .message else empty end),
        (.approvals[] | "\n[APPROVAL NEEDED] \(.action)", (.details[] | "    \(.label): \(.value)")),
        (.credentials[] | "\n[SECRET for the user] \(.name)" + (if .consumerKey then " (consumer key \(.consumerKey))" else "" end)
            + ": " + (if $show == "1" then .value else .value[0:4] + "…(" + (.value | length | tostring) + " chars)" end))
    end' "$LAST_REPLY"
