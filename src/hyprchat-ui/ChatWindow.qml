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

    // NativeAOT backend process — handles LLM streaming, tools, keyring, models
    BackendProcess {
        id: backend

        onTokenReceived: (token) => {
            let idx = messageModel.count - 1;
            // Ensure we have an assistant message to append to
            if (idx < 0 || messageModel.get(idx).role !== "assistant") {
                messageModel.append({ role: "assistant", text: "", sent: true });
                idx = messageModel.count - 1;
            }
            let current = messageModel.get(idx).text;
            if (current === "...") {
                messageModel.setProperty(idx, "text", token);
            } else {
                messageModel.setProperty(idx, "text", current + token);
            }
        }

        onToolCallNotified: (name, args) => {
            let argsPreview = "";
            try {
                let a = JSON.parse(args || "{}");
                if (a.command) argsPreview = "`" + a.command + "`";
                else if (a.query) argsPreview = '"' + a.query + '"';
                else if (a.topic) argsPreview = a.topic;
                else if (a.url) argsPreview = a.url;
            } catch(e) {}
            let label = "🔧 **" + name + "**" + (argsPreview.length > 0 ? "  " + argsPreview : "");
            messageModel.append({ role: "system", text: label, sent: false });
        }

        onToolResultNotified: (name, preview) => {
            messageModel.append({ role: "system", text: "↩ " + preview, sent: false });
        }

        onUsageReceived: (promptTokens, completionTokens, totalTokens) => {
            if (totalTokens > 0) {
                window.actualPromptTokens = totalTokens;
            }
        }

        onResponseFinished: {
            if (!window._summarizing && window.contextUsage >= window.summarizeThreshold) {
                window.performSummarization();
            }
        }

        onResponseError: (error) => {
            let idx = messageModel.count - 1;
            if (idx >= 0 && messageModel.get(idx).role === "assistant") {
                messageModel.set(idx, { role: "assistant", text: "**Error:** " + error, sent: true });
            }
        }

        onTokenExpired: {
            console.log("ChatWindow: backend token expired, refreshing...");
            if (window.activeBackendName === "copilot") {
                initCopilotAuth();
            }
        }

        onCopilotApiReady: (apiBase, token) => {
            backend.apiUrl = apiBase + "/chat/completions";
            backend.apiKey = token;
        }

        onModelsTokenExpired: {
            console.log("ChatWindow: models token expired, refreshing...");
            initCopilotAuth();
        }

        onModelsFetched: (models) => {
            backendSwitcher.models = models;
            backendSwitcher.loadingModels = false;
            window._fetchedModels = models;
        }

        onKeyRetrieved: (account, key) => {
            if (account === "copilot_oauth") {
                window.exchangeCopilotToken(key);
            } else if (account === "copilot_refresh") {
                window._refreshingToken = false;
                window.doCopilotRefresh(key);
            } else {
                backend.apiKey = key;
                apiKeyPrompt.shown = false;
            }
        }
        onKeyMissing: (account) => {
            if (account === "copilot_oauth") {
                window.startGhLogin();
            } else if (account === "copilot_refresh") {
                window._refreshingToken = false;
                console.log("ChatWindow: no refresh token found, starting login");
                window.startGhLogin();
            } else {
                apiKeyPrompt.backendName = account;
                apiKeyPrompt.shown = true;
                apiKeyPrompt.focusInput();
            }
        }
        onKeyStored: (account) => {
            if (account !== "copilot_refresh") {
                backend.keyringLookup(account);
            }
        }
        onKeyDeleted: (account) => {
            if (account === "copilot_refresh") return;
            backend.apiKey = "";
            apiKeyPrompt.backendName = account;
            apiKeyPrompt.shown = true;
            apiKeyPrompt.focusInput();
        }
    }

    // Active backend
    property string activeBackendName: prefs.activeBackend
    property string activeModel: prefs.activeModel

    // Context window tracking
    property int maxContextTokens: 128000
    property int actualPromptTokens: -1  // -1 means no actual data yet
    property int estimatedTokens: {
        let chars = 0;
        for (let i = 0; i < messageModel.count; i++) {
            chars += messageModel.get(i).text.length;
        }
        return Math.ceil(chars / 3.5); // ~3.5 chars per token heuristic
    }
    property int displayTokens: actualPromptTokens >= 0 ? actualPromptTokens : estimatedTokens
    property real contextUsage: maxContextTokens > 0 ? Math.min(displayTokens / maxContextTokens, 1.0) : 0
    property bool _summarizing: false
    readonly property real summarizeThreshold: prefs.summarizeThreshold
    readonly property int keepRecentMessages: prefs.keepRecentMessages
    property string _activeSummary: ""

    // Preferences (persisted to file)
    Preferences {
        id: prefs
    }

    // Models list for switchModel
    property var _fetchedModels: []

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
            backend.keyringLookup(name);
        }
        // Fetch models for new backend
        backendSwitcher.loadingModels = true;
        backend.fetchModels(name, backend.apiKey, "");
    }

    function switchModel(b, model) {
        activeModel = model;
        prefs.activeModel = model;
        prefs.save();
        actualPromptTokens = -1; // reset to heuristic

        // Find maxTokens from the fetched model list
        let models = window._fetchedModels;
        for (let i = 0; i < models.length; i++) {
            if (models[i].id === model && models[i].maxTokens) {
                maxContextTokens = models[i].maxTokens;
                break;
            }
        }
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
        backend.keyringLookup("copilot_oauth");
    }

    // Try refreshing the OAuth token using stored refresh token
    property bool _refreshingToken: false
    function refreshCopilotToken() {
        console.log("ChatWindow: attempting OAuth token refresh...");
        _refreshingToken = true;
        backend.keyringLookup("copilot_refresh");
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
                window.refreshCopilotToken();
                return;
            }

            try {
                let json = JSON.parse(exchangeStdout.text);
                let apiBase = json.endpoints && json.endpoints.api;
                let token = json.token;

                if (apiBase && token) {
                    backend.apiUrl = apiBase + "/chat/completions";
                    backend.apiKey = token;
                    backend.copilotApiBase = apiBase;
                    backend.extraHeaders = [
                        "Editor-Version: vscode/1.105.1",
                        "Editor-Plugin-Version: copilot-chat/0.26.7",
                        "Copilot-Integration-Id: vscode-chat",
                        "User-Agent: GitHubCopilotChat/0.26.7"
                    ];
                    apiKeyPrompt.shown = false;
                    // Fetch models now that we have the session token
                    backend.fetchModels("copilot", token, "");
                } else {
                    console.warn("Copilot token response missing endpoints or token");
                    window.refreshCopilotToken();
                }
            } catch (e) {
                console.warn("Copilot token parse error:", e);
                window.refreshCopilotToken();
            }
        }
    }

    // Exchange refresh token for new OAuth + refresh tokens
    function doCopilotRefresh(refreshToken) {
        copilotRefreshProcess.command = [
            "curl", "-s", "-X", "POST",
            "https://github.com/login/oauth/access_token",
            "-H", "Accept: application/json",
            "-d", "client_id=Iv1.b507a08c87ecfe98"
                + "&grant_type=refresh_token"
                + "&refresh_token=" + refreshToken
        ];
        copilotRefreshProcess.running = true;
    }

    Process {
        id: copilotRefreshProcess
        running: false

        stdout: StdioCollector {
            id: refreshStdout
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("ChatWindow: refresh token exchange failed");
                window.startGhLogin();
                return;
            }

            try {
                let json = JSON.parse(refreshStdout.text);

                if (json.access_token) {
                    console.log("ChatWindow: OAuth token refreshed successfully");
                    // Store new OAuth token
                    backend.keyringStore("copilot_oauth", json.access_token);
                    // Store new refresh token if provided
                    if (json.refresh_token) {
                        backend.keyringStore("copilot_refresh", json.refresh_token);
                    }
                    // Exchange for session token
                    window.exchangeCopilotToken(json.access_token);
                } else {
                    console.warn("ChatWindow: refresh response had no access_token:", json.error || "");
                    window.startGhLogin();
                }
            } catch (e) {
                console.warn("ChatWindow: refresh parse error:", e);
                window.startGhLogin();
            }
        }
    }

    // GitHub device login flow
    function startGhLogin() {
        window.visible = true;
        ghLoginFlow.start();
    }

    // --- Context Summarization ---
    // TODO: When Memory MCP is available, the summarization prompt should
    // instruct the model to save key facts to memory before summarizing,
    // and include memory file references in the summary.

    readonly property string summarizePrompt: "You are summarizing this conversation because it is approaching the context limit. " +
        "Write a concise summary that includes: what topics were discussed, key decisions or conclusions, " +
        "and the current state of any ongoing tasks. Be thorough but compact. " +
        "The user should be able to continue the conversation naturally after this summary."

    function performSummarization() {
        if (_summarizing || messageModel.count < 4) return;
        _summarizing = true;
        console.log("ChatWindow: starting summarization, usage:", (contextUsage * 100).toFixed(1) + "%");

        // Build messages for the summarization request
        let msgs = [{ role: "system", content: summarizePrompt }];
        for (let i = 0; i < messageModel.count; i++) {
            let msg = messageModel.get(i);
            if (msg.text === "...") continue;
            msgs.push({ role: msg.role, content: msg.text });
        }
        msgs.push({ role: "user", content: "Please summarize this conversation now." });

        let body = JSON.stringify({
            model: activeModel,
            messages: msgs,
            stream: false
        });

        // Write body to temp file and call curl
        summaryWriteProcess.command = ["bash", "-c", "cat > /tmp/hyprchat-summary.json"];
        summaryWriteProcess.stdinEnabled = true;
        window._summaryBody = body;
        summaryWriteProcess.running = true;
    }

    property string _summaryBody: ""

    Process {
        id: summaryWriteProcess
        running: false

        onStarted: {
            summaryWriteProcess.write(window._summaryBody);
            summaryWriteProcess.stdinEnabled = false;
        }

        onExited: (exitCode, exitStatus) => {
            summaryCurlProcess.command = [
                "curl", "-s",
                backend.apiUrl,
                "-H", "Content-Type: application/json",
                "-H", "Authorization: Bearer " + backend.apiKey,
                "-d", "@/tmp/hyprchat-summary.json"
            ].concat(backend.extraHeaders);
            summaryCurlProcess.running = true;
        }
    }

    Process {
        id: summaryCurlProcess
        running: false

        stdout: StdioCollector {
            id: summaryStdout
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            window._summarizing = false;

            if (exitCode !== 0) {
                console.warn("ChatWindow: summarization request failed");
                return;
            }

            try {
                let json = JSON.parse(summaryStdout.text);
                let summary = "";
                if (json.choices && json.choices[0] && json.choices[0].message) {
                    summary = json.choices[0].message.content;
                }

                if (summary.length === 0) {
                    console.warn("ChatWindow: empty summary response");
                    return;
                }

                console.log("ChatWindow: summarization complete,", summary.length, "chars");

                // Store the summary — will be injected as system context
                window._activeSummary = summary;

                // Mark old messages as not sent, keep last N as sent
                let boundary = Math.max(0, messageModel.count - window.keepRecentMessages);
                for (let i = 0; i < boundary; i++) {
                    messageModel.setProperty(i, "sent", false);
                }

                // Insert a visual divider
                messageModel.insert(boundary, { role: "system", text: "--- Messages above have been summarized ---", sent: false });

                window.actualPromptTokens = -1; // reset to heuristic
            } catch (e) {
                console.warn("ChatWindow: summarization parse error:", e);
            }
        }
    }

    // Fetch API key once backend is ready
    function _initAuth() {
        if (activeBackendName === "copilot") {
            initCopilotAuth();
        } else if (activeBackendName === "ollama") {
            backend.apiKey = "ollama";
        } else {
            backend.keyringLookup(activeBackendName);
        }
    }

    Connections {
        target: backend
        function onReadyChanged() {
            if (backend.ready) window._initAuth();
        }
    }

    Component.onCompleted: {
        if (backend.ready) _initAuth();
    }

    Rectangle {
        anchors.fill: parent
        color: Theme.bg0

        ColumnLayout {
            anchors.fill: parent
            anchors.bottomMargin: 4
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
                        font.pixelSize: Theme.fontSize + 2
                        font.bold: true
                    }

                    // New chat button
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: newChatLabel.implicitWidth + 12
                        radius: 4
                        color: newChatMouse.containsMouse ? Theme.bg3 : "transparent"

                        Text {
                            id: newChatLabel
                            anchors.centerIn: parent
                            text: "New Chat"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: newChatMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: { messageModel.clear(); window.actualPromptTokens = -1; window._activeSummary = ""; }
                        }
                    }

                    // Sign out button
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: memoryLabel.implicitWidth + 12
                        radius: 4
                        color: memoryMouse.containsMouse ? Theme.bg3 : "transparent"

                        Text {
                            id: memoryLabel
                            anchors.centerIn: parent
                            text: "Memory"
                            color: memoryView.shown ? Theme.accent1 : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: memoryMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                memoryView.shown = !memoryView.shown;
                                prefsView.shown = false;
                            }
                        }
                    }

                    // Preferences button
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: prefsLabel.implicitWidth + 12
                        radius: 4
                        color: prefsMouse.containsMouse ? Theme.bg3 : "transparent"

                        Text {
                            id: prefsLabel
                            anchors.centerIn: parent
                            text: "Prefs"
                            color: prefsView.shown ? Theme.accent1 : Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: prefsMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                prefsView.shown = !prefsView.shown;
                                memoryView.shown = false;
                            }
                        }
                    }

                    // Sign out button
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: signOutLabel.implicitWidth + 12
                        radius: 4
                        color: signOutMouse.containsMouse ? Theme.bg3 : "transparent"

                        Text {
                            id: signOutLabel
                            anchors.centerIn: parent
                            text: "Sign Out"
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 2
                        }

                        MouseArea {
                            id: signOutMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                if (window.activeBackendName === "copilot") {
                                    backend.keyringDelete("copilot_oauth");
                                    backend.keyringDelete("copilot_refresh");
                                    backend.apiKey = "";
                                    backend.extraHeaders = [];
                                    window.startGhLogin();
                                } else if (window.activeBackendName !== "ollama") {
                                    backend.keyringDelete(window.activeBackendName);
                                    backend.apiKey = "";
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Profile switcher label
                    Rectangle {
                        Layout.preferredHeight: 24
                        Layout.preferredWidth: profileLabel.implicitWidth + 16
                        radius: 4
                        color: profileLabelMouse.containsMouse ? Theme.bg2 : "transparent"

                        Text {
                            id: profileLabel
                            anchors.centerIn: parent
                            text: {
                                let p = prefs.activeProfile;
                                return (p.icon || "🤖") + " " + p.name;
                            }
                            color: Theme.textDim
                            font.family: Theme.fontFamily
                            font.pixelSize: Theme.fontSize - 1
                        }

                        MouseArea {
                            id: profileLabelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                profileSwitcher.shown = !profileSwitcher.shown;
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

            // Profile switcher popup
            ProfileSwitcher {
                id: profileSwitcher
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight
                profiles: prefs.profiles
                activeProfileName: prefs.activeProfileName

                onProfileSelected: (name) => {
                    let oldBackend = window.activeBackendName;
                    prefs.switchProfile(name);
                    // Clear chat on profile switch
                    messageModel.clear();
                    window.actualPromptTokens = -1;
                    window._activeSummary = "";
                    // Re-auth if backend changed
                    if (prefs.activeBackend !== oldBackend) {
                        if (prefs.activeBackend === "copilot") {
                            initCopilotAuth();
                        } else if (prefs.activeBackend === "ollama") {
                            backend.apiKey = "ollama";
                        } else {
                            backend.keyringLookup(prefs.activeBackend);
                        }
                    }
                }
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
                    backend.keyringStore(apiKeyPrompt.backendName, key);
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

                onAuthCompleted: (oauthToken, refreshToken) => {
                    // Store OAuth token in keyring for future use
                    backend.keyringStore("copilot_oauth", oauthToken);
                    // Store refresh token if provided
                    if (refreshToken && refreshToken.length > 0) {
                        backend.keyringStore("copilot_refresh", refreshToken);
                    }
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

            // Context gauge
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 14
                Layout.leftMargin: 8
                Layout.rightMargin: 8

                // Background track
                Rectangle {
                    id: gaugeTrack
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    height: 3
                    radius: 1.5
                    color: Theme.bg2

                    // Fill bar
                    Rectangle {
                        width: parent.width * window.contextUsage
                        height: parent.height
                        radius: parent.radius
                        color: Theme.accent1

                        Behavior on width {
                            NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                        }
                    }

                    // Threshold marker
                    Rectangle {
                        x: gaugeTrack.width * window.summarizeThreshold - 1
                        anchors.verticalCenter: parent.verticalCenter
                        width: 2
                        height: 7
                        radius: 1
                        color: Theme.textDim
                    }
                }

                // Label
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        let tokens = window.displayTokens;
                        let max = window.maxContextTokens;
                        let prefix = window.actualPromptTokens >= 0 ? "" : "~";
                        if (tokens < 1000) return prefix + tokens + " / " + Math.round(max / 1000) + "k";
                        return prefix + (tokens / 1000).toFixed(1) + "k / " + Math.round(max / 1000) + "k";
                    }
                    color: Theme.textDim
                    font.family: Theme.fontFamily
                    font.pixelSize: Theme.fontSize - 3
                }
            }

            // Input bar
            InputBar {
                id: inputBar
                Layout.fillWidth: true
                Layout.minimumHeight: 48
                Layout.preferredHeight: implicitHeight
                Layout.bottomMargin: 4
                enabled: !backend.streaming && !window._summarizing
                streaming: backend.streaming

                onStopRequested: {
                    backend.cancel();
                }

                onMessageSent: (text) => {
                    if (backend.apiKey.length === 0) {
                        apiKeyPrompt.backendName = window.activeBackendName;
                        apiKeyPrompt.shown = true;
                        apiKeyPrompt.focusInput();
                        return;
                    }
                    messageModel.append({ role: "user", text: text, sent: true });
                    messageModel.append({ role: "assistant", text: "...", sent: true });
                    backend.send(messageModel, {
                        backend: window.activeBackendName,
                        model: window.activeModel,
                        systemPrompt: prefs.systemPrompt,
                        contextSummary: window._activeSummary,
                        memoryEnabled: prefs.memoryEnabled,
                        webSearchEnabled: prefs.webSearchEnabled,
                        shellEnabled: prefs.shellEnabled,
                        fileAccessEnabled: prefs.fileAccessEnabled,
                        dateEnabled: prefs.dateEnabled,
                        fileAccessRoot: prefs.fileAccessRoot,
                        memorySplitThreshold: prefs.memorySplitThreshold
                    });
                }
            }
        }
    }

    // Memory viewer overlay
    MemoryView {
        id: memoryView
        anchors.fill: parent
        backendProcess: backend
    }

    // Preferences overlay
    PreferencesView {
        id: prefsView
        anchors.fill: parent
        preferences: prefs
        backendProcess: backend
    }

    // Escape to hide
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (prefsView.shown) {
                prefsView.shown = false;
            } else if (memoryView.shown) {
                memoryView.shown = false;
            } else {
                window.visible = false;
            }
        }
    }

    // Ctrl+N for new chat
    Shortcut {
        sequence: "Ctrl+N"
        onActivated: { messageModel.clear(); window.actualPromptTokens = -1; window._activeSummary = ""; }
    }
}
