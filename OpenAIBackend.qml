import QtQuick
import Quickshell.Io

// Streams chat completions from an OpenAI-compatible API using curl.
// Works with: OpenAI, GitHub Copilot (Models API), Ollama, any compatible endpoint.
Item {
    id: root

    // Configuration — set these before calling send()
    property string apiUrl: "https://api.openai.com/v1/chat/completions"
    property string apiKey: ""
    property string model: "gpt-4o"
    property string systemPrompt: "You are a helpful assistant. Be concise."
    property bool memoryEnabled: false

    // Static prompts appended to the system prompt
    readonly property string _memoryPrompt: "You have access to a persistent memory system. Use it proactively:\n" +
        "READING: At the start of conversations, check relevant memory topics for context. " +
        "Use memory_list_topics to see what's available, then memory_read for relevant topics.\n" +
        "WRITING: When you learn something new about the user (preferences, patterns, environment, projects), " +
        "save it immediately using memory_append. When the user corrects you, update memory. " +
        "When you discover a useful fact (a working command, a solution), save it.\n" +
        "Be selective — save facts and preferences, not conversation transcripts. Use concise bullet points."

    readonly property string _toolPrompt: "You have tools available. Use them when they would help answer " +
        "the user's question accurately. Don't ask permission to use tools — just use them. " +
        "If a tool call fails, report the error briefly and continue."

    // Assembled system prompt
    readonly property string _fullSystemPrompt: {
        let prompt = systemPrompt;
        if (memoryEnabled) {
            prompt += "\n\n" + _memoryPrompt;
        }
        // TODO: add _toolPrompt when MCP tools are wired up
        return prompt;
    }

    // Context management — if set, injected after system prompt
    property string contextSummary: ""

    // Tool definitions (set by ChatWindow when memory is enabled)
    property var tools: []

    // Extra headers for Copilot internal API
    property var extraHeaders: []

    // Signals
    signal tokenReceived(string token)
    signal toolCallReceived(var toolCalls)
    signal usageReceived(int promptTokens, int completionTokens, int totalTokens)
    signal responseFinished()
    signal responseError(string error)

    // State
    readonly property bool streaming: curlProcess.running || writeProcess.running
    property string _accumulatedResponse: ""
    property var _accumulatedToolCalls: []  // [{id, name, arguments}]

    property string _body: ""
    readonly property string _tmpFile: "/tmp/hyprchat-req.json"
    property var _pendingMessages: []  // full message list for tool-use loop

    function send(messages) {
        if (curlProcess.running || writeProcess.running) {
            return;
        }

        _accumulatedResponse = "";
        _accumulatedToolCalls = [];

        // Build the messages array with system prompt prepended
        let apiMessages = [{ role: "system", content: _fullSystemPrompt }];

        // If we have a summary, inject it as context
        if (contextSummary.length > 0) {
            apiMessages.push({ role: "system", content: "Previous conversation summary:\n" + contextSummary });
        }

        // Only send messages marked as sent
        for (let i = 0; i < messages.count; i++) {
            let msg = messages.get(i);
            if (msg.text === "..." || msg.role === "system") continue;
            if (msg.sent === false) continue;
            apiMessages.push({ role: msg.role, content: msg.text });
        }

        _sendApiMessages(apiMessages);
    }

    // Send raw API messages (used by both initial send and tool-use loop)
    function _sendApiMessages(apiMessages) {
        _pendingMessages = apiMessages;

        let body = {
            model: model,
            messages: apiMessages,
            stream: true
        };

        // Include tool definitions if available
        if (tools.length > 0) {
            body.tools = tools;
        }

        _body = JSON.stringify(body);

        writeProcess.command = ["bash", "-c", "cat > " + _tmpFile];
        writeProcess.stdinEnabled = true;
        writeProcess.running = true;
    }

    // Continue after tool execution — append tool results and re-send
    function continueWithToolResults(toolCallMsg, toolResults) {
        let msgs = _pendingMessages.slice();

        // Append the assistant's tool_call message
        msgs.push(toolCallMsg);

        // Append each tool result
        for (let i = 0; i < toolResults.length; i++) {
            msgs.push(toolResults[i]);
        }

        _accumulatedResponse = "";
        _accumulatedToolCalls = [];
        _sendApiMessages(msgs);
    }

    // Step 1: Write JSON to temp file
    Process {
        id: writeProcess
        running: false

        onStarted: {
            writeProcess.write(root._body);
            writeProcess.stdinEnabled = false;
        }

        onExited: (exitCode, exitStatus) => {
            // Step 2: Launch curl reading from the file
            curlProcess.command = [
                "curl", "-sN", "--no-buffer",
                root.apiUrl,
                "-H", "Content-Type: application/json",
                "-H", "Authorization: Bearer " + root.apiKey,
                "-d", "@" + root._tmpFile
            ].concat(root.extraHeaders);
            console.log("OpenAIBackend: sending to", root.apiUrl, "model:", root.model);
            curlProcess.running = true;
        }
    }

    function cancel() {
        if (curlProcess.running) {
            curlProcess.running = false;
        }
    }

    property string _sseBuffer: ""

    Process {
        id: curlProcess
        running: false

        stdout: SplitParser {
            splitMarker: "\n\n"
            onRead: (chunk) => {
                let lines = chunk.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];
                    if (!line.startsWith("data: ")) continue;
                    let payload = line.substring(6).trim();
                    if (payload === "[DONE]") continue;
                    try {
                        let json = JSON.parse(payload);
                        let delta = json.choices && json.choices[0] && json.choices[0].delta;
                        if (delta) {
                            // Stream content tokens
                            if (delta.content) {
                                root._accumulatedResponse += delta.content;
                                root.tokenReceived(delta.content);
                            }
                            // Accumulate tool calls (streamed in chunks)
                            if (delta.tool_calls) {
                                for (let t = 0; t < delta.tool_calls.length; t++) {
                                    let tc = delta.tool_calls[t];
                                    let idx = tc.index !== undefined ? tc.index : 0;
                                    // Initialize slot if needed
                                    while (root._accumulatedToolCalls.length <= idx) {
                                        root._accumulatedToolCalls.push({ id: "", name: "", arguments: "" });
                                    }
                                    if (tc.id) root._accumulatedToolCalls[idx].id = tc.id;
                                    if (tc.function && tc.function.name) root._accumulatedToolCalls[idx].name = tc.function.name;
                                    if (tc.function && tc.function.arguments) root._accumulatedToolCalls[idx].arguments += tc.function.arguments;
                                }
                            }
                        }
                        // Capture usage stats
                        if (json.usage) {
                            root.usageReceived(
                                json.usage.prompt_tokens || 0,
                                json.usage.completion_tokens || 0,
                                json.usage.total_tokens || 0
                            );
                        }
                    } catch (e) {}
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line.trim().length > 0) {
                    console.warn("Backend stderr:", line);
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            console.log("OpenAIBackend: curl exited, code:", exitCode, "streamed:", root._accumulatedResponse.length, "chars, toolCalls:", root._accumulatedToolCalls.length);
            if (exitCode !== 0 && root._accumulatedResponse.length === 0 && root._accumulatedToolCalls.length === 0) {
                root.responseError("Request failed (exit code " + exitCode + ")");
            } else if (root._accumulatedToolCalls.length > 0) {
                // Model wants to call tools — emit for ChatWindow to handle
                root.toolCallReceived(root._accumulatedToolCalls);
            } else {
                root.responseFinished();
            }
        }
    }
}
