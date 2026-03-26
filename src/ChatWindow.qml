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

    // Memory service
    MemoryService {
        id: memoryService
        splitThreshold: prefs.memorySplitThreshold
    }

    // Web search service
    WebSearchService {
        id: webSearch

        onSearchComplete: (toolCallId, results) => {
            window._resolveAsyncTool(toolCallId, results);
        }
        onPageComplete: (toolCallId, content) => {
            window._resolveAsyncTool(toolCallId, content);
        }
    }

    // Shell service
    ShellService {
        id: shellService

        onExecComplete: (toolCallId, result) => {
            window._resolveAsyncTool(toolCallId, result);
        }
    }

    // Async tool handling — when a tool is async, we store the pending
    // state and resume when the result arrives
    property var _pendingToolCallMsg: null
    property var _pendingToolResults: []
    property int _pendingToolTotal: 0
    property int _pendingToolDone: 0

    function _resolveAsyncTool(toolCallId, result) {
        // Show result preview in UI
        let preview = result.length > 200 ? result.substring(0, 200) + "..." : result;
        messageModel.append({ role: "system", text: "↩ " + preview, sent: false });

        _pendingToolResults.push({
            role: "tool",
            tool_call_id: toolCallId,
            content: result
        });
        _pendingToolDone++;

        if (_pendingToolDone >= _pendingToolTotal) {
            // All tool results ready — add placeholder and continue
            messageModel.append({ role: "assistant", text: "...", sent: true });
            backend.continueWithToolResults(_pendingToolCallMsg, _pendingToolResults);
            _pendingToolCallMsg = null;
            _pendingToolResults = [];
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
            backend.apiUrl = apiBase + "/chat/completions";
            backend.apiKey = token;
        }

        onTokenExpired: {
            console.log("ChatWindow: Copilot token expired, refreshing...");
            initCopilotAuth();
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
        actualPromptTokens = -1; // reset to heuristic

        // Find maxTokens from the fetched model list
        let models = modelFetcher.models;
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

    // LLM backend
    // Memory tool definitions (OpenAI function calling format)
    readonly property var memoryTools: [
        {
            type: "function",
            function: {
                name: "memory_list_topics",
                description: "List all available memory topics",
                parameters: { type: "object", properties: {}, required: [] }
            }
        },
        {
            type: "function",
            function: {
                name: "memory_read",
                description: "Read the contents of a memory topic",
                parameters: {
                    type: "object",
                    properties: { topic: { type: "string", description: "Topic name" } },
                    required: ["topic"]
                }
            }
        },
        {
            type: "function",
            function: {
                name: "memory_append",
                description: "Append content to a memory topic. Creates the topic if it doesn't exist.",
                parameters: {
                    type: "object",
                    properties: {
                        topic: { type: "string", description: "Topic name (alphanumeric, hyphens, underscores)" },
                        content: { type: "string", description: "Markdown content to append" }
                    },
                    required: ["topic", "content"]
                }
            }
        },
        {
            type: "function",
            function: {
                name: "memory_search",
                description: "Search across all memory topics for a keyword or phrase",
                parameters: {
                    type: "object",
                    properties: { query: { type: "string", description: "Search query" } },
                    required: ["query"]
                }
            }
        },
        {
            type: "function",
            function: {
                name: "memory_reorganize",
                description: "Split a large memory topic into smaller subtopics. Use when a topic exceeds the size threshold. The original topic is deleted and replaced with subtopics under a directory.",
                parameters: {
                    type: "object",
                    properties: {
                        source_topic: { type: "string", description: "The topic to split" },
                        subtopics: {
                            type: "array",
                            description: "Array of new subtopics to create",
                            items: {
                                type: "object",
                                properties: {
                                    name: { type: "string", description: "Subtopic name (will be created as source_topic/name)" },
                                    content: { type: "string", description: "Markdown content for this subtopic" }
                                },
                                required: ["name", "content"]
                            }
                        }
                    },
                    required: ["source_topic", "subtopics"]
                }
            }
        }
    ]

    readonly property var webTools: [
        {
            type: "function",
            function: {
                name: "web_search",
                description: "Search the web using DuckDuckGo. Returns titles, URLs, and snippets for the top results.",
                parameters: {
                    type: "object",
                    properties: { query: { type: "string", description: "Search query" } },
                    required: ["query"]
                }
            }
        },
        {
            type: "function",
            function: {
                name: "web_read_page",
                description: "Fetch and read the text content of a web page URL. Returns cleaned text, truncated to ~8000 chars.",
                parameters: {
                    type: "object",
                    properties: { url: { type: "string", description: "URL to fetch" } },
                    required: ["url"]
                }
            }
        }
    ]

    // Combine active tools based on preferences
    readonly property var shellTools: [
        {
            type: "function",
            function: {
                name: "shell_exec",
                description: "Execute a shell command and return its output (stdout + stderr). Times out after 30s.",
                parameters: {
                    type: "object",
                    properties: { command: { type: "string", description: "The shell command to execute" } },
                    required: ["command"]
                }
            }
        },
        {
            type: "function",
            function: {
                name: "shell_exec_background",
                description: "Execute a shell command in the background without waiting for output. Use for servers or long-running tasks.",
                parameters: {
                    type: "object",
                    properties: { command: { type: "string", description: "The shell command to run in background" } },
                    required: ["command"]
                }
            }
        }
    ]

    // Combine active tools based on preferences
    readonly property var activeTools: {
        let t = [];
        if (prefs.memoryEnabled) t = t.concat(memoryTools);
        if (prefs.webSearchEnabled) t = t.concat(webTools);
        if (prefs.shellEnabled) t = t.concat(shellTools);
        return t;
    }

    // Tool-use loop counter
    property int _toolLoopCount: 0
    readonly property int _maxToolLoops: 10

    OpenAIBackend {
        id: backend
        model: window.activeModel
        apiUrl: window.backendUrls[window.activeBackendName] || "https://api.openai.com/v1/chat/completions"
        contextSummary: window._activeSummary
        systemPrompt: prefs.systemPrompt
        memoryEnabled: prefs.memoryEnabled
        webSearchEnabled: prefs.webSearchEnabled
        shellEnabled: prefs.shellEnabled
        tools: window.activeTools

        onTokenReceived: (token) => {
            let idx = messageModel.count - 1;
            if (idx >= 0 && messageModel.get(idx).role === "assistant") {
                let current = messageModel.get(idx).text;
                if (current === "...") {
                    messageModel.setProperty(idx, "text", token);
                } else {
                    messageModel.setProperty(idx, "text", current + token);
                }
            }
        }

        onToolCallReceived: (toolCalls) => {
            console.log("ChatWindow: received", toolCalls.length, "tool calls");
            window._toolLoopCount++;

            if (window._toolLoopCount > window._maxToolLoops) {
                console.warn("ChatWindow: tool loop limit reached");
                let idx = messageModel.count - 1;
                if (idx >= 0) {
                    messageModel.setProperty(idx, "text", (messageModel.get(idx).text || "") + "\n\n*[Tool loop limit reached]*");
                }
                return;
            }

            // Filter out empty tool calls (streaming artifacts)
            let validCalls = toolCalls.filter(tc => tc.name && tc.name.length > 0);

            // Show tool calls in UI
            for (let i = 0; i < validCalls.length; i++) {
                let tc = validCalls[i];
                let argsPreview = "";
                try {
                    let args = JSON.parse(tc.arguments || "{}");
                    // Show a concise preview of the args
                    if (args.command) argsPreview = "`" + args.command + "`";
                    else if (args.query) argsPreview = "\"" + args.query + "\"";
                    else if (args.topic) argsPreview = args.topic;
                    else if (args.url) argsPreview = args.url;
                } catch(e) {}
                let label = "🔧 **" + tc.name + "**" + (argsPreview.length > 0 ? "  " + argsPreview : "");
                messageModel.append({ role: "system", text: label, sent: false });
            }

            let toolCallMsg = {
                role: "assistant",
                content: null,
                tool_calls: validCalls.map(tc => ({
                    id: tc.id,
                    type: "function",
                    function: { name: tc.name, arguments: tc.arguments }
                }))
            };

            let toolResults = [];
            let asyncCount = 0;

            for (let i = 0; i < toolCalls.length; i++) {
                let tc = toolCalls[i];

                // Skip empty tool calls (streaming accumulation artifacts)
                if (!tc.name || tc.name.length === 0) {
                    console.log("ChatWindow: skipping empty tool call at index", i);
                    continue;
                }

                console.log("ChatWindow: executing tool", tc.name);

                if (tc.name === "web_search" || tc.name === "web_read_page") {
                    // Async tool — will be resolved later
                    asyncCount++;
                    try {
                        let args = JSON.parse(tc.arguments);
                        if (tc.name === "web_search") {
                            webSearch.search(args.query, tc.id);
                        } else {
                            webSearch.fetchPage(args.url, tc.id);
                        }
                    } catch (e) {
                        toolResults.push({ role: "tool", tool_call_id: tc.id, content: "Error: " + e });
                    }
                } else if (tc.name === "shell_exec" || tc.name === "shell_exec_background") {
                    asyncCount++;
                    try {
                        let args = JSON.parse(tc.arguments);
                        if (tc.name === "shell_exec") {
                            shellService.exec(args.command, tc.id);
                        } else {
                            shellService.execBackground(args.command, tc.id);
                        }
                    } catch (e) {
                        toolResults.push({ role: "tool", tool_call_id: tc.id, content: "Error: " + e });
                    }
                } else {
                    // Sync tool (memory)
                    let result = window.executeTool(tc.name, tc.arguments);
                    console.log("ChatWindow: tool", tc.name, "->", result.substring(0, 100));
                    toolResults.push({ role: "tool", tool_call_id: tc.id, content: result });

                    // Show result preview in UI
                    let preview = result.length > 200 ? result.substring(0, 200) + "..." : result;
                    messageModel.append({ role: "system", text: "↩ " + preview, sent: false });
                }
            }

            if (asyncCount > 0) {
                // Store pending state — will resume when async tools complete
                window._pendingToolCallMsg = toolCallMsg;
                window._pendingToolResults = toolResults;
                window._pendingToolTotal = toolResults.length + asyncCount;
                window._pendingToolDone = toolResults.length;
            } else {
                // All sync — add new placeholder and continue
                messageModel.append({ role: "assistant", text: "...", sent: true });
                backend.continueWithToolResults(toolCallMsg, toolResults);
            }
        }

        onResponseFinished: {
            window._toolLoopCount = 0;
            if (!window._summarizing && window.contextUsage >= window.summarizeThreshold) {
                window.performSummarization();
            }
        }

        onUsageReceived: (promptTokens, completionTokens, totalTokens) => {
            if (totalTokens > 0) {
                window.actualPromptTokens = totalTokens;
            }
        }

        onResponseError: (error) => {
            window._toolLoopCount = 0;
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
    }

    // Execute a memory tool and return the result as a string
    function executeTool(name, argsJson) {
        try {
            let args = {};
            if (argsJson && argsJson.length > 0 && argsJson !== "null") {
                try { args = JSON.parse(argsJson); } catch(e) { args = {}; }
            }

            if (name === "memory_list_topics") {
                let topics = memoryService.listTopics();
                if (topics.length === 0) return "No memory topics found.";
                return "Available topics:\n" + topics.join("\n");
            }

            if (name === "memory_read") {
                let content = memoryService.readTopic(args.topic);
                if (content.length === 0) return "Topic '" + args.topic + "' is empty or does not exist.";
                return content;
            }

            if (name === "memory_append") {
                return memoryService.appendTopic(args.topic, args.content);
            }

            if (name === "memory_search") {
                let results = memoryService.search(args.query);
                if (results.length === 0) return "No results for '" + args.query + "'.";
                let out = "";
                for (let i = 0; i < results.length; i++) {
                    out += "### " + results[i].topic + "\n" + results[i].matches + "\n\n";
                }
                return out.trim();
            }

            if (name === "memory_reorganize") {
                if (!args.source_topic || !args.subtopics || !Array.isArray(args.subtopics)) {
                    return "Error: memory_reorganize requires source_topic and subtopics array";
                }
                return memoryService.reorganizeTopic(args.source_topic, args.subtopics);
            }

            return "Unknown tool: " + name;
        } catch (e) {
            return "Tool error: " + e;
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
                        font.pixelSize: Theme.fontSize
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
                                    keyring.remove("copilot_oauth");
                                    backend.apiKey = "";
                                    backend.extraHeaders = [];
                                    modelFetcher.copilotApiBase = "";
                                    modelFetcher.copilotSessionToken = "";
                                    window.startGhLogin();
                                } else if (window.activeBackendName !== "ollama") {
                                    keyring.remove(window.activeBackendName);
                                    backend.apiKey = "";
                                }
                            }
                        }
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
                    backend.send(messageModel);
                }
            }
        }
    }

    // Memory viewer overlay
    MemoryView {
        id: memoryView
        anchors.fill: parent
        memoryService: memoryService
    }

    // Preferences overlay
    PreferencesView {
        id: prefsView
        anchors.fill: parent
        preferences: prefs
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
