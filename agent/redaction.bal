// Keeps secrets away from the model. Every tool result passes through `redactSecrets`,
// which blanks secret values and, for tools whose purpose is to produce a secret,
// hands the real value to a `CredentialCollector` so the UI can show it to the user.

// Context key under which the chat service stores the turn's `CredentialCollector`.
const string CREDENTIAL_COLLECTOR_KEY = "credentialCollector";

const string REDACTED_VALUE = "(shown in the credentials card below this message)";

// String-valued fields of the Devportal REST API that hold secrets.
final readonly & string[] secretFields = ["consumerSecret", "clientSecret", "secretValue", "accessToken", "apikey"];

# Gathers the secrets produced by tools during one chat turn.
isolated class CredentialCollector {
    private final Credential[] credentials = [];

    isolated function add(Credential credential) {
        lock {
            self.credentials.push(credential.clone());
        }
    }

    isolated function getAll() returns Credential[] {
        lock {
            return self.credentials.clone();
        }
    }
}

# Returns a copy of a tool result payload with secret values replaced.
#
# The payload is walked as raw JSON on purpose: redaction must not depend on knowing the
# shape of each response, so that a secret in an unexpected place is still caught.
#
# + payload - Parsed tool result
# + collector - Receives the removed secrets; `()` to discard them
# + consumerKey - Consumer key of the enclosing key set, if one was seen higher up
# + return - The redacted payload
isolated function redactSecrets(json payload, CredentialCollector? collector, string? consumerKey = ()) returns json {
    if payload is json[] {
        json[] redactedItems = [];
        foreach json item in payload {
            redactedItems.push(redactSecrets(payload = item, collector = collector, consumerKey = consumerKey));
        }
        return redactedItems;
    }
    if payload !is map<json> {
        return payload;
    }
    json ownConsumerKey = payload["consumerKey"];
    string? nearestConsumerKey = ownConsumerKey is string ? ownConsumerKey : consumerKey;
    map<json> redactedFields = {};
    foreach [string, json] [fieldName, fieldValue] in payload.entries() {
        if fieldValue is string && secretFields.indexOf(fieldName) !is () {
            if collector !is () && fieldValue != "" {
                Credential credential = {name: fieldName, value: fieldValue};
                if nearestConsumerKey is string {
                    credential.consumerKey = nearestConsumerKey;
                }
                collector.add(credential = credential);
            }
            redactedFields[fieldName] = REDACTED_VALUE;
        } else {
            redactedFields[fieldName] = redactSecrets(payload = fieldValue, collector = collector,
                    consumerKey = nearestConsumerKey);
        }
    }
    return redactedFields;
}
