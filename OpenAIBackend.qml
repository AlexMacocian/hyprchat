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

    // Signals
    signal tokenReceived(string token)
    signal responseFinished()
    signal responseError(string error)

    // State
    readonly property bool streaming: curlProcess.running
    property string _accumulatedResponse: ""

    function send(messages) {
        if (curlProcess.running) {
            return;
        }

        _accumulatedResponse = "";

        // Build the messages array with system prompt prepended
        let apiMessages = [{ role: "system", content: systemPrompt }];
        for (let i = 0; i < messages.count; i++) {
            let msg = messages.get(i);
            apiMessages.push({ role: msg.role, content: msg.text });
        }

        let body = JSON.stringify({
            model: model,
            messages: apiMessages,
            stream: true
        });

        curlProcess.command = [
            "curl", "-sN",
            apiUrl,
            "-H", "Content-Type: application/json",
            "-H", "Authorization: Bearer " + apiKey,
            "-d", body
        ];
        curlProcess.running = true;
    }

    function cancel() {
        if (curlProcess.running) {
            curlProcess.running = false;
        }
    }

    Process {
        id: curlProcess
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (!line.startsWith("data: ")) return;

                let payload = line.substring(6).trim();
                if (payload === "[DONE]") return;

                try {
                    let json = JSON.parse(payload);
                    let delta = json.choices?.[0]?.delta;
                    if (delta?.content) {
                        root._accumulatedResponse += delta.content;
                        root.tokenReceived(delta.content);
                    }
                } catch (e) {
                    // Incomplete JSON chunk — skip
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
            if (exitCode !== 0 && root._accumulatedResponse.length === 0) {
                root.responseError("Request failed (exit code " + exitCode + ")");
            } else {
                root.responseFinished();
            }
        }
    }
}
