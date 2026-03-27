import QtQuick
import Quickshell
import Quickshell.Io

// Manages the NativeAOT backend process via stdin/stdout JSON-RPC.
// The backend handles: LLM streaming, tool execution loop, memory,
// file access, web search, shell, date tools, model fetching, keyring.
Item {
    id: root

    // Configuration — resolve backend binary path
    // Priority: HYPRCHAT_BACKEND env > sibling Publish/ folder (dev) > system install
    property string backendPath: {
        let envPath = Quickshell.env("HYPRCHAT_BACKEND");
        if (envPath && envPath.length > 0) return envPath;

        // Use the QML file's own location to find the sibling backend
        // Qt.resolvedUrl(".") gives us file:///path/to/src/hyprchat-ui/
        let qmlDir = Qt.resolvedUrl(".").toString();
        // Strip file:// prefix and trailing slash
        if (qmlDir.startsWith("file://")) qmlDir = qmlDir.substring(7);
        if (qmlDir.endsWith("/")) qmlDir = qmlDir.substring(0, qmlDir.length - 1);

        if (qmlDir.indexOf("/hyprchat-ui") >= 0) {
            let srcDir = qmlDir.substring(0, qmlDir.lastIndexOf("/hyprchat-ui"));
            return srcDir + "/hyprchat-backend/Publish/HyprChat.Backend";
        }

        // System install path (AUR package)
        return "/usr/lib/hyprchat/HyprChat.Backend";
    }

    Component.onCompleted: {
        backendProcess.running = true;
    }

    property bool ready: false
    property bool streaming: false
    property string apiKey: ""
    property string apiUrl: ""
    property var extraHeaders: []
    property int _nextId: 1

    // Pending RPC calls: { id: { resolve, reject } }
    property var _pending: ({})

    // Signals for ChatWindow
    signal tokenReceived(string token)
    signal toolCallNotified(string name, string args)
    signal toolResultNotified(string name, string preview)
    signal usageReceived(int promptTokens, int completionTokens, int totalTokens)
    signal responseFinished()
    signal responseError(string error)
    signal tokenExpired()

    // Model fetcher signals
    signal modelsFetched(var models)
    signal copilotApiReady(string apiBase, string token)
    signal modelsTokenExpired()

    // Keyring signals
    signal keyRetrieved(string account, string key)
    signal keyMissing(string account)
    signal keyStored(string account)
    signal keyDeleted(string account)

    // Memory signals (for MemoryView)
    signal memoryTopicsListed(var topics)
    signal memoryTopicRead(string topic, string content)

    Process {
        id: backendProcess
        command: [root.backendPath]
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line.trim().length === 0) return;
                try {
                    let msg = JSON.parse(line);
                    root._handleMessage(msg);
                } catch (e) {
                    console.warn("BackendProcess: failed to parse:", line.substring(0, 200), e);
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
            console.warn("BackendProcess: exited with code", exitCode);
            root.ready = false;
        }
    }

    // --- JSON-RPC send ---

    function _send(method, params, callback) {
        if (!backendProcess.running) {
            console.warn("BackendProcess: not running, can't send", method);
            return;
        }

        let id = null;
        if (callback) {
            id = _nextId++;
            _pending[id] = callback;
        }

        let msg = { jsonrpc: "2.0", method: method };
        if (id !== null) msg.id = id;
        if (params !== undefined && params !== null) msg.params = params;

        let json = JSON.stringify(msg) + "\n";
        backendProcess.write(json);
    }

    // Fire-and-forget notification (no response expected)
    function _notify(method, params) {
        _send(method, params, null);
    }

    // --- Message handler ---

    function _handleMessage(msg) {
        // Response to a request
        if (msg.id !== undefined && msg.id !== null) {
            let cb = _pending[msg.id];
            if (cb) {
                delete _pending[msg.id];
                if (msg.error) {
                    console.warn("RPC error:", msg.error.message);
                } else {
                    cb(msg.result);
                }
            }
            return;
        }

        // Notification
        let method = msg.method || "";
        let params = msg.params || {};

        if (method === "ready") {
            root.ready = true;
            console.log("BackendProcess: ready");
        }
        // Chat notifications
        else if (method === "chat/token") {
            root.tokenReceived(params.token || "");
        }
        else if (method === "chat/toolCall") {
            root.toolCallNotified(params.name || "", params.args || "");
        }
        else if (method === "chat/toolResult") {
            root.toolResultNotified(params.name || "", params.preview || "");
        }
        else if (method === "chat/usage") {
            root.usageReceived(params.promptTokens || 0, params.completionTokens || 0, params.totalTokens || 0);
        }
        else if (method === "chat/finished") {
            root.streaming = false;
            root.responseFinished();
        }
        else if (method === "chat/error") {
            root.streaming = false;
            root.responseError(params.error || "Unknown error");
        }
        else if (method === "chat/tokenExpired") {
            root.tokenExpired();
        }
        // Model notifications
        else if (method === "models/copilotApiReady") {
            root.copilotApiReady(params.apiBase || "", params.token || "");
        }
        else if (method === "models/tokenExpired") {
            root.modelsTokenExpired();
        }
    }

    // --- Public API ---

    function send(messageModel, params) {
        if (streaming) return;
        streaming = true;

        // Build messages array from the ListModel
        let messages = [];
        for (let i = 0; i < messageModel.count; i++) {
            let msg = messageModel.get(i);
            if (msg.text === "..." || msg.role === "system") continue;
            if (msg.sent === false) continue;
            messages.push({ role: msg.role, content: msg.text });
        }

        _send("chat/send", {
            messages: messages,
            backend: params.backend,
            model: params.model,
            apiUrl: root.apiUrl,
            apiKey: root.apiKey,
            systemPrompt: params.systemPrompt,
            contextSummary: params.contextSummary || "",
            extraHeaders: root.extraHeaders,
            memoryEnabled: params.memoryEnabled,
            webSearchEnabled: params.webSearchEnabled,
            shellEnabled: params.shellEnabled,
            fileAccessEnabled: params.fileAccessEnabled,
            dateEnabled: params.dateEnabled,
            fileAccessRoot: params.fileAccessRoot || "/",
            memorySplitThreshold: params.memorySplitThreshold || 200
        }, function(result) {
            // chat/send response comes after the entire stream+tool loop is done
        });
    }

    function cancel() {
        _send("chat/cancel", {}, function(result) {
            root.streaming = false;
        });
    }

    // --- Model fetching ---

    function fetchModels(backend, apiKey, apiUrl) {
        _send("models/fetch", {
            backend: backend,
            apiKey: apiKey,
            apiUrl: apiUrl || ""
        }, function(result) {
            root.modelsFetched(result.models || []);
        });
    }

    // --- Keyring ---

    function keyringLookup(account) {
        _send("keyring/lookup", { account: account }, function(result) {
            if (result.found) {
                root.keyRetrieved(result.account, result.key);
            } else {
                root.keyMissing(result.account);
            }
        });
    }

    function keyringStore(account, key) {
        _send("keyring/store", { account: account, key: key }, function(result) {
            root.keyStored(account);
        });
    }

    function keyringDelete(account) {
        _send("keyring/delete", { account: account }, function(result) {
            root.keyDeleted(account);
        });
    }

    // --- Memory (for MemoryView UI) ---

    function memoryList(callback) {
        _send("memory/list", {}, function(result) {
            if (callback) callback(result.topics || []);
        });
    }

    function memoryRead(topic, callback) {
        _send("memory/read", { topic: topic }, function(result) {
            if (callback) callback(result.content || "");
        });
    }

    function memoryEdit(topic, content) {
        _send("memory/edit", { topic: topic, content: content }, null);
    }

    function memoryDelete(topic) {
        _send("memory/delete", { topic: topic }, null);
    }

    Component.onDestruction: {
        backendProcess.running = false;
    }
}
