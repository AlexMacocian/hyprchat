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
    property int splitThreshold: 200  // lines before suggesting split

    // In-memory cache: { "topic_name": "markdown content", ... }
    // Nested topics use "/" separator: "linux/hyprland"
    property var cache: ({})
    property var topicNames: []
    property bool _cacheLoaded: false
    property int _cacheVersion: 0

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
        console.log("MemoryService: loading topics, key length:", _encryptionKey.length, "dir:", memoryDir);
        // Find all .md.enc files including subdirectories
        loadAllProcess.command = [
            "bash", "-c",
            "find '" + memoryDir + "' -name '*.md.enc' 2>/dev/null | while read f; do " +
            "  topic=$(realpath --relative-to='" + memoryDir + "' \"$f\" | sed 's/\\.md\\.enc$//'); " +
            "  echo \"__TOPIC__:$topic\"; " +
            "  header=$(head -1 \"$f\"); " +
            "  if echo \"$header\" | grep -q '^HYPRCHAT:'; then " +
            "    algo=$(echo \"$header\" | cut -d: -f3); " +
            "    headerlen=$(echo -n \"$header\" | wc -c); " +
            "    headerlen=$((headerlen + 1)); " +
            "    if [ \"$algo\" = 'aes-256-cbc' ]; then " +
            "      tail -c +$((headerlen + 1)) \"$f\" | openssl enc -d -aes-256-cbc -pbkdf2 -pass pass:" + _encryptionKey + " 2>/dev/null; " +
            "    else " +
            "      echo '[unsupported encryption: '$algo']'; " +
            "    fi; " +
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
            console.log("MemoryService: load exited code:", exitCode, "output length:", text.length, "first 200:", text.substring(0, 200));
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
                        content = content.substring(0, endIdx).replace(/\s+$/, "");
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
        if (!_isValidTopic(topic)) { root.error("Invalid topic name"); return ""; }

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

        // Return hint if file is getting large
        let lines = cache[topic].split("\n").length;
        if (lines > splitThreshold) {
            return "Appended to '" + topic + "'. WARNING: " + topic + " is now " + lines + " lines (threshold: " + splitThreshold + "). Consider using memory_reorganize to split it into subtopics.";
        }
        return "Appended to '" + topic + "'.";
    }

    function editTopic(topic, content) {
        if (!_isValidTopic(topic)) { root.error("Invalid topic name"); return "Error: invalid topic name."; }

        cache[topic] = content;

        if (topicNames.indexOf(topic) < 0) {
            let names = topicNames.slice();
            names.push(topic);
            topicNames = names.sort();
        }

        _cacheVersion++;
        _persistTopic(topic);
        root.topicChanged(topic);

        let lines = content.split("\n").length;
        if (lines > splitThreshold) {
            return "Saved '" + topic + "'. WARNING: " + topic + " is now " + lines + " lines (threshold: " + splitThreshold + "). Consider using memory_reorganize to split it into subtopics.";
        }
        return "Saved '" + topic + "'.";
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

    // Reorganize: split a topic into subtopics
    // subtopics is an array of { name: "subtopic_name", content: "markdown" }
    function reorganizeTopic(sourceTopic, subtopics) {
        if (!_isValidTopic(sourceTopic)) { root.error("Invalid topic name"); return "Error: invalid topic"; }

        // Create each subtopic as sourceTopic/subtopicName
        for (let i = 0; i < subtopics.length; i++) {
            let st = subtopics[i];
            let fullName = sourceTopic + "/" + st.name;
            if (!_isValidTopic(st.name)) { continue; }

            cache[fullName] = st.content;

            if (topicNames.indexOf(fullName) < 0) {
                let names = topicNames.slice();
                names.push(fullName);
                topicNames = names;
            }

            // Ensure subdirectory exists and persist
            _ensureDir(sourceTopic);
            _persistTopic(fullName);
        }

        // Delete the original topic
        delete cache[sourceTopic];
        topicNames = topicNames.filter(n => n !== sourceTopic);

        deleteFileProcess.command = ["rm", "-f", memoryDir + "/" + sourceTopic + ".md.enc"];
        deleteFileProcess.running = true;

        topicNames = topicNames.sort();
        _cacheVersion++;
        root.topicChanged(sourceTopic);

        return "Reorganized '" + sourceTopic + "' into " + subtopics.length + " subtopics: " + subtopics.map(s => sourceTopic + "/" + s.name).join(", ");
    }

    // Ensure subdirectory exists for nested topics
    function _ensureDir(subdir) {
        ensureSubdirProcess.command = ["mkdir", "-p", memoryDir + "/" + subdir];
        ensureSubdirProcess.running = true;
    }

    Process {
        id: ensureSubdirProcess
        running: false
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
        // Ensure parent directory exists for nested topics
        let dir = file.substring(0, file.lastIndexOf("/"));

        // Write with header: HYPRCHAT:v1:aes-256-cbc\n then encrypted data
        persistProcess.command = [
            "bash", "-c",
            "mkdir -p '" + dir + "' && " +
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
        // Allow alphanumeric, hyphens, underscores, and / for nesting
        if (!name || name.length === 0) return false;
        if (name.indexOf("..") >= 0) return false;
        if (name.startsWith("/") || name.endsWith("/")) return false;
        return /^[a-zA-Z0-9_\/-]+$/.test(name);
    }
}
