import ballerina/http;

// Stands in for the model service so the tests exercise the real agent loop, toolkit and
// gateway without an LLM. A user message of the form `CALL <tool> <json arguments>` makes
// it request that tool call; it then answers with whatever the tool (or a rejection) returned.

configurable int llmStubPort = ?;

const string CALL_PREFIX = "CALL ";

// Field names follow the chat completions wire format.
type StubRequestMessage record {
    string role;
    string? content?;
};

type StubCompletionRequest record {
    StubRequestMessage[] messages;
};

type StubFunctionCall record {|
    string name;
    string arguments;
|};

type StubResponseMessage record {|
    string role = "assistant";
    string? content = ();
    StubFunctionCall function_call?;
|};

type StubChoice record {|
    int index = 0;
    StubResponseMessage message;
    string finish_reason;
|};

type StubCompletionResponse record {|
    string id = "stub-completion";
    string 'object = "chat.completion";
    int created = 0;
    string model = "stub";
    StubChoice[] choices;
|};

listener http:Listener llmStubListener = new (llmStubPort);

service /llm on llmStubListener {

    resource function post chat/completions(StubCompletionRequest completionRequest) returns StubCompletionResponse {
        StubRequestMessage lastMessage = completionRequest.messages[completionRequest.messages.length() - 1];
        string lastContent = lastMessage?.content ?: "";
        if lastMessage.role == "user" && lastContent.startsWith(CALL_PREFIX) {
            string instruction = lastContent.substring(startIndex = CALL_PREFIX.length());
            int separatorIndex = instruction.indexOf(" ") ?: instruction.length();
            string toolName = instruction.substring(startIndex = 0, endIndex = separatorIndex);
            string toolArguments = instruction.substring(startIndex = separatorIndex).trim();
            return {
                choices: [
                    {
                        message: {function_call: {name: toolName, arguments: toolArguments == "" ? "{}" : toolArguments}},
                        finish_reason: "function_call"
                    }
                ]
            };
        }
        return {choices: [{message: {content: lastContent}, finish_reason: "stop"}]};
    }
}
