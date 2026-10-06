import ballerina/ai;
import ballerina/mcp;

// Turns the agent's raw approval requests into something a person can judge:
// a plain description of the action and its values, with ids resolved to names.

final readonly & map<string> actionTitles = {
    "create_application": "Create an application",
    "subscribe_to_api": "Subscribe an application to an API",
    "unsubscribe_from_api": "Remove a subscription",
    "generate_application_keys": "Generate OAuth keys for an application"
};

final readonly & map<string> detailLabels = {
    "applicationId": "Application",
    "apiId": "API",
    "subscriptionId": "Subscription",
    "throttlingPolicy": "Throttling tier",
    "name": "Name",
    "description": "Description",
    "keyType": "Key type",
    "keyManager": "Key manager",
    "grantTypesToBeSupported": "Grant types",
    "callbackUrl": "Callback URL",
    "validityTime": "Validity (seconds)",
    "scopes": "Scopes"
};

// The fields of Devportal responses needed to name a resource.
type NamedResource record {
    string name?;
    string version?;
    NamedResource apiInfo?;
    NamedResource applicationInfo?;
    string throttlingPolicy?;
};

# Describes pending approvals for the user.
#
# + requests - The agent's approval requests
# + context - Context of the current turn, used to look names up as the user
# + return - One approval per request
isolated function describeApprovals(ai:ApprovalRequest[] requests, ai:Context context) returns Approval[] {
    Approval[] approvals = [];
    foreach ai:ApprovalRequest request in requests {
        ApprovalDetail[] details = [];
        foreach [string, json] [argumentName, argumentValue] in request.arguments.entries() {
            if argumentName == "requestBody" && argumentValue is map<json> {
                foreach [string, json] [bodyField, bodyValue] in argumentValue.entries() {
                    details.push(describeDetail(fieldName = bodyField, fieldValue = bodyValue, context = context));
                }
            } else {
                details.push(describeDetail(fieldName = argumentName, fieldValue = argumentValue, context = context));
            }
        }
        approvals.push({
            id: request.id,
            toolName: request.toolName,
            action: actionTitles[request.toolName] ?: request.toolName,
            details
        });
    }
    return approvals;
}

isolated function describeDetail(string fieldName, json fieldValue, ai:Context context) returns ApprovalDetail {
    string label = detailLabels[fieldName] ?: fieldName;
    string displayValue = fieldValue is string ? fieldValue : fieldValue.toJsonString();
    if fieldValue is string {
        string? resolvedName = resolveName(fieldName = fieldName, identifier = fieldValue, context = context);
        if resolvedName is string {
            displayValue = resolvedName;
        }
    }
    return {label, value: displayValue};
}

// Looks up the display name behind an identifier. Returns `()` when the field is not an
// identifier or the lookup fails; the raw value is shown in that case.
isolated function resolveName(string fieldName, string identifier, ai:Context context) returns string? {
    match fieldName {
        "applicationId" => {
            NamedResource? application = lookUp(toolName = "get_application",
                    arguments = {applicationId: identifier}, context = context);
            return application?.name;
        }
        "apiId" => {
            NamedResource? api = lookUp(toolName = "get_api", arguments = {apiId: identifier}, context = context);
            string? apiName = api?.name;
            string? apiVersion = api?.version;
            return apiName is string && apiVersion is string ? string `${apiName} ${apiVersion}` : apiName;
        }
        "subscriptionId" => {
            NamedResource? subscription = lookUp(toolName = "get_subscription",
                    arguments = {subscriptionId: identifier}, context = context);
            string? apiName = subscription?.apiInfo?.name;
            string? applicationName = subscription?.applicationInfo?.name;
            if apiName is string && applicationName is string {
                return string `${applicationName} to ${apiName}`;
            }
        }
    }
    return ();
}

isolated function lookUp(string toolName, map<string> arguments, ai:Context context) returns NamedResource? {
    mcp:CallToolResult|error toolResult = devportalToolKit.callTool(context = context,
            params = {name: toolName, arguments: arguments});
    if toolResult is error || toolResult.isError == true || toolResult.content.length() == 0 {
        return ();
    }
    mcp:ContentBlock firstBlock = toolResult.content[0];
    if firstBlock !is mcp:TextContent {
        return ();
    }
    NamedResource|error namedResource = firstBlock.text.fromJsonStringWithType();
    return namedResource is error ? () : namedResource;
}
