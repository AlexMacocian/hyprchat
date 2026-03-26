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

    // Extra headers for Copilot internal API
    property var extraHeaders: []

    // Signals
    signal tokenReceived(string token)
    signal usageReceived(int promptTokens, int completionTokens, int totalTokens)
    signal responseFinished()
    signal responseError(string error)

    // State
    readonly property bool streaming: curlProcess.running
    property string _accumulatedResponse: ""

    property string _body: ""
    readonly property string _tmpFile: "/tmp/hyprchat-req.json"

    function send(messages) {
        if (curlProcess.running || writeProcess.running) {
            return;
        }

        _accumulatedResponse = "";

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

        _body = JSON.stringify({
            model: model,
            messages: apiMessages,
            stream: true
        });

        // Step 1: Write body to temp file
        writeProcess.command = ["bash", "-c", "cat > " + _tmpFile];
        writeProcess.stdinEnabled = true;
        writeProcess.running = true;
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
                // Each chunk is one or more SSE events separated by blank lines
                let lines = chunk.split("\n");
                for (let i = 0; i < lines.length; i++) {
                    let line = lines[i];
                    if (!line.startsWith("data: ")) continue;
                    let payload = line.substring(6).trim();
                    if (payload === "[DONE]") continue;
                    try {
                        let json = JSON.parse(payload);
                        // Stream content tokens
                        if (json.choices && json.choices[0] && json.choices[0].delta && json.choices[0].delta.content) {
                            let content = json.choices[0].delta.content;
                            root._accumulatedResponse += content;
                            root.tokenReceived(content);
                        }
                        // Capture usage stats (usually in the last chunk)
                        if (json.usage) {
                            let u = json.usage;
                            root.usageReceived(
                                u.prompt_tokens || 0,
                                u.completion_tokens || 0,
                                u.total_tokens || 0
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
            console.log("OpenAIBackend: curl exited, code:", exitCode, "streamed:", root._accumulatedResponse.length, "chars");
            if (exitCode !== 0 && root._accumulatedResponse.length === 0) {
                root.responseError("Request failed (exit code " + exitCode + ")");
            } else {
                root.responseFinished();
            }
        }
    }
}
