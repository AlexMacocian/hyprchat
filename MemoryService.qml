import QtQuick
import Quickshell
import Quickshell.Io

// Manages encrypted memory files with in-memory cache.
// All topics are decrypted and loaded into memory at startup.
// Changes update the cache immediately and write back encrypted to disk.
Item {
    id: root

    readonly property string memoryDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/hyprchat/memory"
    property string _encryptionKey: ""
    property bool ready: _encryptionKey.length > 0 && _cacheLoaded

    // In-memory cache: { "topic_name": "markdown content", ... }
    property var cache: ({})
    property var topicNames: []
    property bool _cacheLoaded: false
    property int _cacheVersion: 0  // bump to trigger UI reactivity

    signal cacheReady()
    signal topicChanged(string topic)
    signal topicDeleted(string topic)
    signal error(string message)

    Component.onCompleted: {
        ensureDirProcess.command = ["mkdir", "-p", memoryDir];
        ensureDirProcess.running = true;
    }

    Process {
        id: ensureDirProcess
        running: false
        onExited: {
            keyLookupProcess.command = ["secret-tool", "lookup", "service", "hyprchat", "account", "memory_key"];
            keyLookupProcess.running = true;
        }
    }

    // --- Key Management ---
    Process {
        id: keyLookupProcess
        running: false
        stdout: StdioCollector { id: keyLookupStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            let key = keyLookupStdout.text.trim();
            if (key.length === 64) {
                root._encryptionKey = key;
                console.log("MemoryService: key loaded");
                root._loadAllTopics();
            } else {
                console.log("MemoryService: generating new key");
                keyGenProcess.command = ["openssl", "rand", "-hex", "32"];
                keyGenProcess.running = true;
            }
        }
    }

    Process {
        id: keyGenProcess
        running: false
        stdout: StdioCollector { id: keyGenStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root._encryptionKey = keyGenStdout.text.trim();
                keyStoreProcess.command = [
                    "bash", "-c",
                    "printf '%s' '" + root._encryptionKey + "' | secret-tool store --label='HyprChat Memory Key' service hyprchat account memory_key"
                ];
                keyStoreProcess.running = true;
            } else {
                root.error("Failed to generate encryption key");
            }
        }
    }

    Process {
        id: keyStoreProcess
        running: false
        onExited: {
            console.log("MemoryService: key stored");
            root._cacheLoaded = true;
            root.cacheReady();
        }
    }

    // Encryption format version
    readonly property string _encHeader: "HYPRCHAT:v1:aes-256-cbc"

    // --- Load All Topics at Startup ---
    function _loadAllTopics() {
        loadAllProcess.command = [
            "bash", "-c",
            "for f in '" + memoryDir + "'/*.md.enc 2>/dev/null; do " +
            "  [ -f \"$f\" ] || continue; " +
            "  topic=$(basename \"$f\" .md.enc); " +
            "  echo \"__TOPIC__:$topic\"; " +
            "  header=$(head -c 24 \"$f\"); " +
            "  if [ \"$header\" = 'HYPRCHAT:v1:aes-256-cbc' ]; then " +
            "    tail -c +26 \"$f\" | openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:" + _encryptionKey + " 2>/dev/null; " +
            "  else " +
            "    openssl enc -d -aes-256-cbc -pbkdf2 -in \"$f\" -pass pass:" + _encryptionKey + " 2>/dev/null; " +
            "  fi; " +
            "  echo \"__END__\"; " +
            "done"
        ];
        loadAllProcess.running = true;
    }

    Process {
        id: loadAllProcess
        running: false
        stdout: StdioCollector { id: loadAllStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            let text = loadAllStdout.text;
            let newCache = {};
            let names = [];

            if (text.length > 0) {
                let parts = text.split("__TOPIC__:");
                for (let i = 0; i < parts.length; i++) {
                    let part = parts[i].trim();
                    if (part.length === 0) continue;

                    let firstNewline = part.indexOf("\n");
                    if (firstNewline < 0) continue;

                    let topic = part.substring(0, firstNewline).trim();
                    let content = part.substring(firstNewline + 1);

                    let endIdx = content.lastIndexOf("__END__");
                    if (endIdx >= 0) {
                        content = content.substring(0, endIdx).trimEnd();
                    }

                    newCache[topic] = content;
                    names.push(topic);
                }
            }

            root.cache = newCache;
            root.topicNames = names.sort();
            root._cacheLoaded = true;
            root._cacheVersion++;
            console.log("MemoryService: loaded", names.length, "topics into cache");
            root.cacheReady();
        }
    }

    // --- Public API (synchronous from cache) ---

    function listTopics() {
        return topicNames;
    }

    function readTopic(topic) {
        let v = _cacheVersion;
        return cache[topic] || "";
    }

    function appendTopic(topic, content) {
        if (!_isValidTopic(topic)) { root.error("Invalid topic name"); return; }

        let existing = cache[topic] || "";
        let separator = existing.length > 0 ? "\n\n" : "";
        cache[topic] = existing + separator + content;

        if (topicNames.indexOf(topic) < 0) {
            let names = topicNames.slice();
            names.push(topic);
            topicNames = names.sort();
        }

        _cacheVersion++;
        _persistTopic(topic);
        root.topicChanged(topic);
    }

    function editTopic(topic, content) {
        if (!_isValidTopic(topic)) { root.error("Invalid topic name"); return; }

        cache[topic] = content;

        if (topicNames.indexOf(topic) < 0) {
            let names = topicNames.slice();
            names.push(topic);
            topicNames = names.sort();
        }

        _cacheVersion++;
        _persistTopic(topic);
        root.topicChanged(topic);
    }

    function deleteTopic(topic) {
        if (!_isValidTopic(topic)) { root.error("Invalid topic name"); return; }

        delete cache[topic];
        topicNames = topicNames.filter(n => n !== topic);
        _cacheVersion++;

        deleteFileProcess.command = ["rm", "-f", memoryDir + "/" + topic + ".md.enc"];
        deleteFileProcess.running = true;

        root.topicDeleted(topic);
    }

    function search(query) {
        let q = query.toLowerCase();
        let results = [];
        for (let i = 0; i < topicNames.length; i++) {
            let topic = topicNames[i];
            let content = cache[topic] || "";
            if (content.toLowerCase().indexOf(q) >= 0 || topic.toLowerCase().indexOf(q) >= 0) {
                let lines = content.split("\n");
                let matches = lines.filter(l => l.toLowerCase().indexOf(q) >= 0);
                results.push({ topic: topic, matches: matches.slice(0, 5).join("\n") });
            }
        }
        return results;
    }

    // --- Write-back queue ---
    property var _writeQueue: []
    property bool _writing: false

    function _persistTopic(topic) {
        _writeQueue.push(topic);
        _processWriteQueue();
    }

    function _processWriteQueue() {
        if (_writing || _writeQueue.length === 0) return;
        _writing = true;

        let topic = _writeQueue.shift();
        let content = cache[topic] || "";
        let file = memoryDir + "/" + topic + ".md.enc";

        // Write with header: HYPRCHAT:v1:aes-256-cbc\n then encrypted data
        persistProcess.command = [
            "bash", "-c",
            "cat > /tmp/hyprchat-mem-plain.md && " +
            "printf 'HYPRCHAT:v1:aes-256-cbc\n' > '" + file + "' && " +
            "openssl enc -aes-256-cbc -pbkdf2 -in /tmp/hyprchat-mem-plain.md -pass pass:" + _encryptionKey + " >> '" + file + "' && " +
            "rm -f /tmp/hyprchat-mem-plain.md"
        ];
        persistProcess.stdinEnabled = true;
        persistProcess._content = content;
        persistProcess.running = true;
    }

    Process {
        id: persistProcess
        running: false
        property string _content: ""

        onStarted: {
            persistProcess.write(persistProcess._content);
            persistProcess.stdinEnabled = false;
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0) {
                console.warn("MemoryService: persist failed");
            }
            root._writing = false;
            root._processWriteQueue();
        }
    }

    Process {
        id: deleteFileProcess
        running: false
    }

    // --- Validation ---
    function _isValidTopic(name) {
        return /^[a-zA-Z0-9_-]+$/.test(name);
    }
}
