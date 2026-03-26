import QtQuick
import Quickshell.Io

// Fetches available models from a backend's API.
// For Copilot: uses the internal Copilot API (same as VS Code / avante.nvim).
Item {
    id: root

    property string backendName: ""
    property string apiUrl: ""
    property string apiKey: ""

    property var models: []
    property bool loading: false

    // Copilot internal state
    property string _copilotApiBase: ""
    property string _copilotToken: ""

    // For Copilot: the caller should set these after token exchange
    property string copilotApiBase: ""
    property string copilotSessionToken: ""

    signal fetchComplete()
    signal copilotApiReady(string apiBase, string token)
    signal tokenExpired()

    // Required headers for Copilot internal API
    readonly property var copilotHeaders: [
        "-H", "Editor-Version: vscode/1.105.1",
        "-H", "Editor-Plugin-Version: copilot-chat/0.26.7",
        "-H", "Copilot-Integration-Id: vscode-chat",
        "-H", "User-Agent: GitHubCopilotChat/0.26.7"
    ]

    function fetch() {
        if (fetchProcess.running || copilotTokenProcess.running) return;

        models = [];
        loading = true;

        if (backendName === "copilot") {
            if (copilotApiBase && copilotSessionToken) {
                // Already have session token — fetch models directly
                fetchProcess.command = [
                    "curl", "-s",
                    copilotApiBase + "/models",
                    "-H", "Authorization: Bearer " + copilotSessionToken,
                    "-H", "Accept: application/json"
                ].concat(copilotHeaders);
                fetchProcess.running = true;
            } else {
                // Need to exchange OAuth token first
                copilotTokenProcess.command = [
                    "curl", "-s",
                    "https://api.github.com/copilot_internal/v2/token",
                    "-H", "Authorization: token " + apiKey,
                    "-H", "Accept: application/json"
                ];
                copilotTokenProcess.running = true;
            }
        } else if (backendName === "ollama") {
            fetchProcess.command = ["curl", "-s", (apiUrl || "http://localhost:11434") + "/api/tags"];
            fetchProcess.running = true;
        } else if (backendName === "openai") {
            fetchProcess.command = [
                "curl", "-s",
                "https://api.openai.com/v1/models",
                "-H", "Authorization: Bearer " + apiKey
            ];
            fetchProcess.running = true;
        } else {
            loading = false;
        }
    }

    // Step 1: Exchange OAuth token for Copilot token
    Process {
        id: copilotTokenProcess
        running: false

        stdout: StdioCollector {
            id: tokenStdout
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                root.loading = false;
                root.fetchComplete();
                return;
            }

            try {
                console.log("ModelFetcher: token response:", tokenStdout.text.substring(0, 200));
                let json = JSON.parse(tokenStdout.text);
                root._copilotToken = json.token || "";
                root._copilotApiBase = (json.endpoints && json.endpoints.api) || "";

                if (root._copilotToken && root._copilotApiBase) {
                    // Emit the API details so ChatWindow can use them
                    root.copilotApiReady(root._copilotApiBase, root._copilotToken);

                    // Step 2: Fetch models from the Copilot API
                    fetchProcess.command = [
                        "curl", "-s",
                        root._copilotApiBase + "/models",
                        "-H", "Authorization: Bearer " + root._copilotToken,
                        "-H", "Accept: application/json"
                    ].concat(root.copilotHeaders);
                    fetchProcess.running = true;
                } else {
                    console.warn("ModelFetcher: Copilot token response missing endpoints");
                    root.loading = false;
                    root.fetchComplete();
                }
            } catch (e) {
                console.warn("ModelFetcher: Failed to parse Copilot token:", e);
                root.loading = false;
                root.fetchComplete();
            }
        }
    }

    // Step 2 (Copilot) or direct fetch (other backends): Get model list
    Process {
        id: fetchProcess
        running: false

        stdout: StdioCollector {
            id: fetchStdout
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            root.loading = false;
            if (exitCode !== 0) {
                root.fetchComplete();
                return;
            }

            let text = fetchStdout.text.trim();
            console.log("ModelFetcher: models response (", text.length, "chars):", text.substring(0, 300));

            // Check for expired token
            if (text.indexOf("expired") >= 0 || text.indexOf("unauthorized") >= 0 || text.indexOf("Incorrect API key") >= 0) {
                console.log("ModelFetcher: token expired, requesting refresh");
                root.tokenExpired();
                root.fetchComplete();
                return;
            }

            try {
                if (root.backendName === "copilot") {
                    root.parseCopilotModels(text);
                } else if (root.backendName === "ollama") {
                    root.parseOllamaModels(text);
                } else if (root.backendName === "openai") {
                    root.parseOpenAIModels(text);
                }
            } catch (e) {
                console.warn("ModelFetcher: parse error:", e);
            }
            root.fetchComplete();
        }
    }

    function parseCopilotModels(text) {
        let json = JSON.parse(text);
        if (json.data && Array.isArray(json.data)) {
            let chatModels = json.data
                .filter(m => m.capabilities && m.capabilities.type === "chat")
                .filter(m => !m.id.endsWith("-paygo"))
                .sort((a, b) => (a.name || a.id).localeCompare(b.name || b.id));

            // Detect duplicate names and disambiguate with id
            let nameCounts = {};
            for (let i = 0; i < chatModels.length; i++) {
                let n = chatModels[i].name || chatModels[i].id;
                nameCounts[n] = (nameCounts[n] || 0) + 1;
            }

            models = chatModels.map(m => {
                let displayName = m.name || m.id;
                if (nameCounts[displayName] > 1) {
                    displayName = displayName + " (" + m.id + ")";
                }
                let maxTokens = 128000; // default
                if (m.capabilities && m.capabilities.limits && m.capabilities.limits.max_prompt_tokens) {
                    maxTokens = m.capabilities.limits.max_prompt_tokens;
                }
                return { id: m.id, name: displayName, maxTokens: maxTokens };
            });
        }
    }

    function parseOllamaModels(text) {
        let json = JSON.parse(text);
        if (json.models && Array.isArray(json.models)) {
            models = json.models.map(m => ({ id: m.name, name: m.name }));
        }
    }

    function parseOpenAIModels(text) {
        let json = JSON.parse(text);
        if (json.data && Array.isArray(json.data)) {
            let chatModels = json.data
                .filter(m => m.id.indexOf("gpt") >= 0 || m.id.indexOf("o1") >= 0 || m.id.indexOf("o3") >= 0)
                .sort((a, b) => a.id.localeCompare(b.id));
            models = chatModels.map(m => ({ id: m.id, name: m.id }));
        }
    }
}
