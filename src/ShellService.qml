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

    // --- Execute command and capture output ---
    property string _execCallId: ""
    property string _execCommand: ""

    function exec(command, toolCallId) {
        if (execProcess.running) {
            root.execComplete(toolCallId, "Error: another command is still running.");
            return;
        }
        _execCallId = toolCallId;
        _execCommand = command;

        execProcess.command = [
            "bash", "-c",
            "cd '" + workingDirectory + "' && timeout " + timeout + " " + shell + " -c " +
            "'" + command.replace(/'/g, "'\\''") + "' 2>&1"
        ];
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
        }
    }

    // --- Execute background command (no output capture) ---
    property string _bgCallId: ""

    function execBackground(command, toolCallId) {
        _bgCallId = toolCallId;

        bgProcess.command = [
            "bash", "-c",
            "cd '" + workingDirectory + "' && " + shell + " -c " +
            "'" + command.replace(/'/g, "'\\''") + "' &"
        ];
        bgProcess.running = true;
    }

    Process {
        id: bgProcess
        running: false

        onExited: (exitCode, exitStatus) => {
            root.execComplete(root._bgCallId, "Command started in background.");
        }
    }
}
