# Agent

The Devportal agent: a Ballerina (WSO2 Integrator) service that answers developer questions
and carries out requests by calling the Devportal MCP server on behalf of the signed-in user.

## API

The chat operations need `Authorization: Bearer <user token>`. The token must carry the `openid`
scope and the Devportal scopes (`apim:subscribe`, `apim:app_manage`, `apim:sub_manage`), and
come from a client registered at the DCR endpoint.

| Operation | Request body |
|---|---|
| `POST /agent/auth/token` | `{"code": "...", "codeVerifier": "...", "redirectUri": "..."}`. No bearer token. Redeems the UI's authorization code and returns `{accessToken, expiresIn, idToken, userName}`. The sign-in client's secret stays in this service. |
| `POST /agent/chat` | `{"sessionId": "<conversation id>", "message": "<text>"}` |
| `POST /agent/chat/decisions` | `{"sessionId": "...", "decisions": [{"id": "<approval id>", "approved": true}]}` |

Both chat operations return the same body:

```json
{
  "status": "COMPLETED | APPROVAL_REQUIRED",
  "message": "reply text, empty while approval is required",
  "approvals": [{"id": "...", "toolName": "subscribe_to_api", "action": "Subscribe an application to an API",
                 "details": [{"label": "Application", "value": "Onboard1"}]}],
  "credentials": [{"name": "consumerSecret", "value": "...", "consumerKey": "..."}]
}
```

Errors: 401 for a missing, invalid or expired token; 409 for a decision that matches no
pending approval; 500 when the agent or the user check fails.

Browsers may call the API only from the origin in `uiOrigin` (CORS).

Conversation memory is keyed by user and `sessionId`. Send requests for one session one at a time.

## Actions and approval

The agent can create an application, subscribe, unsubscribe, and generate OAuth keys. Each
of these pauses the turn: the response has `status: APPROVAL_REQUIRED` and describes the
action with identifiers resolved to names. Nothing runs until the user approves it through
`/chat/decisions`; a rejection is reported back to the model. While an approval is pending,
a new message to the same session returns the same approval again. The pause is enforced by
the `ai` module (`requiresApproval` on the tool), not by the prompt.

## Secrets

Every tool result is checked before the model sees it (`redaction.bal`). Consumer secrets,
access tokens and API keys are replaced with a fixed marker. When the user asked for the
secret, by generating keys, the real values are returned in `credentials` for the UI to
show; they are not stored in conversation memory. The UI must display `credentials`
itself, because the reply text only says that the values are shown alongside.

Generating a further access token is not offered: the Devportal API needs the consumer
secret for it, and the server reveals that secret only once, at key generation.

## How it works

| File | Role |
|---|---|
| `service.bal` | The two endpoints. Validates the user token at the userinfo endpoint and runs or resumes the agent. |
| `agent.bal` | Model provider (`ai:getDefaultModelProvider()`), system prompt and agent. |
| `toolkit.bal` | `DevportalToolKit`: lists the MCP server's tools at start-up, marks the write tools as needing approval, and forwards each call with two headers, the agent application's gateway token and the user's token. `ai:McpToolKit` cannot do this because its headers are fixed at construction. |
| `redaction.bal` | Removes secrets from tool results and collects the ones meant for the user. |
| `approvals.bal` | Describes pending actions for the user. |
| `gateway_token.bal` | Fetches and caches the agent application's client-credentials token. |
| `clients.bal`, `config.bal`, `types.bal` | HTTP clients, configurables, payload records. |

## Run

Prerequisites: API Manager running and `mcp-server/scripts/provision.sh` completed.

```sh
scripts/write-config.sh    # writes Config.toml and tests/Config.toml (git-ignored)
```

Then add the default model provider settings to `Config.toml`. In VS Code, open this
folder and run **Ballerina: Configure default WSO2 model provider**; it adds:

```toml
[ballerina.ai.wso2ProviderConfig]
serviceUrl = "..."
accessToken = "..."
```

`write-config.sh` keeps that section when re-run. Start the agent with `bal run`.
Without the section it exits at start-up with a message naming the missing setting.

Try it from a terminal (signs in as the test user with the password grant; local testing only):

```sh
../mcp-server/scripts/seed-sample-api.sh     # publishes PizzaShackAPI so there is something to find
scripts/chat.sh demo-1 "Is there an API for ordering food?"
scripts/chat.sh demo-1 "Subscribe a new app called Demo to it and generate keys."
scripts/chat.sh demo-1 --approve      # or --reject; repeat for each step it asks about
```

`chat.sh` masks secrets unless `SHOW_SECRETS=1` is set.

Re-running `mcp-server/scripts/teardown.sh` and `provision.sh` issues new application keys:
run `scripts/write-config.sh` again and restart the agent.

## Test

```sh
../mcp-server/scripts/create-test-user.sh
bal test
```

The tests are integration tests against the running API Manager. They replace the model
service with a local stub (`tests/llm_stub.bal`) that calls whichever tool the test message
names and returns its output. They check per-user identity, that a write waits for approval
and does not run when rejected, that another user cannot approve it, and that secrets reach
`credentials` but not the model. They do not check the quality of a real model's answers. They run their own copy
of the agent on port 9095, so they work while the agent is running.

## Observed behaviour with the default model (2026-10-06)

Checked by hand with `scripts/chat.sh` against a catalogue holding one API.

- Finds an API from a described need, explains how to call it with the real gateway URL,
  reports the API's own tiers and the user's subscription state, and declines write requests.
- Each user sees only their own applications.
- Catalogue search matches one keyword at a time and a bare keyword matches names only.
  The `search_apis` description and the system prompt tell the model to try several
  keywords, `tag:` and `description:`. It does this unevenly: for an API that does not
  exist it tried a single keyword before answering.
- It invented request body fields for an operation with no documented schema until the
  prompt rule was made explicit. That rule held in two runs afterwards; treat it as
  mitigated, not guaranteed.
- It reports tier names but does not always look up their limits.
- Actions: from one request ("call the pizza API from a new app, set everything up") it
  proposed create, subscribe and generate-keys in turn, each approved separately. The
  access token it delivered was accepted by the gateway for the PizzaShack menu.
- Asked to print the consumer secret, it declined and pointed to the portal display.
- A rejected unsubscribe left the subscription in place.
- It chose the Unlimited tier for the subscription without asking when no tier was named.
