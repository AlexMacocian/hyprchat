import QtQuick
import Quickshell
import Quickshell.Io

// Shell service using kitty remote control.
// Spawns kitty with a shell that has a POSTCMD hook installed.
// The hook touches a signal file after every command completes.
// inotifywait detects this instantly — zero polling, zero visible markers.
Item {
    id: root

    property string shell: Quickshell.env("SHELL") || "/bin/bash"
    property string workingDirectory: Quickshell.env("HOME")
    property bool terminalAlive: terminalProcess.running

    signal execComplete(string toolCallId, string result)

    readonly property string _socketPath: "/tmp/hyprchat-kitty.sock"
    readonly property string _signalFile: "/tmp/hyprchat-done"

    // State
    property var _queue: []
    property string _currentCallId: ""
    property bool _locked: false
    property string _bufferBefore: ""
    property int _spawnFailCount: 0
    readonly property int _maxSpawnRetries: 3

    // --- Setup ---
    Component.onCompleted: {
        setupProcess.command = [
            "bash", "-c",
            "rm -f '" + _signalFile + "' && touch '" + _signalFile + "'"
        ];
        setupProcess.running = true;
    }

    Process {
        id: setupProcess
        running: false
        onExited: {
            _startWatcher();
        }
    }

    // --- inotifywait watcher (runs forever) ---
    function _startWatcher() {
        watchProcess.command = [
            "bash", "-c",
            "while inotifywait -q -e close_write '" + _signalFile + "' 2>/dev/null; do echo DONE; done"
        ];
        watchProcess.running = true;
    }

    Process {
        id: watchProcess
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line.indexOf("DONE") >= 0 && root._locked) {
                    console.log("ShellService: command completed (postcmd hook fired)");
                    captureDelay.running = true;
                }
            }
        }

        onExited: {
            if (root.terminalAlive) {
                root._startWatcher();
            }
        }
    }

    Timer {
        id: captureDelay
        interval: 300
        running: false
        repeat: false
        onTriggered: root._captureResult()
    }

    // --- Spawn terminal with postcmd hook ---
    function _spawnTerminal() {
        if (terminalProcess.running) return;
        if (_spawnFailCount >= _maxSpawnRetries) {
            _failAllQueued("Failed to spawn terminal.");
            return;
        }

        console.log("ShellService: spawning kitty");

        // Build shell init command that installs a postcmd hook
        // The hook touches the signal file after every command — invisible to user
        let initCmd = "";
        if (shell.indexOf("fish") >= 0) {
            // Fish: use --on-event fish_postexec
            initCmd = "function __hyprchat_postcmd --on-event fish_postexec; echo done > '" + _signalFile + "'; end";
        } else if (shell.indexOf("zsh") >= 0) {
            // Zsh: use precmd hook
            initCmd = "precmd() { echo done > '" + _signalFile + "'; }";
        } else {
            // Bash: use PROMPT_COMMAND
            initCmd = "PROMPT_COMMAND='echo done > \"" + _signalFile + "\";'\"${PROMPT_COMMAND}\"";
        }

        // Write a tiny init script
        initProcess.command = [
            "bash", "-c",
            "printf '%s\\n' '" + initCmd.replace(/'/g, "'\\''") + "' > '" + _signalFile + ".init'"
        ];
        initProcess.running = true;
    }

    Process {
        id: initProcess
        running: false
        onExited: {
            // Spawn kitty with the shell, sourcing our init script
            let shellCmd = "";
            if (root.shell.indexOf("fish") >= 0) {
                shellCmd = root.shell + " -C 'source " + root._signalFile + ".init'";
            } else if (root.shell.indexOf("zsh") >= 0) {
                shellCmd = root.shell + " -c 'source " + root._signalFile + ".init; exec " + root.shell + "'";
            } else {
                shellCmd = root.shell + " --rcfile <(cat ~/.bashrc " + root._signalFile + ".init 2>/dev/null)";
            }

            terminalProcess.command = [
                "setsid", "kitty",
                "--class", "hyprchat-shell",
                "--title", "HyprChat Shell",
                "--listen-on", "unix:" + root._socketPath,
                "--override", "allow_remote_control=yes",
                "--directory", root.workingDirectory,
                "-e", "bash", "-c", shellCmd
            ];
            terminalProcess.running = true;
        }
    }

    Process {
        id: terminalProcess
        running: false

        onExited: (exitCode, exitStatus) => {
            console.log("ShellService: terminal closed, code:", exitCode);
            root._spawnFailCount++;

            if (root._locked) {
                root._locked = false;
                root.execComplete(root._currentCallId, "Terminal was closed before command completed.");
            }
            root._failAllQueued("Terminal was closed.");
        }
    }

    // --- Public API ---
    function exec(command, toolCallId) {
        _spawnFailCount = 0;
        _queue.push({ command: command, toolCallId: toolCallId });
        _processQueue();
    }

    function execBackground(command, toolCallId) {
        _spawnFailCount = 0;
        _queue.push({ command: command, toolCallId: toolCallId, background: true });
        _processQueue();
    }

    // --- Queue processing ---
    function _processQueue() {
        if (_locked || _queue.length === 0) return;

        if (!terminalProcess.running) {
            _spawnTerminal();
            spawnRetryTimer.running = true;
            return;
        }

        let item = _queue.shift();
        _currentCallId = item.toolCallId;

        if (item.background) {
            _sendKeys(item.command + "\n");
            root.execComplete(item.toolCallId, "Command sent to terminal in background.");
            _processQueue();
            return;
        }

        _locked = true;

        // Snapshot buffer before command
        _snapshotBefore(item.command);
    }

    Timer {
        id: spawnRetryTimer
        interval: 2000
        running: false
        repeat: false
        onTriggered: root._processQueue()
    }

    // --- Snapshot buffer before ---
    property string _pendingCommand: ""

    function _snapshotBefore(command) {
        _pendingCommand = command;
        beforeProcess.command = [
            "kitty", "@", "--to", "unix:" + _socketPath,
            "get-text", "--extent", "all"
        ];
        beforeProcess.running = true;
    }

    Process {
        id: beforeProcess
        running: false
        stdout: StdioCollector { id: beforeStdout; waitForEnd: true }

        onExited: {
            root._bufferBefore = beforeStdout.text;
            // Send the raw command — no markers, no suffix
            root._sendKeys(root._pendingCommand + "\n");
        }
    }

    // --- Send keystrokes ---
    function _sendKeys(text) {
        sendProcess.command = [
            "kitty", "@", "--to", "unix:" + _socketPath,
            "send-text", "--", text
        ];
        sendProcess.running = true;
    }

    Process { id: sendProcess; running: false }

    // --- Capture result (triggered by postcmd hook) ---
    function _captureResult() {
        captureProcess.command = [
            "kitty", "@", "--to", "unix:" + _socketPath,
            "get-text", "--extent", "all"
        ];
        captureProcess.running = true;
    }

    Process {
        id: captureProcess
        running: false
        stdout: StdioCollector { id: captureStdout; waitForEnd: true }

        onExited: {
            let currentBuffer = captureStdout.text;
            let result = currentBuffer;

            // Diff against before-buffer
            if (root._bufferBefore.length > 0 && result.indexOf(root._bufferBefore) === 0) {
                result = result.substring(root._bufferBefore.length);
            } else {
                let beforeLines = root._bufferBefore.split("\n");
                let currentLines = result.split("\n");
                let startLine = 0;
                for (let i = 0; i < Math.min(beforeLines.length, currentLines.length); i++) {
                    if (beforeLines[i] === currentLines[i]) {
                        startLine = i + 1;
                    } else {
                        break;
                    }
                }
                result = currentLines.slice(startLine).join("\n");
            }

            // Strip ANSI/OSC codes
            result = result.replace(/\x1B\[[0-9;]*[a-zA-Z]/g, "")
                           .replace(/\x1B\][^\x07]*\x07/g, "")
                           .replace(/\x1B\([A-Z]/g, "")
                           .replace(/\r/g, "")
                           .replace(/^\s+|\s+$/g, "");

            // Truncate
            if (result.length > 10000) {
                result = result.substring(0, 5000) +
                    "\n\n[... truncated ...]\n\n" +
                    result.substring(result.length - 5000);
            }

            if (result.length === 0) result = "(no output)";

            console.log("ShellService: captured", result.length, "chars");
            root._locked = false;
            root.execComplete(root._currentCallId, result);
            root._processQueue();
        }
    }

    // --- Helpers ---
    function _failAllQueued(reason) {
        while (_queue.length > 0) {
            let item = _queue.shift();
            root.execComplete(item.toolCallId, reason);
        }
    }

    Component.onDestruction: {
        watchProcess.running = false;
        terminalProcess.running = false;
        cleanupProcess.command = ["bash", "-c", "rm -f '" + _socketPath + "' '" + _signalFile + "' '" + _signalFile + ".init'"];
        cleanupProcess.running = true;
    }

    Process { id: cleanupProcess; running: false }
}
