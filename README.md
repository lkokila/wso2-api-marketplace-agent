# Devportal Agent

An AI agent front end for the WSO2 API Manager Developer Portal. Developers obtain information, discover APIs,
create applications, subscribe and obtain credentials by chatting, instead of clicking
through the portal.

```
React chat UI ──sign-in (authorization code + PKCE)──► API Manager key manager
     │ user token
     ▼
Agent (WSO2 Integrator) ──► LLM
     │ MCP, user token forwarded
     ▼
Devportal MCP server (API Manager gateway) ──► Devportal REST API v3
```

## Components

| Path | What it is | Runs on |
|---|---|---|
| WSO2 API Manager 4.7.0 | The product being fronted. Hosts the Devportal REST API, the key manager and the gateway. Not part of this repository. | `https://localhost:9443` (management), `https://localhost:8243` (gateway) |
| `mcp-server/` | Tool manifest and scripts that create the Devportal MCP server inside API Manager. Nothing here runs as a process. | Served by the gateway at `/devportal-mcp/1.0.0/mcp` |
| `agent/` | The agent: a Ballerina service built for WSO2 Integrator. | `http://localhost:9090` |
| `ui/` | React chat UI. | `http://localhost:5173` |
| `docs/` | Design notes and spike findings. | |
| `.local/` | Credentials and state written by the scripts. Git-ignored. | |

## Prerequisites

- WSO2 API Manager 4.7.0, unpacked locally, and a JDK it supports (21 to 25)
- Ballerina Swan Lake 2201.13.x
- Node.js 20.19+ or 22.12+
- `curl` and `jq`
- VS Code with the WSO2 Integrator (or Ballerina) extension, signed in. It is needed once
  per model-token lifetime, to issue the token for the default model provider.

## First-time setup

Run everything from the repository root unless a step says otherwise. Steps 2, 6 and 8
start long-running processes: give each its own terminal.

### 1. Configure

```sh
cp .env.example .env
```

Edit `.env` and set `APIM_HOME` to your API Manager folder. Change the admin credentials
if yours are not `admin` / `admin`.

### 2. Start API Manager

```sh
sh "$APIM_HOME/bin/api-manager.sh"      # use the path you set in .env
```

Wait for the line `Mgt Console URL  : https://localhost:9443/carbon/`.

### 3. Create the Devportal MCP server

```sh
(cd mcp-server && npm install)
mcp-server/scripts/provision.sh
```

This builds the curated OpenAPI definition, creates the `DevportalMCP` server in API
Manager, deploys and publishes it, and creates the `DevportalAgent` application the agent
uses to call it. It is safe to re-run.

### 4. Create a test user and sample data

```sh
mcp-server/scripts/create-test-user.sh   # developer account dev1 (password in .env)
mcp-server/scripts/seed-sample-api.sh    # optional: publishes PizzaShackAPI so there is something to find
```

### 5. Check the MCP server

```sh
mcp-server/scripts/smoke-test.sh
```

It should end with `All checks passed`.

### 6. Configure and start the agent

```sh
agent/scripts/write-config.sh
```

This writes `agent/Config.toml`. Then add the model settings to it:

1. Open the `agent/` folder in VS Code.
2. Run the command **Ballerina: Configure default WSO2 model provider**.
3. Confirm `agent/Config.toml` now has a `[ballerina.ai.wso2ProviderConfig]` section with
   `serviceUrl` and `accessToken`.

Start the agent:

```sh
cd agent
bal run
```

It is ready when `bal run` prints `Running executable` and stays running. If it exits
with `ballerina.ai.wso2ProviderConfig is not configured correctly`, the model settings are missing.

### 7. Check the agent (optional)

In another terminal, from the repository root:

```sh
agent/scripts/chat.sh demo-1 "What APIs are available?"
```

This signs in as the test user and prints the agent's reply.

### 8. Configure and start the UI

```sh
ui/scripts/write-config.sh
cd ui
npm install
npm run dev
```

### 9. Sign in

1. Open `https://localhost:9443` in your browser and accept API Manager's self-signed
   certificate. This is needed once per browser; without it the sign-in redirect is blocked.
2. Open `http://localhost:5173` and choose **Sign in**.
3. Use the test user: `dev1` with the password from `TEST_USER_PASSWORD` in `.env`.

Things to try:

- "Is there an API for ordering food?"
- "Create an application called Demo, subscribe it to that API on the Gold tier and generate production keys."
  Approve each step when its card appears; the credentials card shows the secret and token.
- "Show me how to get the menu."

## Starting it again later

Setup is kept between runs. To bring everything back up:

```sh
sh "$APIM_HOME/bin/api-manager.sh"     # terminal 1; wait for the Mgt Console URL line
cd agent && bal run                     # terminal 2
cd ui && npm run dev                    # terminal 3
```

Start API Manager first: the agent connects to the MCP server when it starts and exits if
it cannot.

## Stopping

Press `Ctrl+C` in each terminal: the UI, the agent, then API Manager.

## Tests

| Command | What it checks | Needs |
|---|---|---|
| `mcp-server/scripts/smoke-test.sh` | The MCP server through the gateway: tools, per-user identity, credential enforcement | API Manager |
| `cd agent && bal test` | The agent with a stand-in model: per-user identity, approval before actions, secrets withheld from the model | API Manager and the test user. Works while the agent is running. |

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| The UI shows "The assistant could not complete the request", and the agent log has `Error while connecting to the model` with `401` | The model access token has expired. Run **Ballerina: Configure default WSO2 model provider** again in VS Code, then restart the agent. |
| The browser shows a certificate warning or a blank page after **Sign in** | Open `https://localhost:9443` and accept the certificate, then try again. |
| The agent exits at start-up with a connection error | API Manager is not running, or the MCP server is not provisioned. Start API Manager, then run `mcp-server/scripts/provision.sh`. |
| The agent starts but every tool call fails with `Invalid Credentials` from the gateway | The agent application's keys changed, which happens after `teardown.sh` and `provision.sh`. Run `agent/scripts/write-config.sh` and restart the agent. |
| `Address already in use` for 9090 or 5173 | An earlier agent or UI is still running. Stop it. The UI port is fixed; see [ui/README.md](ui/README.md). |
| `mcp-server/scripts/smoke-test.sh` fails right after `provision.sh` with 404 | The gateway is still deploying. Wait a few seconds and run it again. |

## Changing the tools

The tools the agent can use are listed in `mcp-server/openapi/tools.yaml`. After editing it:

```sh
mcp-server/scripts/teardown.sh
mcp-server/scripts/provision.sh
agent/scripts/write-config.sh      # the application keys are new
```

Then restart the agent. A new tool also has to be added to the read or approval list in
`agent/toolkit.bal` before the agent will offer it to the model.

## More detail

- [agent/README.md](agent/README.md): the chat API, approvals, how secrets are kept from the model
- [ui/README.md](ui/README.md): sign-in flow and UI limits
- [docs/phase0-spike-findings.md](docs/phase0-spike-findings.md): how authentication through the gateway works and why
