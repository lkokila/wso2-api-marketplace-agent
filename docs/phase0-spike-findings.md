# Phase 0 spike: Devportal REST API as an MCP server

Tested on 2026-10-06 against WSO2 API Manager 4.7.0 (update level 9), single node, JDK 25.

## Question

Can the MCP server that API Manager generates from an OpenAPI definition front the
Devportal REST API so that each tool call runs as the logged-in developer?

## Answer

Yes. The generated MCP server is used as is; no hand-written MCP server is needed.
`mcp-server/scripts/smoke-test.sh` proves it with 12 checks, all passing.

## How authentication works

Each request to the MCP server carries two tokens in two headers.

| Header | Token | Issued to | Checked by | Purpose |
|---|---|---|---|---|
| `X-Agent-Authorization` | Application token (client credentials) | `DevportalAgent` application, subscribed to the MCP server | Gateway | Subscription, throttling, analytics |
| `Authorization` | User token with `apim:*` devportal scopes | The developer, through a client registered at the DCR endpoint | Devportal REST API | Identity and permissions of the developer |

The MCP server's `authorizationHeader` is set to `X-Agent-Authorization`, so the gateway
reads its own credential from there and forwards `Authorization` to the backend untouched.

Observed behaviour:

- `admin` and `dev1` each see only their own applications through the same MCP server.
- An application created by `dev1` through `create_application` cannot be read with `admin`'s token: `get_application` returns an error result.
- Without the user token the tool returns the REST API's 401 as an error result.
- Without the application token the gateway returns HTTP 401.
- Path, query and request body parameters are all mapped. Body fields are passed under a `requestBody` argument.

## Approaches that were rejected

### One token for both gateway and REST API

A token issued to the subscribed application by password grant, with `apim:*` scopes, is
accepted by both the gateway and the REST API, and the gateway forwards it. It fails on
identity: these tokens are JWTs whose `sub` is the user's internal UUID, and the REST API
uses that as the username. `admin` was treated as a different user
(`10bceb56-…`) with a separate, empty set of applications.

Tokens from a client registered at `/client-registration/v0.17/register` are opaque and
resolve to the real username, which is what the Devportal UI itself relies on. The server
setting `[service_provider] use_username_as_sub_claim` may also fix the JWT case; it was
not tested because it changes behaviour for every application on the server.

### API key for the gateway credential

With `api_key` enabled on the MCP server, every call fails with HTTP 500 and the gateway logs
`Swagger is missing in the gateway. Therefore, Api Key authentication cannot be performed.`
API key security does not work for MCP servers at this update level. Worth reporting upstream.

## Tool curation

`mcp-server/openapi/tools.yaml` selects 11 of the 108 Devportal operations and gives each a
tool name and an LLM-oriented description. `build-spec.mjs` produces the definition from it.

- The tool name comes from `operationId`, and the description from the operation description.
  Only 48 of the 108 source operations have an `operationId`, so curation is required, not optional.
- Header parameters (`If-None-Match`, `X-WSO2-Tenant`) appear as tool inputs unless removed;
  the build script strips them.
- Tool results are the raw REST JSON as a text block. Error responses come back as
  `isError: true` with the REST error body.

## Operational notes

- Gateway deployment is asynchronous. The MCP endpoint returned 404 for about six seconds
  after `deploy-revision`; `provision.sh` waits for it.
- Changing the tool set on an existing MCP server was not explored; the scripts tear down and recreate.
- This server has no SCIM2 endpoint; `create-test-user.sh` uses the `RemoteUserStoreManagerService` admin service.
- The server logs a startup error for `SecureWebhookServer` (port 8021 already in use on this machine). Unrelated to this work.

## Open items for later phases

- The UI must log users in with authorization code + PKCE against a DCR-registered client.
  The smoke test uses the password grant, which is for testing only.
- Done in Phase 2: key generation with secrets kept from the LLM, and approval before
  mutating tools. See `agent/README.md`.
- `search_apis` is keyword search; it was not tested against a populated catalogue.
