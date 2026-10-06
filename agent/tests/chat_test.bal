import ballerina/http;
import ballerina/lang.regexp;
import ballerina/test;
import ballerina/uuid;

// Integration tests: they need API Manager running with the Devportal MCP server
// provisioned (mcp-server/scripts/provision.sh) and the test user created.

configurable string testClientId = ?;
configurable string testClientSecret = ?;
configurable string adminUser = ?;
configurable string adminPassword = ?;
configurable string testUser = ?;
configurable string testUserPassword = ?;
configurable string devportalApiUrl = ?;

const string USER_SCOPES = "openid apim:subscribe apim:app_manage apim:sub_manage";
const string LIST_APPLICATIONS = "CALL list_applications {}";

final http:Client agentClient = check new (string `http://localhost:${agentPort}/agent`);

final http:Client userTokenClient = check new (tokenUrl,
    auth = {username: testClientId, password: testClientSecret},
    secureSocket = apimSecureSocket
);

final http:Client devportalClient = check new (devportalApiUrl, secureSocket = apimSecureSocket);

function getUserToken(string userName, string password) returns string|error {
    TokenResponse tokenResponse = check userTokenClient->post(path = "",
        message = {grant_type: "password", username: userName, password: password, scope: USER_SCOPES},
        mediaType = "application/x-www-form-urlencoded"
    );
    return tokenResponse.access_token;
}

function getTestUserToken() returns string|error => getUserToken(userName = testUser, password = testUserPassword);

function chat(string userToken, string sessionId, string message) returns ChatResponse|error {
    ChatRequest chatRequest = {sessionId, message};
    return agentClient->post(path = "/chat", message = chatRequest,
        headers = {"Authorization": string `Bearer ${userToken}`}
    );
}

function decide(string userToken, string sessionId, string approvalId, boolean approved) returns ChatResponse|error {
    DecisionRequest decisionRequest = {sessionId, decisions: [{id: approvalId, approved}]};
    return agentClient->post(path = "/chat/decisions", message = decisionRequest,
        headers = {"Authorization": string `Bearer ${userToken}`}
    );
}

function newSession() returns string => uuid:createType4AsString();

function createApplicationCall(string applicationName) returns string =>
    string `CALL create_application {"requestBody":{"name":"${applicationName}","throttlingPolicy":"Unlimited"}}`;

function detailValue(Approval approval, string label) returns string? {
    foreach ApprovalDetail detail in approval.details {
        if detail.label == label {
            return detail.value;
        }
    }
    return ();
}

@test:Config
function testToolRunsAsTestUser() returns error? {
    ChatResponse chatResponse = check chat(userToken = check getTestUserToken(), sessionId = newSession(),
            message = LIST_APPLICATIONS);
    test:assertEquals(chatResponse.status, COMPLETED);
    test:assertTrue(chatResponse.message.includes(string `"owner":"${testUser}"`), msg = chatResponse.message);
    test:assertFalse(chatResponse.message.includes(string `"owner":"${adminUser}"`), msg = chatResponse.message);
}

@test:Config
function testToolRunsAsAdmin() returns error? {
    string adminToken = check getUserToken(userName = adminUser, password = adminPassword);
    ChatResponse chatResponse = check chat(userToken = adminToken, sessionId = newSession(), message = LIST_APPLICATIONS);
    test:assertTrue(chatResponse.message.includes(string `"owner":"${adminUser}"`), msg = chatResponse.message);
    test:assertFalse(chatResponse.message.includes(string `"owner":"${testUser}"`), msg = chatResponse.message);
}

@test:Config
function testInvalidTokenIsRejected() returns error? {
    ChatRequest chatRequest = {sessionId: newSession(), message: LIST_APPLICATIONS};
    http:Response chatResponse = check agentClient->post(path = "/chat", message = chatRequest,
        headers = {"Authorization": "Bearer not-a-real-token"}
    );
    test:assertEquals(chatResponse.statusCode, http:STATUS_UNAUTHORIZED);
}

@test:Config
function testMissingTokenIsRejected() returns error? {
    ChatRequest chatRequest = {sessionId: newSession(), message: LIST_APPLICATIONS};
    http:Response chatResponse = check agentClient->post(path = "/chat", message = chatRequest);
    test:assertEquals(chatResponse.statusCode, http:STATUS_UNAUTHORIZED);
}

@test:Config
function testRejectedActionDoesNotRun() returns error? {
    string userToken = check getTestUserToken();
    string sessionId = newSession();
    string applicationName = string `Rejected${uuid:createType4AsString().substring(startIndex = 0, endIndex = 8)}`;

    ChatResponse pausedResponse = check chat(userToken = userToken, sessionId = sessionId,
            message = createApplicationCall(applicationName = applicationName));
    test:assertEquals(pausedResponse.status, APPROVAL_REQUIRED);
    test:assertEquals(pausedResponse.approvals.length(), 1);
    Approval approval = pausedResponse.approvals[0];
    test:assertEquals(approval.toolName, "create_application");
    test:assertEquals(detailValue(approval = approval, label = "Name"), applicationName);

    ChatResponse beforeDecision = check chat(userToken = userToken, sessionId = newSession(), message = LIST_APPLICATIONS);
    test:assertFalse(beforeDecision.message.includes(applicationName), msg = "The action ran before it was approved");

    ChatResponse rejectedResponse = check decide(userToken = userToken, sessionId = sessionId,
            approvalId = approval.id, approved = false);
    test:assertEquals(rejectedResponse.status, COMPLETED);

    ChatResponse afterDecision = check chat(userToken = userToken, sessionId = newSession(), message = LIST_APPLICATIONS);
    test:assertFalse(afterDecision.message.includes(applicationName), msg = "A rejected action ran");
}

@test:Config
function testAnotherUserCannotApprove() returns error? {
    string userToken = check getTestUserToken();
    string adminToken = check getUserToken(userName = adminUser, password = adminPassword);
    string sessionId = newSession();
    string applicationName = string `Hijack${uuid:createType4AsString().substring(startIndex = 0, endIndex = 8)}`;

    ChatResponse pausedResponse = check chat(userToken = userToken, sessionId = sessionId,
            message = createApplicationCall(applicationName = applicationName));
    string approvalId = pausedResponse.approvals[0].id;

    DecisionRequest decisionRequest = {sessionId, decisions: [{id: approvalId, approved: true}]};
    http:Response hijackResponse = check agentClient->post(path = "/chat/decisions", message = decisionRequest,
        headers = {"Authorization": string `Bearer ${adminToken}`}
    );
    test:assertEquals(hijackResponse.statusCode, http:STATUS_CONFLICT);

    ChatResponse rejectedResponse = check decide(userToken = userToken, sessionId = sessionId,
            approvalId = approvalId, approved = false);
    test:assertEquals(rejectedResponse.status, COMPLETED);
}

@test:Config
function testApprovedActionsRunAndSecretsAreWithheld() returns error? {
    string userToken = check getTestUserToken();
    string sessionId = newSession();
    string applicationName = string `Approved${uuid:createType4AsString().substring(startIndex = 0, endIndex = 8)}`;

    ChatResponse pausedCreate = check chat(userToken = userToken, sessionId = sessionId,
            message = createApplicationCall(applicationName = applicationName));
    test:assertEquals(pausedCreate.status, APPROVAL_REQUIRED);
    ChatResponse created = check decide(userToken = userToken, sessionId = sessionId,
            approvalId = pausedCreate.approvals[0].id, approved = true);
    test:assertEquals(created.status, COMPLETED);
    string applicationId = check extractApplicationId(toolOutput = created.message);

    do {
        string generateKeysCall = string `CALL generate_application_keys {"applicationId":"${applicationId}",` +
            string `"requestBody":{"keyType":"PRODUCTION","grantTypesToBeSupported":["client_credentials"],` +
            string `"keyManager":"Resident Key Manager"}}`;
        ChatResponse pausedKeys = check chat(userToken = userToken, sessionId = sessionId, message = generateKeysCall);
        test:assertEquals(pausedKeys.status, APPROVAL_REQUIRED);
        Approval keysApproval = pausedKeys.approvals[0];
        test:assertEquals(detailValue(approval = keysApproval, label = "Application"), applicationName,
                msg = "The application id was not resolved to its name");
        test:assertEquals(pausedKeys.credentials.length(), 0);

        ChatResponse keysResponse = check decide(userToken = userToken, sessionId = sessionId,
                approvalId = keysApproval.id, approved = true);
        test:assertEquals(keysResponse.status, COMPLETED);
        test:assertTrue(keysResponse.message.includes("consumerKey"), msg = keysResponse.message);
        string[] credentialNames = keysResponse.credentials.map(credential => credential.name);
        test:assertTrue(credentialNames.indexOf("consumerSecret") !is (), msg = credentialNames.toString());
        test:assertTrue(credentialNames.indexOf("accessToken") !is (), msg = credentialNames.toString());
        foreach Credential credential in keysResponse.credentials {
            test:assertFalse(keysResponse.message.includes(credential.value),
                    msg = string `The ${credential.name} reached the model`);
        }

        // Reading the keys back must not reveal the secret either, nor hand it to the UI.
        string listKeysCall = string `CALL list_application_keys {"applicationId":"${applicationId}"}`;
        ChatResponse listedKeys = check chat(userToken = userToken, sessionId = sessionId, message = listKeysCall);
        test:assertEquals(listedKeys.credentials.length(), 0);
        foreach Credential credential in keysResponse.credentials {
            test:assertFalse(listedKeys.message.includes(credential.value),
                    msg = string `Listing keys revealed the ${credential.name}`);
        }
    } on fail error failure {
        check deleteApplication(userToken = userToken, applicationId = applicationId);
        return failure;
    }
    check deleteApplication(userToken = userToken, applicationId = applicationId);
}

function extractApplicationId(string toolOutput) returns string|error {
    regexp:Groups? idGroups = re `"applicationId":"([^"]+)"`.findGroups(toolOutput);
    regexp:Span? idSpan = idGroups is () ? () : idGroups[1];
    if idSpan is () {
        return error(string `No application id in the tool output: ${toolOutput}`);
    }
    return idSpan.substring();
}

function deleteApplication(string userToken, string applicationId) returns error? {
    http:Response deleteResponse = check devportalClient->delete(path = string `/applications/${applicationId}`,
        headers = {"Authorization": string `Bearer ${userToken}`}
    );
    test:assertEquals(deleteResponse.statusCode, http:STATUS_OK);
}
