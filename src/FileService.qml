import QtQuick
import Quickshell
import Quickshell.Io

// File system service — read/write files scoped to allowed root paths.
// All paths are validated to stay within the configured root.
Item {
    id: root

    property string allowedRoot: "/"  // configurable, default allows everything

    signal operationComplete(string toolCallId, string result)

    // Deferred emit — ensures signal fires after the current call stack returns.
    // Prevents race conditions when the caller sets up async state after calling us.
    property string _deferredCallId: ""
    property string _deferredResult: ""

    function _emitDeferred(toolCallId, result) {
        _deferredCallId = toolCallId;
        _deferredResult = result;
        deferTimer.running = true;
    }

    Timer {
        id: deferTimer
        interval: 0
        running: false
        repeat: false
        onTriggered: root.operationComplete(root._deferredCallId, root._deferredResult)
    }

    // --- Path validation ---
    function _isAllowed(path) {
        // Resolve to absolute, block traversal
        if (path.indexOf("..") >= 0) return false;
        if (!path.startsWith("/")) return false;

        // Normalize: remove trailing slash, double slashes
        let normalized = path.replace(/\/+/g, "/").replace(/\/$/, "");
        let rootNorm = allowedRoot.replace(/\/+/g, "/").replace(/\/$/, "");

        if (rootNorm === "") rootNorm = "/";

        return normalized.indexOf(rootNorm) === 0 || rootNorm === "/";
    }

    // --- Read file ---
    property string _readCallId: ""

    function readFile(path, toolCallId) {
        if (!_isAllowed(path)) {
            root._emitDeferred(toolCallId, "BLOCKED: Path '" + path + "' is outside the allowed root '" + allowedRoot + "'.");
            return;
        }
        _readCallId = toolCallId;
        readProcess.command = ["cat", path];
        readProcess.running = true;
    }

    Process {
        id: readProcess
        running: false
        stdout: StdioCollector { id: readStdout; waitForEnd: true }
        stderr: StdioCollector { id: readStderr; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                let content = readStdout.text;
                if (content.length > 50000) {
                    content = content.substring(0, 25000) +
                        "\n\n[... truncated " + (content.length - 50000) + " chars ...]\n\n" +
                        content.substring(content.length - 25000);
                }
                root.operationComplete(root._readCallId, content.length > 0 ? content : "(empty file)");
            } else {
                root.operationComplete(root._readCallId, "Error reading file: " + readStderr.text.replace(/\s+$/, ""));
            }
        }
    }

    // --- Write file ---
    property string _writeCallId: ""

    function writeFile(path, content, toolCallId) {
        if (!_isAllowed(path)) {
            root._emitDeferred(toolCallId, "BLOCKED: Path '" + path + "' is outside the allowed root '" + allowedRoot + "'.");
            return;
        }
        _writeCallId = toolCallId;
        // Ensure parent directory exists, then write via stdin
        writeProcess.command = [
            "bash", "-c",
            "mkdir -p \"$(dirname '" + path.replace(/'/g, "'\\''") + "')\" && cat > '" + path.replace(/'/g, "'\\''") + "'"
        ];
        writeProcess.stdinEnabled = true;
        writeProcess._content = content;
        writeProcess.running = true;
    }

    Process {
        id: writeProcess
        running: false
        property string _content: ""

        onStarted: {
            writeProcess.write(writeProcess._content);
            writeProcess.stdinEnabled = false;
        }

        stderr: StdioCollector { id: writeStderr; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.operationComplete(root._writeCallId, "File written successfully.");
            } else {
                root.operationComplete(root._writeCallId, "Error writing file: " + writeStderr.text.replace(/\s+$/, ""));
            }
        }
    }

    // --- List directory ---
    property string _listCallId: ""

    function listDirectory(path, toolCallId) {
        if (!_isAllowed(path)) {
            root._emitDeferred(toolCallId, "BLOCKED: Path '" + path + "' is outside the allowed root '" + allowedRoot + "'.");
            return;
        }
        _listCallId = toolCallId;
        listProcess.command = [
            "bash", "-c",
            "ls -la --color=never '" + path.replace(/'/g, "'\\''") + "' 2>&1"
        ];
        listProcess.running = true;
    }

    Process {
        id: listProcess
        running: false
        stdout: StdioCollector { id: listStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            let output = listStdout.text;
            if (output.length > 10000) {
                output = output.substring(0, 10000) + "\n[... truncated]";
            }
            root.operationComplete(root._listCallId, output.length > 0 ? output : "(empty directory)");
        }
    }

    // --- Search files ---
    property string _searchCallId: ""

    function searchFiles(pattern, searchRoot, toolCallId) {
        let searchPath = searchRoot || allowedRoot;
        if (!_isAllowed(searchPath)) {
            root._emitDeferred(toolCallId, "BLOCKED: Path '" + searchPath + "' is outside the allowed root '" + allowedRoot + "'.");
            return;
        }
        _searchCallId = toolCallId;
        searchProcess.command = [
            "bash", "-c",
            "find '" + searchPath.replace(/'/g, "'\\''") + "' -name '" + pattern.replace(/'/g, "'\\''") + "' -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -50"
        ];
        searchProcess.running = true;
    }

    Process {
        id: searchProcess
        running: false
        stdout: StdioCollector { id: searchStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            let output = searchStdout.text.replace(/\s+$/, "");
            root.operationComplete(root._searchCallId, output.length > 0 ? output : "No files found matching the pattern.");
        }
    }
}
