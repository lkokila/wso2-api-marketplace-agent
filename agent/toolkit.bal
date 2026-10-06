import ballerina/ai;
import ballerina/http;
import ballerina/mcp;

// Context key under which the chat service stores the caller's Devportal token.
const string USER_TOKEN_KEY = "userToken";

// Tools that only read. The agent calls them freely.
final readonly & string[] readTools = [
    "search_apis",
    "get_api",
    "get_api_definition",
    "list_api_documents",
    "list_mcp_servers",
    "list_applications",
    "get_application",
    "list_subscriptions",
    "get_subscription",
    "list_throttling_policies",
    "list_application_keys"
];

// Tools that change something. Each call pauses the agent until the user approves it.
final readonly & string[] approvalTools = [
    "create_application",
    "subscribe_to_api",
    "unsubscribe_from_api",
    "generate_application_keys"
];

// Tools whose result is a secret the user asked for. Their secrets go to the UI;
// secrets that turn up in any other tool's result are only removed.
final readonly & string[] credentialTools = ["generate_application_keys"];

# Exposes the Devportal MCP server's tools to the agent.
#
# `ai:McpToolKit` sends the same headers on every call. This toolkit instead sends two
# credentials per call: the agent application's token for the gateway, and the token of
# the user who is chatting, so each tool runs with that user's identity and permissions.
# It also redacts secrets from every result before the model sees it.
isolated class DevportalToolKit {
    *ai:McpBaseToolKit;
    private final mcp:StreamableHttpClient mcpClient;
    private final GatewayTokenProvider tokenProvider;
    private final ai:ToolConfig[] & readonly tools;

    # + tokenProvider - Source of the agent application's gateway token
    # + secureSocket - TLS settings for the gateway connection
    isolated function init(GatewayTokenProvider tokenProvider, http:ClientSecureSocket secureSocket) returns error? {
        self.tokenProvider = tokenProvider;
        self.mcpClient = check new (mcpServerUrl, secureSocket = secureSocket);
        map<string> gatewayHeaders = {[gatewayAuthHeader]: string `Bearer ${check tokenProvider.getToken()}`};
        check self.mcpClient->initialize(
            clientInfo = {name: "Devportal Agent", version: "0.1.0"},
            headers = gatewayHeaders
        );
        mcp:ListToolsResult listedTools = check self.mcpClient->listTools(headers = gatewayHeaders);

        isolated function caller = self.callTool;
        ai:ToolConfig[] toolConfigs = [];
        foreach mcp:ToolDefinition toolDefinition in listedTools.tools {
            boolean requiresApproval = approvalTools.indexOf(toolDefinition.name) !is ();
            if !requiresApproval && readTools.indexOf(toolDefinition.name) is () {
                continue;
            }
            map<json> inputSchema = check toolDefinition.inputSchema.cloneWithType();
            toolConfigs.push({
                name: toolDefinition.name,
                description: toolDefinition.description ?: "",
                parameters: inputSchema,
                caller,
                requiresApproval
            });
        }
        int expectedCount = readTools.length() + approvalTools.length();
        if toolConfigs.length() != expectedCount {
            return error("The Devportal MCP server does not offer every tool the agent expects",
                offered = toolConfigs.map(toolConfig => toolConfig.name), expectedCount = expectedCount);
        }
        self.tools = toolConfigs.cloneReadOnly();
    }

    public isolated function getTools() returns ai:ToolConfig[] => self.tools;

    # Calls a tool as the user in `context` and returns its result with secrets removed.
    #
    # + context - Carries the user's token and the turn's credential collector
    # + params - Tool name and arguments
    # + return - The redacted tool result
    isolated function callTool(ai:Context context, mcp:CallToolParams params) returns mcp:CallToolResult|error {
        string userToken = check context.getWithType(key = USER_TOKEN_KEY);
        string gatewayToken = check self.tokenProvider.getToken();
        mcp:CallToolResult toolResult = check self.mcpClient->callTool(params = params, headers = {
            [gatewayAuthHeader]: string `Bearer ${gatewayToken}`,
            "Authorization": string `Bearer ${userToken}`
        });

        boolean producesCredentials = credentialTools.indexOf(params.name) !is ();
        CredentialCollector? collector = ();
        if producesCredentials && context.hasKey(key = CREDENTIAL_COLLECTOR_KEY) {
            collector = check context.getWithType(key = CREDENTIAL_COLLECTOR_KEY);
        }
        mcp:ContentBlock[] redactedContent = [];
        foreach mcp:ContentBlock contentBlock in toolResult.content {
            if contentBlock !is mcp:TextContent {
                redactedContent.push(contentBlock);
                continue;
            }
            json|error payload = contentBlock.text.fromJsonString();
            if payload is error {
                if producesCredentials && toolResult.isError != true {
                    // Unreadable output from a secret-producing tool is withheld rather than risked.
                    return error(string `The result of ${params.name} could not be checked for secrets`);
                }
                redactedContent.push(contentBlock);
                continue;
            }
            json redactedPayload = redactSecrets(payload = payload, collector = collector);
            redactedContent.push({'type: "text", text: redactedPayload.toJsonString()});
        }
        // Only the checked text is passed on; structured content is dropped because it is not redacted.
        return {content: redactedContent, isError: toolResult.isError == true};
    }
}
