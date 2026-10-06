import ballerina/http;
import ballerina/time;

// Renew this many seconds before the token expires.
const int EXPIRY_MARGIN_SECONDS = 60;

# Supplies the agent application's gateway token, fetching a new one when the cached token nears expiry.
isolated class GatewayTokenProvider {
    private final http:Client tokenClient;
    private string accessToken = "";
    private int expiresAtSeconds = 0;

    # + tokenClient - Client for the token endpoint, authenticating as the agent application
    isolated function init(http:Client tokenClient) {
        self.tokenClient = tokenClient;
    }

    isolated function getToken() returns string|error {
        lock {
            int nowSeconds = time:utcNow()[0];
            if self.accessToken != "" && nowSeconds < self.expiresAtSeconds - EXPIRY_MARGIN_SECONDS {
                return self.accessToken;
            }
            TokenResponse tokenResponse = check self.tokenClient->post(path = "",
                message = {grant_type: "client_credentials"},
                mediaType = "application/x-www-form-urlencoded"
            );
            self.accessToken = tokenResponse.access_token;
            self.expiresAtSeconds = nowSeconds + tokenResponse.expires_in;
            return self.accessToken;
        }
    }
}
