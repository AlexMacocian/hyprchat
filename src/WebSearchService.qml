import QtQuick
import Quickshell
import Quickshell.Io

// Web search via DuckDuckGo HTML endpoint.
// Async — call search(), get results via searchComplete signal.
// Supports queuing: multiple concurrent requests are processed sequentially.
Item {
    id: root

    // Resolve scraper.js path relative to the config
    readonly property string _scraperPath: {
        let configPath = Quickshell.env("QS_CONFIG_PATH") || Quickshell.env("PWD");
        if (configPath.indexOf("/src") >= 0) {
            return configPath + "/scraper/scraper.js";
        }
        return configPath + "/src/scraper/scraper.js";
    }

    property bool searching: false

    signal searchComplete(string toolCallId, string results)
    signal pageComplete(string toolCallId, string content)

    // ========================
    // --- Web Search ---
    // ========================
    property string _searchCallId: ""
    property var _searchQueue: []

    function search(query, toolCallId) {
        _searchQueue.push({ query: query, toolCallId: toolCallId });
        if (!searching) _processNextSearch();
    }

    function _processNextSearch() {
        if (_searchQueue.length === 0) {
            searching = false;
            return;
        }
        searching = true;
        let item = _searchQueue.shift();
        _searchCallId = item.toolCallId;

        let encoded = item.query.replace(/ /g, "+").replace(/[^a-zA-Z0-9+\-_.]/g, function(c) {
            return "%" + c.charCodeAt(0).toString(16).toUpperCase();
        });

        searchProcess.command = [
            "bash", "-c",
            "curl -sk 'https://html.duckduckgo.com/html/?q=" + encoded + "' " +
            "-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' | " +
            "sed -n 's/.*class=\"result__a\".*href=\"\\([^\"]*\\)\".*>\\(.*\\)<\\/a>.*/URL:\\1\\nTITLE:\\2/p' | " +
            "sed 's/<[^>]*>//g; s/&amp;/\\&/g; s/&#x27;/\\x27/g; s/&quot;/\"/g' | " +
            "head -20"
        ];
        searchTimeout.restart();
        searchProcess.running = true;
    }

    Timer {
        id: searchTimeout
        interval: 25000
        repeat: false
        onTriggered: {
            console.warn("WebSearchService: search timed out for callId", root._searchCallId);
            searchProcess.running = false;
            root.searchComplete(root._searchCallId, "Search timed out after 25 seconds.");
            root._processNextSearch();
        }
    }

    Process {
        id: searchProcess
        running: false
        stdout: StdioCollector { id: searchStdout; waitForEnd: true }
        stderr: StdioCollector { id: searchStderr; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            searchTimeout.stop();
            let text = searchStdout.text;
            let errText = searchStderr.text.trim();

            if (exitCode !== 0 || text.length === 0) {
                let msg = "Search failed or returned no results.";
                if (errText.length > 0) msg += "\nError: " + errText;
                root.searchComplete(root._searchCallId, msg);
                root._processNextSearch();
                return;
            }

            // Parse URL:/TITLE: pairs
            let lines = text.split("\n").filter(function(l) { return l.length > 0; });
            let results = [];
            let currentUrl = "";

            for (let i = 0; i < lines.length; i++) {
                let line = lines[i];
                if (line.indexOf("URL:") === 0) {
                    let rawUrl = line.substring(4);
                    // Extract actual URL from DDG redirect
                    let urlMatch = rawUrl.match(/uddg=([^&]+)/);
                    if (urlMatch) {
                        currentUrl = decodeURIComponent(urlMatch[1]);
                    } else {
                        currentUrl = rawUrl;
                    }
                } else if (line.indexOf("TITLE:") === 0 && currentUrl.length > 0) {
                    let title = line.substring(6).trim();
                    results.push({ title: title, url: currentUrl });
                    currentUrl = "";
                }
            }

            if (results.length === 0) {
                root.searchComplete(root._searchCallId, "No results found.");
                root._processNextSearch();
                return;
            }

            let output = "Search results:\n\n";
            let count = Math.min(results.length, 8);
            for (let i = 0; i < count; i++) {
                let r = results[i];
                output += (i + 1) + ". **" + r.title + "**\n";
                output += "   " + r.url + "\n\n";
            }

            root.searchComplete(root._searchCallId, output);
            root._processNextSearch();
        }
    }

    // ========================
    // --- Fetch Page Content ---
    // ========================
    property string _pageCallId: ""
    property string _pageUrl: ""
    property var _fetchQueue: []
    property bool _fetching: false

    function fetchPage(url, toolCallId) {
        _fetchQueue.push({ url: url, toolCallId: toolCallId });
        if (!_fetching) _processNextFetch();
    }

    function _processNextFetch() {
        if (_fetchQueue.length === 0) {
            _fetching = false;
            return;
        }
        _fetching = true;
        let item = _fetchQueue.shift();
        _pageCallId = item.toolCallId;
        _pageUrl = item.url;

        // Use Readability.js scraper for clean article extraction
        fetchProcess.command = [
            "node", root._scraperPath,
            item.url
        ];
        fetchTimeout.restart();
        fetchProcess.running = true;
    }

    Timer {
        id: fetchTimeout
        interval: 30000
        repeat: false
        onTriggered: {
            console.warn("WebSearchService: fetch timed out for", root._pageUrl);
            fetchProcess.running = false;
            root.pageComplete(root._pageCallId, "Fetch timed out after 30 seconds for: " + root._pageUrl);
            root._processNextFetch();
        }
    }

    Process {
        id: fetchProcess
        running: false
        stdout: StdioCollector { id: fetchStdout; waitForEnd: true }
        stderr: StdioCollector { id: fetchStderr; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            fetchTimeout.stop();
            let text = fetchStdout.text;
            let errText = fetchStderr.text.trim();

            if (exitCode !== 0 || text.length === 0) {
                // Scraper failed — try curl fallback
                console.warn("WebSearchService: scraper failed for", root._pageUrl,
                    "exit:", exitCode, "err:", errText);
                root._startFallbackFetch();
                return;
            }

            // Truncate to reasonable size
            if (text.length > 8000) {
                text = text.substring(0, 8000) + "\n\n[Truncated — page content too long]";
            }

            root.pageComplete(root._pageCallId, text);
            root._processNextFetch();
        }
    }

    // --- Fallback: curl-based text extraction when Node scraper fails ---
    function _startFallbackFetch() {
        console.log("WebSearchService: attempting curl fallback for", _pageUrl);
        fallbackFetchProcess.command = [
            "bash", "-c",
            "curl -skL --max-time 20 " +
            "-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' " +
            "'" + _pageUrl.replace(/'/g, "'\\''") + "' | " +
            "sed 's/<script[^>]*>[\\s\\S]*?<\\/script>//gi' | " +
            "sed 's/<style[^>]*>[\\s\\S]*?<\\/style>//gi' | " +
            "sed 's/<[^>]*>/ /g' | " +
            "sed 's/&amp;/\\&/g; s/&lt;/</g; s/&gt;/>/g; s/&quot;/\"/g; s/&#39;/\\x27/g; s/&#x27;/\\x27/g; s/&nbsp;/ /g' | " +
            "tr -s ' \\t' ' ' | " +
            "head -c 8000"
        ];
        fallbackTimeout.restart();
        fallbackFetchProcess.running = true;
    }

    Timer {
        id: fallbackTimeout
        interval: 25000
        repeat: false
        onTriggered: {
            console.warn("WebSearchService: fallback fetch timed out for", root._pageUrl);
            fallbackFetchProcess.running = false;
            root.pageComplete(root._pageCallId,
                "Failed to fetch page (both scraper and fallback timed out): " + root._pageUrl);
            root._processNextFetch();
        }
    }

    Process {
        id: fallbackFetchProcess
        running: false
        stdout: StdioCollector { id: fallbackStdout; waitForEnd: true }
        stderr: StdioCollector { id: fallbackStderr; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            fallbackTimeout.stop();
            let text = fallbackStdout.text.trim();
            let errText = fallbackStderr.text.trim();

            if (exitCode !== 0 || text.length === 0) {
                let msg = "Failed to fetch page: " + root._pageUrl;
                if (errText.length > 0) msg += "\nError: " + errText;
                root.pageComplete(root._pageCallId, msg);
                root._processNextFetch();
                return;
            }

            // Clean up excessive whitespace
            text = text.replace(/\n{3,}/g, "\n\n").trim();

            if (text.length > 8000) {
                text = text.substring(0, 8000) + "\n\n[Truncated — page content too long]";
            }

            root.pageComplete(root._pageCallId, "[Extracted via fallback — formatting may be rough]\n\n" + text);
            root._processNextFetch();
        }
    }
}
