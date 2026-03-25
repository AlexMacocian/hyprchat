import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

FloatingWindow {
    id: window

    visible: false
    implicitWidth: 700
    implicitHeight: 500
    title: "HyprChat"

    // Toggle visibility via Hyprland global shortcut
    GlobalShortcut {
        appid: "hyprchat"
        name: "toggle"
        description: "Toggle HyprChat window"

        onPressed: {
            window.visible = !window.visible;
            if (window.visible) {
                inputBar.focusInput();
            }
        }
    }

    // Grab focus when the window is shown so clicks outside dismiss it
    // TODO: re-enable once toggle keybind is set up
    // HyprlandFocusGrab {
    //     id: focusGrab
    //     active: window.visible
    //     windows: [window]
    //     onCleared: window.visible = false
    // }

    // Message model
    ListModel {
        id: messageModel
    }

    // Active backend
    property string activeBackendName: prefs.activeBackend
    property string activeModel: prefs.activeModel

    // Preferences (persisted to file)
    Preferences {
        id: prefs
    }

    // Model fetcher
    ModelFetcher {
        id: modelFetcher
        backendName: window.activeBackendName
        apiKey: backend.apiKey

        onFetchComplete: {
            backendSwitcher.models = modelFetcher.models;
            backendSwitcher.loadingModels = false;
        }

        onCopilotApiReady: (apiBase, token) => {
            // Use the Copilot internal API for chat completions
            backend.apiUrl = apiBase + "/chat/completions";
            backend.apiKey = token;
        }
    }

    function switchBackend(name) {
        activeBackendName = name;
        prefs.activeBackend = name;
        prefs.save();
        // Re-auth for new backend
        if (name === "copilot") {
            initCopilotAuth();
        } else if (name === "ollama") {
            backend.apiKey = "ollama";
        } else {
            keyring.lookup(name);
        }
        // Fetch models for new backend
        modelFetcher.backendName = name;
        backendSwitcher.loadingModels = true;
        modelFetcher.fetch();
    }

    function switchModel(backend, model) {
        activeModel = model;
        prefs.activeModel = model;
        prefs.save();
    }

    // Backend URL mapping
    readonly property var backendUrls: ({
        "copilot": "https://models.inference.ai.azure.com/chat/completions",
        "openai": "https://api.openai.com/v1/chat/completions",
        "claude": "https://api.anthropic.com/v1/messages",
        "ollama": "http://localhost:11434/api/chat"
    })

    // For Copilot: try keyring for stored OAuth token, otherwise start device flow
    function initCopilotAuth() {
        keyring.lookup("copilot_oauth");
    }

    // Keyring for API key retrieval
    KeyringService {
        id: keyring
        onKeyRetrieved: (account, key) => {
            if (account === "copilot_oauth") {
                // Got OAuth token — exchange for Copilot session token
                window.exchangeCopilotToken(key);
            } else {
                backend.apiKey = key;
                apiKeyPrompt.shown = false;
            }
        }
        onKeyMissing: (account) => {
            if (account === "copilot_oauth") {
                // No OAuth token — start device flow
                window.startGhLogin();
            } else {
                apiKeyPrompt.backendName = account;
                apiKeyPrompt.shown = true;
                apiKeyPrompt.focusInput();
            }
        }
        onKeyError: (account, error) => {
            console.warn("Keyring error:", error);
            if (account === "copilot_oauth") {
                window.startGhLogin();
            } else {
                apiKeyPrompt.backendName = account;
                apiKeyPrompt.shown = true;
                apiKeyPrompt.focusInput();
            }
        }
        onKeyStored: (account) => {
            keyring.lookup(account);
        }
        onKeyDeleted: (account) => {
            backend.apiKey = "";
            apiKeyPrompt.backendName = account;
            apiKeyPrompt.shown = true;
            apiKeyPrompt.focusInput();
        }
    }

    // Exchange Copilot OAuth token for session token + API endpoint
    function exchangeCopilotToken(oauthToken) {
        copilotExchangeProcess.command = [
            "curl", "-s",
            "https://api.github.com/copilot_internal/v2/token",
            "-H", "Authorization: token " + oauthToken,
            "-H", "Accept: application/json"
        ];
        copilotExchangeProcess.running = true;
    }

    Process {
        id: copilotExchangeProcess
        running: false

        stdout: StdioCollector {
            id: exchangeStdout
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("Copilot token exchange failed");
                window.startGhLogin();
                return;
            }

            try {
                let json = JSON.parse(exchangeStdout.text);
                let apiBase = json.endpoints && json.endpoints.api;
                let token = json.token;

                if (apiBase && token) {
                    backend.apiUrl = apiBase + "/chat/completions";
                    backend.apiKey = token;
                    backend.extraHeaders = [
                        "-H", "Editor-Version: vscode/1.105.1",
                        "-H", "Editor-Plugin-Version: copilot-chat/0.26.7",
                        "-H", "Copilot-Integration-Id: vscode-chat",
                        "-H", "User-Agent: GitHubCopilotChat/0.26.7"
                    ];
                    modelFetcher.copilotApiBase = apiBase;
                    modelFetcher.copilotSessionToken = token;
                    apiKeyPrompt.shown = false;
                } else {
                    console.warn("Copilot token response missing endpoints or token");
                    window.startGhLogin();
                }
            } catch (e) {
                console.warn("Copilot token parse error:", e);
                window.startGhLogin();
            }
        }
    }

    // GitHub device login flow
    function startGhLogin() {
        window.visible = true;
        ghLoginFlow.start();
    }

    // LLM backend
    OpenAIBackend {
        id: backend
        model: window.activeModel
        apiUrl: window.backendUrls[window.activeBackendName] || "https://api.openai.com/v1/chat/completions"

        onTokenReceived: (token) => {
            // Update the last assistant message in-place
            let idx = messageModel.count - 1;
            if (idx >= 0 && messageModel.get(idx).role === "assistant") {
                let current = messageModel.get(idx).text;
                if (current === "...") {
                    messageModel.set(idx, { role: "assistant", text: token });
                } else {
                    messageModel.set(idx, { role: "assistant", text: current + token });
                }
            }
        }

        onResponseFinished: {
            // Done streaming
        }

        onResponseError: (error) => {
            let idx = messageModel.count - 1;
            if (idx >= 0 && messageModel.get(idx).role === "assistant") {
                messageModel.set(idx, { role: "assistant", text: "**Error:** " + error });
            }
        }
    }

    // Fetch API key on startup
    Component.onCompleted: {
        if (activeBackendName === "copilot") {
            initCopilotAuth();
        } else if (activeBackendName === "ollama") {
            backend.apiKey = "ollama";
        } else {
            keyring.lookup(activeBackendName);
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg0

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // Top bar
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 36
                color: Theme.bg1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12

                    Text {
                        text: "HyprChat"
                        color: Theme.text
                        font.family: Theme.fontFamily
                        font.pixelSize: Theme.fontSize
                        font.bold: true
                    }

                    Item { Layout.fillWidth: true }

                    // Clickable backend/model label
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: backendLabel.implicitWidth + 16
                        radius: 4
                        color: backendLabelMouse.containsMouse ? Theme.bg2 : "transparent"

                        Text {
                            id: backendLabel
                            anchors.centerIn: parent
                            text: window.activeBackendName + " · " + window.activeModel
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }

                        MouseArea {
                            id: backendLabelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                backendSwitcher.shown = !backendSwitcher.shown;
                                if (backendSwitcher.shown) {
                                    backendSwitcher.currentBackend = window.activeBackendName;
                                    backendSwitcher.currentModel = window.activeModel;
                                    backendSwitcher.loadingModels = true;
                                    modelFetcher.fetch();
                                }
                            }
                        }
                    }
                }
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // Backend/model switcher popup
            BackendSwitcher {
                id: backendSwitcher
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                currentBackend: window.activeBackendName
                currentModel: window.activeModel

                onBackendSelected: (backend) => {
                    window.switchBackend(backend);
                    backendSwitcher.currentBackend = backend;
                }
                onModelSelected: (backend, model) => {
                    window.switchModel(backend, model);
                    backendSwitcher.currentModel = model;
                }
            }

            // API key prompt (shown when key is missing)
            ApiKeyPrompt {
                id: apiKeyPrompt
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight

                onKeySubmitted: (key) => {
                    keyring.store(apiKeyPrompt.backendName, key);
                }
                onCancelled: {
                    apiKeyPrompt.shown = false;
                }
            }

            // GitHub login flow (shown for Copilot when not authenticated)
            GhLoginFlow {
                id: ghLoginFlow
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight

                onAuthCompleted: (oauthToken) => {
                    // Store OAuth token in keyring for future use
                    keyring.store("copilot_oauth", oauthToken);
                    // Exchange for session token
                    window.exchangeCopilotToken(oauthToken);
                }
                onAuthFailed: (error) => {
                    console.warn("GitHub login failed:", error);
                    apiKeyPrompt.backendName = "copilot";
                    apiKeyPrompt.shown = true;
                    apiKeyPrompt.focusInput();
                }
            }

            // Chat messages
            ChatView {
                id: chatView
                Layout.fillWidth: true
                Layout.fillHeight: true
                model: messageModel
            }

            // Separator
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 1
                color: Theme.border
            }

            // Input bar
            InputBar {
                id: inputBar
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight

                onMessageSent: (text) => {
                    if (backend.apiKey.length === 0) {
                        apiKeyPrompt.backendName = window.activeBackendName;
                        apiKeyPrompt.shown = true;
                        apiKeyPrompt.focusInput();
                        return;
                    }
                    messageModel.append({ role: "user", text: text });
                    messageModel.append({ role: "assistant", text: "..." });
                    backend.send(messageModel);
                }
            }
        }
    }

    // Escape to hide
    Shortcut {
        sequence: "Escape"
        onActivated: window.visible = false
    }

    // Ctrl+N for new chat
    Shortcut {
        sequence: "Ctrl+N"
        onActivated: messageModel.clear()
    }
}
