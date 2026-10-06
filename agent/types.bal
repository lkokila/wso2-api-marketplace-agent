# A chat message sent by the UI.
public type ChatRequest record {|
    # Conversation identifier chosen by the client; messages with the same value share memory.
    string sessionId;
    # The user's message.
    string message;
|};

# The user's answers to the approvals a previous response asked for.
public type DecisionRequest record {|
    # The conversation that is waiting for approval.
    string sessionId;
    # One decision per pending approval.
    Decision[] decisions;
|};

# The user's answer to one pending approval.
public type Decision record {|
    # The `id` of the approval being answered.
    string id;
    # `true` to let the action run, `false` to block it.
    boolean approved;
    # When blocking, optional guidance for the agent.
    string reason?;
|};

# Whether the agent finished its turn or is waiting for the user to approve an action.
public enum ChatStatus {
    COMPLETED,
    APPROVAL_REQUIRED
}

# The agent's reply.
public type ChatResponse record {|
    # `COMPLETED` when `message` is the reply; `APPROVAL_REQUIRED` when `approvals` must be answered first.
    ChatStatus status;
    # The reply text. Empty while approval is required.
    string message = "";
    # Actions waiting for the user's approval.
    Approval[] approvals = [];
    # Secrets produced during this turn. They are withheld from the model and must be shown by the UI.
    Credential[] credentials = [];
|};

# An action the agent wants to perform, described for the user.
public type Approval record {|
    # Identifier to send back in the decision.
    string id;
    # Name of the tool the agent wants to call.
    string toolName;
    # What the action does, in plain words.
    string action;
    # The values the action would use.
    ApprovalDetail[] details;
|};

# One labelled value of a pending action.
public type ApprovalDetail record {|
    # What the value is.
    string label;
    # The value, with identifiers resolved to names where possible.
    string value;
|};

# A secret returned by a tool, delivered to the UI instead of the model.
public type Credential record {|
    # The field the secret came from: `consumerSecret`, `accessToken`, ...
    string name;
    # The secret itself.
    string value;
    # Consumer key of the key set the secret belongs to, when known.
    string consumerKey?;
|};

# The authorization code the UI received after the user signed in.
public type SignInRequest record {|
    # Authorization code from the redirect.
    string code;
    # PKCE verifier matching the challenge the UI sent to the authorization endpoint.
    string codeVerifier;
    # Redirect URI the UI used; must match the one registered for the client.
    string redirectUri;
|};

# The signed-in user's session.
public type SignInResponse record {|
    # Token to send as `Authorization: Bearer` to the chat API.
    string accessToken;
    # Seconds until the access token expires.
    int expiresIn;
    # ID token, needed to sign out at the identity provider.
    string idToken;
    # The user's name.
    string userName;
|};

# Error payload returned by the chat API.
public type ErrorResponse record {|
    # What went wrong.
    string message;
|};

// Field names follow the OAuth2 token response.
type TokenResponse record {
    string access_token;
    int expires_in;
    string id_token?;
};

// Field names follow the OIDC userinfo response.
type UserInfo record {
    string sub;
};
