import QtQuick
import Quickshell
import Quickshell.Io

// Reads and writes user preferences from ~/.config/hyprchat/preferences.json
// Properties here map directly to JSON keys.
Item {
    id: root

    readonly property string prefsDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hyprchat"
    readonly property string prefsPath: prefsDir + "/preferences.json"

    property string activeBackend: "copilot"
    property string activeModel: "gpt-4o"
    property real summarizeThreshold: 0.7

    property bool _loaded: false

    Component.onCompleted: {
        load();
    }

    function load() {
        loadProcess.command = ["cat", prefsPath];
        loadProcess.running = true;
    }

    function save() {
        let data = JSON.stringify({
            active_backend: root.activeBackend,
            active_model: root.activeModel,
            summarize_threshold: root.summarizeThreshold
        }, null, 2);

        // Use printf to write to file — avoids shell escaping issues with echo
        saveProcess.command = [
            "bash", "-c",
            "mkdir -p '" + prefsDir + "' && printf '%s' '" + data.replace(/'/g, "'\"'\"'") + "' > '" + prefsPath + "'"
        ];
        saveProcess.running = true;
    }

    Process {
        id: loadProcess
        running: false

        stdout: StdioCollector {
            id: loadStdout
            waitForEnd: true
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                try {
                    let json = JSON.parse(loadStdout.text);
                    if (json.active_backend) root.activeBackend = json.active_backend;
                    if (json.active_model) root.activeModel = json.active_model;
                    if (json.summarize_threshold !== undefined) root.summarizeThreshold = json.summarize_threshold;
                } catch (e) {
                    console.warn("Preferences: failed to parse:", e);
                }
            }
            root._loaded = true;
        }
    }

    Process {
        id: saveProcess
        running: false
    }
}
