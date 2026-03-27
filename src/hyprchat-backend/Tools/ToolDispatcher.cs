using System.Text.Json;
using HyprChat.Services;

namespace HyprChat.Tools;

/// <summary>
/// Routes tool calls to the appropriate handler and returns the result string.
/// All tools are synchronous from the caller's perspective (async internally).
/// </summary>
public sealed class ToolDispatcher
{
  private readonly MemoryStore _memory;
  private readonly FileService _files;
  private readonly WebService _web;
  private readonly ShellExecutor _shell;

  public ToolDispatcher(MemoryStore memory, FileService files, WebService web, ShellExecutor shell)
  {
    _memory = memory;
    _files = files;
    _web = web;
    _shell = shell;
  }

  public async Task<string> ExecuteAsync(string name, string argumentsJson, CancellationToken ct = default)
  {
    try
    {
      var args = string.IsNullOrEmpty(argumentsJson) || argumentsJson == "null"
          ? new Dictionary<string, JsonElement>()
          : JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(argumentsJson,
              Protocol.HyprChatJsonContext.Default.DictionaryStringJsonElement)
            ?? [];

      return name switch
      {
        // Memory (sync)
        "memory_list_topics" => MemoryListTopics(),
        "memory_read" => MemoryRead(args),
        "memory_append" => MemoryAppend(args),
        "memory_edit" => MemoryEdit(args),
        "memory_search" => MemorySearch(args),
        "memory_reorganize" => MemoryReorganize(args),
        "memory_delete" => MemoryDelete(args),

        // Date (sync)
        "date_now" => DateNow(),
        "date_info" => DateInfo(args),
        "date_diff" => DateDiff(args),
        "date_add" => DateAdd(args),

        // File (async)
        "fs_read_file" => await _files.ReadFileAsync(GetStr(args, "path"), ct),
        "fs_write_file" => await _files.WriteFileAsync(GetStr(args, "path"), GetStr(args, "content"), ct),
        "fs_list_directory" => await _files.ListDirectoryAsync(GetStr(args, "path"), ct),
        "fs_search_files" => await _files.SearchFilesAsync(GetStr(args, "pattern"), GetStr(args, "root", ""), ct),

        // Web (async)
        "web_search" => await _web.SearchAsync(GetStr(args, "query"), ct),
        "web_read_page" => await _web.FetchPageAsync(GetStr(args, "url"), ct),

        // Shell (async)
        "shell_exec" => await _shell.ExecAsync(GetStr(args, "command"), ct),
        "shell_exec_background" => await _shell.ExecBackgroundAsync(GetStr(args, "command"), ct),

        _ => $"Unknown tool: {name}"
      };
    }
    catch (Exception ex)
    {
      return $"Tool error: {ex.Message}";
    }
  }

  // --- Memory ---

  private string MemoryListTopics()
  {
    var topics = _memory.ListTopics();
    return topics.Count == 0
        ? "No memory topics found."
        : "Available topics:\n" + string.Join("\n", topics);
  }

  private string MemoryRead(Dictionary<string, JsonElement> args)
  {
    var topic = GetStr(args, "topic");
    var content = _memory.ReadTopic(topic);
    return string.IsNullOrEmpty(content)
        ? $"Topic '{topic}' is empty or does not exist."
        : content;
  }

  private string MemoryDelete(Dictionary<string, JsonElement> args)
  {
      var topic = GetStr(args, "topic");
      _memory.DeleteTopic(topic);
      return $"Deleted topic '{topic}'.";
  }

  private string MemoryAppend(Dictionary<string, JsonElement> args)
      => _memory.AppendTopic(GetStr(args, "topic"), GetStr(args, "content"));

  private string MemoryEdit(Dictionary<string, JsonElement> args)
      => _memory.EditTopic(GetStr(args, "topic"), GetStr(args, "content"));

  private string MemorySearch(Dictionary<string, JsonElement> args)
  {
    var results = _memory.Search(GetStr(args, "query"));
    if (results.Count == 0) return $"No results for '{GetStr(args, "query")}'.";
    return string.Join("\n\n", results.Select(r => $"### {r.Topic}\n{r.Matches}")).Trim();
  }

  private string MemoryReorganize(Dictionary<string, JsonElement> args)
  {
    var source = GetStr(args, "source_topic");
    if (string.IsNullOrEmpty(source))
      return "Error: memory_reorganize requires source_topic and subtopics array";

    if (!args.TryGetValue("subtopics", out var subtopicsEl) || subtopicsEl.ValueKind != JsonValueKind.Array)
      return "Error: memory_reorganize requires source_topic and subtopics array";

    var subtopics = new List<(string Name, string Content)>();
    foreach (var item in subtopicsEl.EnumerateArray())
    {
      var name = item.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
      var content = item.TryGetProperty("content", out var c) ? c.GetString() ?? "" : "";
      subtopics.Add((name, content));
    }

    return _memory.ReorganizeTopic(source, subtopics);
  }

  // --- Date ---

  private static string DateNow()
  {
    var now = DateTimeOffset.Now;
    return $"{now:O} ({now:dddd})";
  }

  private static string DateInfo(Dictionary<string, JsonElement> args)
  {
    if (!DateTimeOffset.TryParse(GetStr(args, "date"), out var d))
      return $"Error: invalid date '{GetStr(args, "date")}'. Use YYYY-MM-DD format.";

    var y = d.Year;
    var dayOfYear = d.DayOfYear;
    var isLeap = DateTime.IsLeapYear(y);
    var daysInYear = isLeap ? 366 : 365;
    var cal = System.Globalization.CultureInfo.InvariantCulture.Calendar;
    var week = cal.GetWeekOfYear(d.DateTime, System.Globalization.CalendarWeekRule.FirstFourDayWeek,
        DayOfWeek.Monday);

    return $"Date: {d:yyyy-MM-dd}\n" +
           $"Day of week: {d:dddd}\n" +
           $"Day of year: {dayOfYear}/{daysInYear}\n" +
           $"ISO week: {week}\n" +
           $"Leap year: {(isLeap ? "yes" : "no")}";
  }

  private static string DateDiff(Dictionary<string, JsonElement> args)
  {
    if (!DateTimeOffset.TryParse(GetStr(args, "date1"), out var d1))
      return $"Error: invalid date1 '{GetStr(args, "date1")}'. Use YYYY-MM-DD format.";
    if (!DateTimeOffset.TryParse(GetStr(args, "date2"), out var d2))
      return $"Error: invalid date2 '{GetStr(args, "date2")}'. Use YYYY-MM-DD format.";

    var diff = (int)(d2.Date - d1.Date).TotalDays;
    var abs = Math.Abs(diff);
    return $"From {d1:yyyy-MM-dd} to {d2:yyyy-MM-dd}:\n" +
           $"Days: {diff}\n" +
           $"({abs / 7} weeks and {abs % 7} days)";
  }

  private static string DateAdd(Dictionary<string, JsonElement> args)
  {
    if (!DateTimeOffset.TryParse(GetStr(args, "date"), out var d))
      return $"Error: invalid date '{GetStr(args, "date")}'. Use YYYY-MM-DD format.";
    if (!args.TryGetValue("days", out var daysEl))
      return "Error: missing 'days' parameter.";
    var days = daysEl.ValueKind == JsonValueKind.Number ? daysEl.GetInt32() : int.Parse(daysEl.GetString() ?? "0");
    var result = d.AddDays(days);
    return $"{result:yyyy-MM-dd} ({result:dddd})";
  }

  // --- Helpers ---

  private static string GetStr(Dictionary<string, JsonElement> args, string key, string def = "")
  {
    if (args.TryGetValue(key, out var el) && el.ValueKind == JsonValueKind.String)
      return el.GetString() ?? def;
    return def;
  }
}
