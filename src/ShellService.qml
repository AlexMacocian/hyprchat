import QtQuick
import Quickshell
import Quickshell.Io

// Shell command execution service.
// Runs commands via bash, captures stdout/stderr, returns results.
// Async — call exec(), get results via execComplete signal.
Item {
    id: root

    property int timeout: 30  // seconds
    property string shell: "/bin/bash"
    property string workingDirectory: Quickshell.env("HOME")
    property bool busy: execProcess.running

    signal execComplete(string toolCallId, string result)

    // --- Command queue ---
    property var _queue: []  // [{command, toolCallId, background}]
    property string _execCallId: ""
    property string _execCommand: ""

    function exec(command, toolCallId) {
        _queue.push({ command: command, toolCallId: toolCallId, background: false });
        _processQueue();
    }

    function execBackground(command, toolCallId) {
        _queue.push({ command: command, toolCallId: toolCallId, background: true });
        _processQueue();
    }

    // Commands that require elevation or interaction — blocked
    readonly property var _blockedPrefixes: [
        "sudo ", "sudo\t", "doas ", "pkexec ",
        "paru ", "yay ", "pacman -S", "pacman -R", "pacman -U",
        "apt install", "apt remove", "apt upgrade",
        "dnf install", "dnf remove", "dnf upgrade",
        "systemctl enable", "systemctl disable", "systemctl start", "systemctl stop",
        "rm -rf /", "mkfs", "dd if="
    ]

    function _isBlocked(command) {
        let cmd = command.replace(/^\s+/, "");
        for (let i = 0; i < _blockedPrefixes.length; i++) {
            if (cmd.indexOf(_blockedPrefixes[i]) === 0) return true;
        }
        // Also block if sudo/doas appears anywhere via pipe
        if (cmd.indexOf("| sudo") >= 0 || cmd.indexOf("| doas") >= 0) return true;
        return false;
    }

    function _processQueue() {
        if (execProcess.running || _queue.length === 0) return;

        let item = _queue.shift();
        _execCallId = item.toolCallId;
        _execCommand = item.command;

        // Check for blocked commands
        if (_isBlocked(item.command)) {
            root.execComplete(item.toolCallId,
                "BLOCKED: This command requires elevated privileges or is potentially destructive. " +
                "Tell the user to run it manually:\n\n```\n" + item.command + "\n```");
            root._processQueue();
            return;
        }

        if (item.background) {
            execProcess.command = [
                "bash", "-c",
                "cd '" + workingDirectory + "' && " + shell + " -c " +
                "'" + item.command.replace(/'/g, "'\\''") + "' &"
            ];
        } else {
            execProcess.command = [
                "bash", "-c",
                "cd '" + workingDirectory + "' && timeout " + timeout + " " + shell + " -c " +
                "'" + item.command.replace(/'/g, "'\\''") + "' 2>&1"
            ];
        }
        execProcess.running = true;
    }

    Process {
        id: execProcess
        running: false
        stdout: StdioCollector { id: execStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            let output = execStdout.text;

            // Truncate very long output
            if (output.length > 10000) {
                output = output.substring(0, 5000) +
                    "\n\n[... truncated " + (output.length - 10000) + " chars ...]\n\n" +
                    output.substring(output.length - 5000);
            }

            let result = "";
            if (exitCode === 124) {
                result = "Command timed out after " + root.timeout + "s.\n\nPartial output:\n" + output;
            } else if (exitCode !== 0) {
                result = "Exit code: " + exitCode + "\n\n" + output;
            } else {
                result = output.length > 0 ? output : "(no output)";
            }

            console.log("ShellService: command '" + root._execCommand.substring(0, 60) + "' exit:", exitCode, "output:", result.length, "chars");
            root.execComplete(root._execCallId, result);

            // Process next queued command
            root._processQueue();
        }
    }
}
