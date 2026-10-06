import ballerina/http;

final http:ClientSecureSocket & readonly apimSecureSocket = {
    cert: {path: trustStorePath, password: trustStorePassword}
};

final http:Client tokenClient = check new (tokenUrl,
    auth = {username: agentClientId, password: agentClientSecret},
    secureSocket = apimSecureSocket
);

final http:Client signInTokenClient = check new (tokenUrl,
    auth = {username: uiClientId, password: uiClientSecret},
    secureSocket = apimSecureSocket
);

final http:Client userInfoClient = check new (userInfoUrl, secureSocket = apimSecureSocket);

final GatewayTokenProvider gatewayTokenProvider = new (tokenClient);
