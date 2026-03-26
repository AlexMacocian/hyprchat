import QtQuick
import Quickshell
import Quickshell.Io

// Shell service using kitty remote control.
// Spawns a kitty terminal with --listen-on, sends commands via `kitty @`,
// reads output via `kitty @ get-text`. No FIFO, no script, no markers.
Item {
    id: root

    property int timeout: 30
    property string shell: Quickshell.env("SHELL") || "/bin/bash"
    property string workingDirectory: Quickshell.env("HOME")
    property bool terminalAlive: terminalProcess.running

    signal execComplete(string toolCallId, string result)

    // Kitty socket for remote control
    readonly property string _socketPath: "/tmp/hyprchat-kitty-" + Qt.application.pid + ".sock"

    // State
    property var _queue: []
    property string _currentCallId: ""
    property bool _locked: false
    property string _bufferBefore: ""
    property int _pollCount: 0
    property string _lastBuffer: ""
    property int _stableCount: 0
    property int _spawnFailCount: 0
    readonly property int _maxSpawnRetries: 3
    readonly property int _stableThreshold: 3  // 1.5s of no change
    readonly property int _maxPolls: 120       // 60s

    // --- Spawn terminal ---
    function _spawnTerminal() {
        if (terminalProcess.running) return;
        if (_spawnFailCount >= _maxSpawnRetries) {
            console.warn("ShellService: too many spawn failures");
            _failAllQueued("Failed to spawn terminal.");
            return;
        }

        console.log("ShellService: spawning kitty with remote control");
        terminalProcess.command = [
            "setsid", "kitty",
            "--class", "hyprchat-shell",
            "--title", "HyprChat Shell",
            "--listen-on", "unix:" + _socketPath,
            "--override", "allow_remote_control=yes",
            "--directory", workingDirectory,
            "-e", shell
        ];
        terminalProcess.running = true;
    }

    Process {
        id: terminalProcess
        running: false

        onExited: (exitCode, exitStatus) => {
            console.log("ShellService: terminal closed, code:", exitCode);
            root._spawnFailCount++;

            if (root._locked) {
                pollTimer.running = false;
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
            _sendCommand(item.command);
            root.execComplete(item.toolCallId, "Command sent to terminal in background.");
            _processQueue();
            return;
        }

        // Lock and capture
        _locked = true;

        // Step 1: Get current buffer (before command)
        _getBuffer("before", item.command);
    }

    Timer {
        id: spawnRetryTimer
        interval: 1500
        running: false
        repeat: false
        onTriggered: root._processQueue()
    }

    // --- Send command via kitty remote control ---
    function _sendCommand(command) {
        sendProcess.command = [
            "kitty", "@", "--to", "unix:" + _socketPath,
            "send-text", "--", command + "\n"
        ];
        sendProcess.running = true;
    }

    Process { id: sendProcess; running: false }

    // --- Get terminal buffer ---
    property string _getBufferPhase: ""
    property string _pendingCommand: ""

    function _getBuffer(phase, command) {
        _getBufferPhase = phase;
        _pendingCommand = command || "";
        getTextProcess.command = [
            "kitty", "@", "--to", "unix:" + _socketPath,
            "get-text", "--extent", "all", "--ansi"
        ];
        getTextProcess.running = true;
    }

    Process {
        id: getTextProcess
        running: false
        stdout: StdioCollector { id: getTextStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            let buffer = getTextStdout.text;

            if (root._getBufferPhase === "before") {
                // Store buffer before command
                root._bufferBefore = buffer;
                root._lastBuffer = buffer;
                root._stableCount = 0;
                root._pollCount = 0;

                // Send the command
                root._sendCommand(root._pendingCommand);

                // Start polling after a short delay
                pollStartTimer.running = true;

            } else if (root._getBufferPhase === "poll") {
                if (buffer === root._lastBuffer) {
                    root._stableCount++;
                } else {
                    root._stableCount = 0;
                    root._lastBuffer = buffer;
                }

                if (root._stableCount >= root._stableThreshold || root._pollCount >= root._maxPolls) {
                    pollTimer.running = false;
                    root._extractResult(buffer);
                }

            } else if (root._getBufferPhase === "capture") {
                root._extractResult(buffer);
            }
        }
    }

    Timer {
        id: pollStartTimer
        interval: 800  // wait for command to start producing output
        running: false
        repeat: false
        onTriggered: { pollTimer.running = true; }
    }

    Timer {
        id: pollTimer
        interval: 500
        running: false
        repeat: true
        onTriggered: {
            root._pollCount++;
            root._getBuffer("poll");
        }
    }

    // --- Extract result ---
    function _extractResult(currentBuffer) {
        // The new output is everything in currentBuffer that wasn't in bufferBefore
        let result = currentBuffer;

        // Remove the prefix that matches bufferBefore
        if (_bufferBefore.length > 0 && result.indexOf(_bufferBefore) === 0) {
            result = result.substring(_bufferBefore.length);
        } else {
            // Buffer scrolled — try to find new content by removing common suffix
            // Just use the whole buffer minus bufferBefore length as approximation
            let beforeLines = _bufferBefore.split("\n");
            let currentLines = result.split("\n");

            // Find where the new content starts
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

        // Strip ANSI codes
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

        if (_pollCount >= _maxPolls) {
            result = "Command may still be running (output capture timed out).\n\nOutput so far:\n" + result;
        }

        console.log("ShellService: captured", result.length, "chars after", _pollCount, "polls");
        _locked = false;
        root.execComplete(_currentCallId, result);
        _processQueue();
    }

    // --- Helpers ---
    function _failAllQueued(reason) {
        while (_queue.length > 0) {
            let item = _queue.shift();
            root.execComplete(item.toolCallId, reason);
        }
    }

    // --- Cleanup ---
    Component.onDestruction: {
        terminalProcess.running = false;
        cleanupProcess.command = ["rm", "-f", _socketPath];
        cleanupProcess.running = true;
    }

    Process { id: cleanupProcess; running: false }
}
