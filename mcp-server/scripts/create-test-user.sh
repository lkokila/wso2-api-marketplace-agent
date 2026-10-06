#!/usr/bin/env bash
# Creates the developer account used by smoke-test.sh, with the Internal/subscriber role.
. "$(dirname "$0")/lib.sh"

envelope='<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ser="http://service.ws.um.carbon.wso2.org"><soapenv:Body>'
exists="$(http -u "$APIM_ADMIN_USER:$APIM_ADMIN_PASSWORD" -H "Content-Type: text/xml" -H "SOAPAction: urn:isExistingUser" \
    -d "$envelope<ser:isExistingUser><ser:userName>$TEST_USER</ser:userName></ser:isExistingUser></soapenv:Body></soapenv:Envelope>" \
    "$APIM_MGT_URL/services/RemoteUserStoreManagerService")"
if [[ "$exists" == *">true<"* ]]; then
    log "User $TEST_USER already exists"
    exit 0
fi
http -u "$APIM_ADMIN_USER:$APIM_ADMIN_PASSWORD" -H "Content-Type: text/xml" -H "SOAPAction: urn:addUser" -o /dev/null \
    -d "$envelope<ser:addUser><ser:userName>$TEST_USER</ser:userName><ser:credential>$TEST_USER_PASSWORD</ser:credential><ser:roleList>Internal/subscriber</ser:roleList><ser:requirePasswordChange>false</ser:requirePasswordChange></ser:addUser></soapenv:Body></soapenv:Envelope>" \
    "$APIM_MGT_URL/services/RemoteUserStoreManagerService"
log "Created user $TEST_USER"
