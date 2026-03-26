import QtQuick
import Quickshell
import Quickshell.Io

// Web search via DuckDuckGo HTML endpoint.
// Async — call search(), get results via searchComplete signal.
Item {
    id: root

    // Resolve scraper.js path relative to the config
    readonly property string _scraperPath: {
        let configPath = Quickshell.env("QS_CONFIG_PATH") || Quickshell.env("PWD");
        // If running from src/, go to scraper/. If from project root, go to src/scraper/
        if (configPath.indexOf("/src") >= 0) {
            return configPath + "/scraper/scraper.js";
        }
        return configPath + "/src/scraper/scraper.js";
    }

    property bool searching: false

    signal searchComplete(string toolCallId, string results)
    signal pageComplete(string toolCallId, string content)

    // --- Web Search ---
    property string _searchCallId: ""

    function search(query, toolCallId) {
        if (searching) return;
        _searchCallId = toolCallId;
        searching = true;

        let encoded = query.replace(/ /g, "+").replace(/[^a-zA-Z0-9+\-_.]/g, function(c) {
            return "%" + c.charCodeAt(0).toString(16).toUpperCase();
        });

        searchProcess.command = [
            "bash", "-c",
            "curl -s 'https://html.duckduckgo.com/html/?q=" + encoded + "' " +
            "-H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36' | " +
            "sed -n 's/.*class=\"result__a\".*href=\"\\([^\"]*\\)\".*>\\(.*\\)<\\/a>.*/URL:\\1\\nTITLE:\\2/p' | " +
            "sed 's/<[^>]*>//g; s/&amp;/\\&/g; s/&#x27;/\\x27/g; s/&quot;/\"/g' | " +
            "head -20"
        ];
        searchProcess.running = true;
    }

    Process {
        id: searchProcess
        running: false
        stdout: StdioCollector { id: searchStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            root.searching = false;
            let text = searchStdout.text;

            if (exitCode !== 0 || text.length === 0) {
                root.searchComplete(root._searchCallId, "Search failed or returned no results.");
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
        }
    }

    // --- Fetch Page Content ---
    property string _pageCallId: ""

    function fetchPage(url, toolCallId) {
        _pageCallId = toolCallId;

        // Use Readability.js scraper for clean article extraction
        fetchProcess.command = [
            "node", root._scraperPath,
            url
        ];
        fetchProcess.running = true;
    }

    Process {
        id: fetchProcess
        running: false
        stdout: StdioCollector { id: fetchStdout; waitForEnd: true }

        onExited: (exitCode, exitStatus) => {
            let text = fetchStdout.text;
            if (exitCode !== 0 || text.length === 0) {
                root.pageComplete(root._pageCallId, "Failed to fetch page.");
                return;
            }

            // Truncate to reasonable size
            if (text.length > 8000) {
                text = text.substring(0, 8000) + "\n\n[Truncated — page content too long]";
            }

            root.pageComplete(root._pageCallId, text);
        }
    }
}
