#!/usr/bin/env bash
# Publishes the PizzaShack sample API (its backend ships with API Manager) so the
# catalogue has something to search. Skips if it already exists.
. "$(dirname "$0")/lib.sh"

TOKEN="$(password_token "$APIM_ADMIN_USER" "$APIM_ADMIN_PASSWORD" "apim:api_view apim:api_create apim:api_publish apim:api_manage")"
AUTH=(-H "Authorization: Bearer $TOKEN")
JSON=(-H "Content-Type: application/json")

existing="$(http "${AUTH[@]}" "$PUBLISHER_API/apis?query=name:PizzaShackAPI" | jq -r '.list[0].id // empty')"
if [ -n "$existing" ]; then
    log "PizzaShackAPI already exists ($existing)"
    exit 0
fi

backend="$APIM_MGT_URL/am/sample/pizzashack/v1/api/"
operation() { # operation <verb> <target>
    jq -n --arg verb "$1" --arg target "$2" \
        '{verb: $verb, target: $target, authType: "Application & Application User", throttlingPolicy: "Unlimited"}'
}
operations="$(jq -s . <(operation GET /menu) <(operation POST /order) <(operation GET '/order/{orderId}') \
    <(operation PUT '/order/{orderId}') <(operation DELETE '/order/{orderId}'))"

log "Creating PizzaShackAPI"
API_ID="$(jq -n --arg backend "$backend" --argjson operations "$operations" '{
        name: "PizzaShackAPI", version: "1.0.0", context: "/pizzashack",
        description: "Order pizza: browse the menu, place an order, and track, update or cancel it.",
        tags: ["pizza", "food", "ordering"],
        policies: ["Unlimited", "Gold", "Bronze"],
        endpointConfig: {
            endpoint_type: "http",
            production_endpoints: {url: $backend},
            sandbox_endpoints: {url: $backend}
        },
        operations: $operations
    }' | http "${AUTH[@]}" "${JSON[@]}" -d @- "$PUBLISHER_API/apis" | jq -r .id)"

REVISION_ID="$(http "${AUTH[@]}" "${JSON[@]}" -d '{"description":"Initial revision"}' \
    "$PUBLISHER_API/apis/$API_ID/revisions" | jq -r .id)"
http "${AUTH[@]}" "${JSON[@]}" -o /dev/null \
    -d '[{"name":"Default","vhost":"localhost","displayOnDevportal":true}]' \
    "$PUBLISHER_API/apis/$API_ID/deploy-revision?revisionId=$REVISION_ID"
http "${AUTH[@]}" -X POST -o /dev/null "$PUBLISHER_API/apis/change-lifecycle?action=Publish&apiId=$API_ID"
log "Published PizzaShackAPI ($API_ID)"
