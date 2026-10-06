# Port the agent's chat API listens on.
configurable int agentPort = ?;

# Streamable HTTP endpoint of the Devportal MCP server on the API Manager gateway.
configurable string mcpServerUrl = ?;
# Header in which the gateway expects the agent application's token.
configurable string gatewayAuthHeader = ?;

# OAuth2 token endpoint of the API Manager key manager.
configurable string tokenUrl = ?;
# OIDC userinfo endpoint, used to validate a user token and resolve the user.
configurable string userInfoUrl = ?;
# Credentials of the application subscribed to the Devportal MCP server.
configurable string agentClientId = ?;
configurable string agentClientSecret = ?;

# Origin the UI is served from; the only origin allowed to call the chat API from a browser.
configurable string uiOrigin = ?;
# Credentials of the OAuth client the UI signs users in with. The secret stays here:
# the UI sends its authorization code to this service, which redeems it.
configurable string uiClientId = ?;
configurable string uiClientSecret = ?;

# Truststore holding the API Manager server certificate.
configurable string trustStorePath = ?;
configurable string trustStorePassword = ?;
