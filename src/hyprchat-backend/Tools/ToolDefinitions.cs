using System.Text.Json;

namespace HyprChat.Tools;

/// <summary>
/// Produces OpenAI function-calling tool definitions for the API request.
/// </summary>
public static class ToolDefinitions
{
    public static JsonElement EmptyObj { get; } =
        JsonDocument.Parse("""{ "type":"object","properties":{},"required":[]}""").RootElement.Clone();

    public static List<Protocol.ToolDefinition> Build(bool memory, bool web, bool shell, bool file, bool date)
    {
        var tools = new List<Protocol.ToolDefinition>();
        if (memory) tools.AddRange(MemoryTools);
        if (web) tools.AddRange(WebTools);
        if (shell) tools.AddRange(ShellTools);
        if (file) tools.AddRange(FileTools);
        if (date) tools.AddRange(DateTools);
        return tools;
    }

    private static Protocol.ToolDefinition Def(string name, string desc, string paramsJson) => new()
    {
        Function = new Protocol.ToolFunctionDef
        {
            Name = name,
            Description = desc,
            Parameters = JsonDocument.Parse(paramsJson).RootElement.Clone()
        }
    };

    // --- Memory ---
    private static readonly Protocol.ToolDefinition[] MemoryTools =
    [
        Def("memory_list_topics",
            "List all available memory topics",
            """{"type":"object","properties":{},"required":[]}"""),
        Def("memory_read",
            "Read the contents of a memory topic",
            """{"type":"object","properties":{"topic":{"type":"string","description":"Topic name"}},"required":["topic"]}"""),
        Def("memory_append",
            "Append content to a memory topic. Creates the topic if it doesn't exist. Use for quick additions without needing to read the topic first.",
            """{"type":"object","properties":{"topic":{"type":"string","description":"Topic name (alphanumeric, hyphens, underscores)"},"content":{"type":"string","description":"Markdown content to append"}},"required":["topic","content"]}"""),
        Def("memory_edit",
            "Replace the full content of a memory topic. Creates the topic if it doesn't exist. Use when you need to rewrite, restructure, or remove parts of existing content. Always read the topic first.",
            """{"type":"object","properties":{"topic":{"type":"string","description":"Topic name (alphanumeric, hyphens, underscores)"},"content":{"type":"string","description":"Complete markdown content that replaces everything in the topic"}},"required":["topic","content"]}"""),
        Def("memory_search",
            "Search across all memory topics for a keyword or phrase",
            """{"type":"object","properties":{"query":{"type":"string","description":"Search query"}},"required":["query"]}"""),
        Def("memory_reorganize",
            "Split a large memory topic into smaller subtopics. Use when a topic exceeds the size threshold. The original topic is deleted and replaced with subtopics under a directory.",
            """{"type":"object","properties":{"source_topic":{"type":"string","description":"The topic to split"},"subtopics":{"type":"array","description":"Array of new subtopics to create","items":{"type":"object","properties":{"name":{"type":"string","description":"Subtopic name (will be created as source_topic/name)"},"content":{"type":"string","description":"Markdown content for this subtopic"}},"required":["name","content"]}}},"required":["source_topic","subtopics"]}"""),
        Def("memory_delete",
            "Delete a memory topic and all its content. Use when information is outdated, wrong, or the topic is empty.",
            """{"type":"object","properties":{"topic":{"type":"string","description":"Topic name to delete"}},"required":["topic"]}"""),
    ];

    // --- Web ---
    private static readonly Protocol.ToolDefinition[] WebTools =
    [
        Def("web_search",
            "Search the web using DuckDuckGo. Returns titles, URLs, and snippets for the top results.",
            """{"type":"object","properties":{"query":{"type":"string","description":"Search query"}},"required":["query"]}"""),
        Def("web_read_page",
            "Fetch and read the text content of a web page URL. Returns cleaned text, truncated to ~8000 chars.",
            """{"type":"object","properties":{"url":{"type":"string","description":"URL to fetch"}},"required":["url"]}"""),
    ];

    // --- Shell ---
    private static readonly Protocol.ToolDefinition[] ShellTools =
    [
        Def("shell_exec",
            "Execute a shell command and return its output (stdout + stderr). Times out after 30s.",
            """{"type":"object","properties":{"command":{"type":"string","description":"The shell command to execute"}},"required":["command"]}"""),
        Def("shell_exec_background",
            "Execute a shell command in the background without waiting for output. Use for servers or long-running tasks.",
            """{"type":"object","properties":{"command":{"type":"string","description":"The shell command to run in background"}},"required":["command"]}"""),
    ];

    // --- File ---
    private static readonly Protocol.ToolDefinition[] FileTools =
    [
        Def("fs_read_file",
            "Read the contents of a file. Path must be absolute.",
            """{"type":"object","properties":{"path":{"type":"string","description":"Absolute file path"}},"required":["path"]}"""),
        Def("fs_write_file",
            "Write content to a file. Creates parent directories if needed. Path must be absolute.",
            """{"type":"object","properties":{"path":{"type":"string","description":"Absolute file path"},"content":{"type":"string","description":"File content to write"}},"required":["path","content"]}"""),
        Def("fs_list_directory",
            "List files and directories at a path with details (permissions, size, dates).",
            """{"type":"object","properties":{"path":{"type":"string","description":"Absolute directory path"}},"required":["path"]}"""),
        Def("fs_search_files",
            "Search for files by name pattern (glob). Excludes node_modules and .git.",
            """{"type":"object","properties":{"pattern":{"type":"string","description":"Filename pattern (e.g. '*.qml', 'README*')"},"root":{"type":"string","description":"Directory to search in (optional, defaults to allowed root)"}},"required":["pattern"]}"""),
    ];

    // --- Date ---
    private static readonly Protocol.ToolDefinition[] DateTools =
    [
        Def("date_now",
            "Get the current date and time with timezone.",
            """{"type":"object","properties":{},"required":[]}"""),
        Def("date_info",
            "Get detailed information about a date: day of week, week number, day of year, leap year.",
            """{"type":"object","properties":{"date":{"type":"string","description":"Date in YYYY-MM-DD format"}},"required":["date"]}"""),
        Def("date_diff",
            "Calculate the number of days between two dates.",
            """{"type":"object","properties":{"date1":{"type":"string","description":"Start date in YYYY-MM-DD format"},"date2":{"type":"string","description":"End date in YYYY-MM-DD format"}},"required":["date1","date2"]}"""),
        Def("date_add",
            "Add or subtract days from a date. Use negative days to subtract.",
            """{"type":"object","properties":{"date":{"type":"string","description":"Starting date in YYYY-MM-DD format"},"days":{"type":"integer","description":"Number of days to add (negative to subtract)"}},"required":["date","days"]}"""),
    ];
}
