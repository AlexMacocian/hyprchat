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
    property int keepRecentMessages: 4
    property string systemPrompt: "You are a helpful assistant. Be concise."
    property bool memoryEnabled: true
    property int memorySplitThreshold: 200
    property bool webSearchEnabled: true
    property bool shellEnabled: false
    property bool fileAccessEnabled: true
    property string fileAccessRoot: "/"
    property bool dateEnabled: true

    // --- Profiles ---
    property string activeProfileName: "Assistant"
    property var profiles: [
        {
            name: "Assistant",
            icon: "🤖",
            backend: "copilot",
            model: "gpt-4o",
            systemPrompt: "You are a helpful assistant. Be concise."
        }
    ]

    // Convenience: get the active profile object
    readonly property var activeProfile: {
        for (let i = 0; i < profiles.length; i++) {
            if (profiles[i].name === activeProfileName) return profiles[i];
        }
        return profiles[0];
    }

    // Switch to a profile — updates activeBackend/model/systemPrompt
    function switchProfile(name) {
        activeProfileName = name;
        let p = activeProfile;
        activeBackend = p.backend;
        activeModel = p.model;
        systemPrompt = p.systemPrompt;
        save();
    }

    function addProfile(profile) {
        let p = profiles.slice();
        p.push(profile);
        profiles = p;
        save();
    }

    function updateProfile(name, profile) {
        let p = profiles.slice();
        for (let i = 0; i < p.length; i++) {
            if (p[i].name === name) {
                p[i] = profile;
                break;
            }
        }
        profiles = p;
        // If we updated the active profile, refresh current values
        if (name === activeProfileName) {
            activeBackend = profile.backend;
            activeModel = profile.model;
            systemPrompt = profile.systemPrompt;
        }
        save();
    }

    function deleteProfile(name) {
        if (name === "Assistant") return; // can't delete default
        let p = profiles.filter(function(pr) { return pr.name !== name; });
        profiles = p;
        if (activeProfileName === name) {
            switchProfile("Assistant");
        }
        save();
    }

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
            active_profile: root.activeProfileName,
            profiles: root.profiles,
            summarize_threshold: root.summarizeThreshold,
            keep_recent_messages: root.keepRecentMessages,
            memory_enabled: root.memoryEnabled,
            memory_split_threshold: root.memorySplitThreshold,
            web_search_enabled: root.webSearchEnabled,
            shell_enabled: root.shellEnabled,
            file_access_enabled: root.fileAccessEnabled,
            file_access_root: root.fileAccessRoot,
            date_enabled: root.dateEnabled
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
                    if (json.active_profile) root.activeProfileName = json.active_profile;
                    if (json.profiles && Array.isArray(json.profiles) && json.profiles.length > 0) root.profiles = json.profiles;
                    // Apply active profile values
                    let p = root.activeProfile;
                    root.activeBackend = p.backend;
                    root.activeModel = p.model;
                    root.systemPrompt = p.systemPrompt;
                    if (json.summarize_threshold !== undefined) root.summarizeThreshold = json.summarize_threshold;
                    if (json.keep_recent_messages !== undefined) root.keepRecentMessages = json.keep_recent_messages;
                    if (json.memory_enabled !== undefined) root.memoryEnabled = json.memory_enabled;
                    if (json.memory_split_threshold !== undefined) root.memorySplitThreshold = json.memory_split_threshold;
                    if (json.web_search_enabled !== undefined) root.webSearchEnabled = json.web_search_enabled;
                    if (json.shell_enabled !== undefined) root.shellEnabled = json.shell_enabled;
                    if (json.file_access_enabled !== undefined) root.fileAccessEnabled = json.file_access_enabled;
                    if (json.file_access_root !== undefined) root.fileAccessRoot = json.file_access_root;
                    if (json.date_enabled !== undefined) root.dateEnabled = json.date_enabled;
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
