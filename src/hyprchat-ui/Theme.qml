pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: theme

    readonly property string _configDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hyprchat"
    readonly property string _themePath: _configDir + "/theme.jsonc"

    // Background layers
    property color bg0: "#0F0808"
    property color bg1: "#1C1210"
    property color bg2: "#2D1F1A"
    property color bg3: "#3E2C25"

    // Accents and borders
    property color border: "#C23A22"
    property color accent1: "#D4391E"
    property color accent2: "#E07A30"

    // Text
    property color text: "#E8CFC0"
    property color textDim: "#A08070"

    // Danger / destructive actions
    property color danger: "#FF6060"
    property color dangerBg: "#802020"

    // Font
    property string fontFamily: "JetBrainsMono Nerd Font"
    property int fontSize: 12

    // -- Defaults (for writing initial theme file) --
    readonly property var _defaults: ({
        bg0: "#0F0808",
        bg1: "#1C1210",
        bg2: "#2D1F1A",
        bg3: "#3E2C25",
        border: "#C23A22",
        accent1: "#D4391E",
        accent2: "#E07A30",
        text: "#E8CFC0",
        textDim: "#A08070",
        danger: "#FF6060",
        dangerBg: "#802020",
        fontFamily: "JetBrainsMono Nerd Font",
        fontSize: 12
    })

    // --- Load theme from JSON ---
    Component.onCompleted: {
        _load();
        _startWatcher();
    }

    function _load() {
        loadProcess.command = ["cat", _themePath];
        loadProcess.running = true;
    }

    // --- Watch theme file for changes ---
    function _startWatcher() {
        watchProcess.command = [
            "bash", "-c",
            "while inotifywait -q -e close_write '" + _themePath + "' 2>/dev/null; do echo CHANGED; done"
        ];
        watchProcess.running = true;
    }

    Process {
        id: watchProcess
        running: false

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: (line) => {
                if (line.indexOf("CHANGED") >= 0) {
                    console.log("Theme: file changed, reloading");
                    theme._load();
                }
            }
        }

        onExited: {
            // Restart watcher if it dies
            theme._startWatcher();
        }
    }

    function _apply(json) {
        if (json.bg0 !== undefined) theme.bg0 = json.bg0;
        if (json.bg1 !== undefined) theme.bg1 = json.bg1;
        if (json.bg2 !== undefined) theme.bg2 = json.bg2;
        if (json.bg3 !== undefined) theme.bg3 = json.bg3;
        if (json.border !== undefined) theme.border = json.border;
        if (json.accent1 !== undefined) theme.accent1 = json.accent1;
        if (json.accent2 !== undefined) theme.accent2 = json.accent2;
        if (json.text !== undefined) theme.text = json.text;
        if (json.textDim !== undefined) theme.textDim = json.textDim;
        if (json.danger !== undefined) theme.danger = json.danger;
        if (json.dangerBg !== undefined) theme.dangerBg = json.dangerBg;
        if (json.fontFamily !== undefined) theme.fontFamily = json.fontFamily;
        if (json.fontSize !== undefined) theme.fontSize = json.fontSize;
        console.log("Theme: loaded from", _themePath);
    }

    function _writeDefaults() {
        let data = "// HyprChat theme file (JSONC)\n" +
                   "// Edit this file to customize colors and fonts.\n" +
                   "// Changes are applied automatically.\n" +
                   JSON.stringify(_defaults, null, 2) + "\n";
        writeProcess.command = [
            "bash", "-c",
            "mkdir -p '" + _configDir + "' && cat > '" + _themePath + "'"
        ];
        writeProcess.stdinEnabled = true;
        writeProcess._content = data;
        writeProcess.running = true;
    }

    Process {
        id: loadProcess
        running: false
        stdout: StdioCollector { id: loadStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0 && loadStdout.text.length > 0) {
                try {
                    // Strip JSONC comments (// and /* */) before parsing
                    let raw = loadStdout.text;
                    let stripped = raw.replace(/\/\/.*$/gm, "").replace(/\/\*[\s\S]*?\*\//g, "");
                    let json = JSON.parse(stripped);
                    theme._apply(json);
                } catch (e) {
                    console.warn("Theme: failed to parse theme.json:", e);
                }
            } else {
                // No theme file — write defaults
                console.log("Theme: no theme.json found, writing defaults");
                theme._writeDefaults();
            }
        }
    }

    Process {
        id: writeProcess
        running: false
        property string _content: ""

        onStarted: {
            writeProcess.write(writeProcess._content);
            writeProcess.stdinEnabled = false;
        }

        onExited: {
            console.log("Theme: defaults written to", theme._themePath);
        }
    }
}
