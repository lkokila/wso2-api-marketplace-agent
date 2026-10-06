import ballerina/ai;
import ballerina/http;
import ballerina/log;

const string BEARER_PREFIX = "Bearer ";

// A caller whose token has been validated.
type AuthenticatedUser record {|
    string name;
    string token;
|};

type ChatResult ChatResponse|http:Unauthorized|http:Conflict|http:InternalServerError;

listener http:Listener agentListener = new (agentPort);

@http:ServiceConfig {
    cors: {
        allowOrigins: [uiOrigin],
        allowMethods: ["POST", "OPTIONS"],
        allowHeaders: ["Authorization", "Content-Type"],
        maxAge: 600
    }
}
service /agent on agentListener {

    # Redeems the authorization code the UI received at sign-in for the user's tokens.
    #
    # + signInRequest - The code, its PKCE verifier and the redirect URI used
    # + return - The user's session, or an error payload
    resource function post auth/token(SignInRequest signInRequest)
            returns SignInResponse|http:Unauthorized|http:InternalServerError {
        TokenResponse|error tokenResponse = signInTokenClient->post(path = "",
            message = {
                grant_type: "authorization_code",
                code: signInRequest.code,
                code_verifier: signInRequest.codeVerifier,
                redirect_uri: signInRequest.redirectUri
            },
            mediaType = "application/x-www-form-urlencoded"
        );
        if tokenResponse is http:ClientRequestError {
            log:printWarn("Sign-in code was not accepted", reason = tokenResponse.message());
            return <http:Unauthorized>{body: <ErrorResponse>{message: "Sign-in failed. Please try again."}};
        }
        if tokenResponse is error {
            log:printError("Could not redeem the sign-in code", 'error = tokenResponse);
            return <http:InternalServerError>{body: <ErrorResponse>{message: "Sign-in is unavailable"}};
        }
        string? idToken = tokenResponse.id_token;
        AuthenticatedUser|http:Unauthorized|http:InternalServerError user =
            authenticate(authorization = BEARER_PREFIX + tokenResponse.access_token);
        if user !is AuthenticatedUser {
            return user;
        }
        if idToken is () {
            log:printError("The token response has no ID token; is the openid scope requested?");
            return <http:InternalServerError>{body: <ErrorResponse>{message: "Sign-in is unavailable"}};
        }
        return {
            accessToken: tokenResponse.access_token,
            expiresIn: tokenResponse.expires_in,
            idToken,
            userName: user.name
        };
    }

    # Sends a message to the agent on behalf of the signed-in user.
    #
    # + authorization - `Bearer` token of the user, carrying the Devportal scopes
    # + chatRequest - The session and message
    # + return - The agent's reply or the approvals it needs, or an error payload
    resource function post chat(@http:Header string? authorization, ChatRequest chatRequest) returns ChatResult {
        AuthenticatedUser|http:Unauthorized|http:InternalServerError user = authenticate(authorization = authorization);
        if user !is AuthenticatedUser {
            return user;
        }
        return runAgent(user = user, sessionId = chatRequest.sessionId, input = chatRequest.message);
    }

    # Answers the approvals a previous response asked for and continues the paused turn.
    #
    # + authorization - `Bearer` token of the user, carrying the Devportal scopes
    # + decisionRequest - The session and the user's decisions
    # + return - The agent's reply or further approvals it needs, or an error payload
    resource function post chat/decisions(@http:Header string? authorization, DecisionRequest decisionRequest)
            returns ChatResult {
        AuthenticatedUser|http:Unauthorized|http:InternalServerError user = authenticate(authorization = authorization);
        if user !is AuthenticatedUser {
            return user;
        }
        map<ai:HumanDecision> humanDecisions = {};
        foreach Decision decision in decisionRequest.decisions {
            ai:HumanDecision humanDecision = {outcome: decision.approved ? ai:APPROVE : ai:REJECT};
            string? reason = decision.reason;
            if reason is string {
                humanDecision.reason = reason;
            }
            humanDecisions[decision.id] = humanDecision;
        }
        ai:Resume resume = {decisions: humanDecisions.cloneReadOnly()};
        return runAgent(user = user, sessionId = decisionRequest.sessionId, input = resume);
    }
}

# Validates the caller's token at the userinfo endpoint.
#
# + authorization - Value of the `Authorization` header, if any
# + return - The user, or the error response to send
function authenticate(string? authorization) returns AuthenticatedUser|http:Unauthorized|http:InternalServerError {
    if authorization is () || !authorization.startsWith(BEARER_PREFIX) {
        return <http:Unauthorized>{body: <ErrorResponse>{message: "A Bearer token is required"}};
    }
    UserInfo|error userInfo = userInfoClient->get(path = "", headers = {"Authorization": authorization});
    if userInfo is http:ClientRequestError {
        log:printWarn("Rejected a chat request with an invalid user token", reason = userInfo.message());
        return <http:Unauthorized>{body: <ErrorResponse>{message: "The token is invalid or expired"}};
    }
    if userInfo is error {
        log:printError("Could not validate the user token", 'error = userInfo);
        return <http:InternalServerError>{body: <ErrorResponse>{message: "The user could not be verified"}};
    }
    return {name: userInfo.sub, token: authorization.substring(startIndex = BEARER_PREFIX.length())};
}

# Runs or resumes an agent turn as the given user.
#
# + user - The validated caller
# + sessionId - The client's conversation identifier
# + input - A new message, or the decisions that resume a paused turn
# + return - The reply or the approvals needed, or the error response to send
function runAgent(AuthenticatedUser user, string sessionId, string|ai:Resume input) returns ChatResult {
    CredentialCollector credentialCollector = new;
    ai:Context context = new;
    context.set(key = USER_TOKEN_KEY, value = user.token);
    context.set(key = CREDENTIAL_COLLECTOR_KEY, value = credentialCollector);
    // Memory is keyed by user as well as session, so one user cannot read or approve another's conversation.
    string memoryKey = string `${user.name}:${sessionId}`;

    string|ai:Error answer = devportalAgent.run(query = input, sessionId = memoryKey, context = context);
    if answer is string {
        return {status: COMPLETED, message: answer, credentials: credentialCollector.getAll()};
    }
    if answer is ai:ApprovalRequiredError {
        ai:ApprovalRequest[] approvalRequests = answer.detail().requests;
        return {
            status: APPROVAL_REQUIRED,
            approvals: describeApprovals(requests = approvalRequests, context = context),
            credentials: credentialCollector.getAll()
        };
    }
    if answer is ai:ApprovalNotFoundError|ai:UnknownApprovalIdError {
        return <http:Conflict>{body: <ErrorResponse>{message: "There is no pending approval matching that decision"}};
    }
    log:printError("Agent run failed", 'error = answer, user = user.name, sessionId = sessionId);
    return <http:InternalServerError>{body: <ErrorResponse>{message: "The agent could not complete the request"}};
}
