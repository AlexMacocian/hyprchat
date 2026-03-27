using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace HyprChat.Services;

/// <summary>
/// Encrypted persistent memory with topic-based organization.
/// AES-256-CBC with PBKDF2, key stored in system keyring via secret-tool.
/// Compatible with the existing QML MemoryService file format.
/// </summary>
public sealed partial class MemoryStore
{
    private readonly string _memoryDir;
    private string _encryptionKey = "";
    private readonly Dictionary<string, string> _cache = new();
    private readonly SortedSet<string> _topicNames = new();
    private readonly SemaphoreSlim _writeLock = new(1, 1);

    private const string EncHeader = "HYPRCHAT:v1:aes-256-cbc";

    public int SplitThreshold { get; set; } = 200;
    public bool IsReady => _encryptionKey.Length > 0;

    public MemoryStore(string? configDir = null)
    {
        var xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var home = Environment.GetEnvironmentVariable("HOME") ?? "~";
        var baseDir = string.IsNullOrEmpty(xdg) ? Path.Combine(home, ".config") : xdg;
        _memoryDir = Path.Combine(configDir ?? baseDir, "hyprchat", "memory");
    }

    public async Task InitializeAsync()
    {
        Directory.CreateDirectory(_memoryDir);

        // Look up encryption key from keyring
        _encryptionKey = await RunProcessAsync("secret-tool", "lookup service hyprchat account memory_key");
        _encryptionKey = _encryptionKey.Trim();

        if (_encryptionKey.Length != 64)
        {
            // Generate new key
            _encryptionKey = (await RunProcessAsync("openssl", "rand -hex 32")).Trim();

            // Store in keyring
            await RunProcessWithStdinAsync(
                "bash", "-c",
                $"printf '%s' '{_encryptionKey}' | secret-tool store --label='HyprChat Memory Key' service hyprchat account memory_key",
                null);
        }

        await LoadAllTopicsAsync();
    }

    private async Task LoadAllTopicsAsync()
    {
        var files = Directory.GetFiles(_memoryDir, "*.md.enc", SearchOption.AllDirectories);

        foreach (var file in files)
        {
            var relativePath = Path.GetRelativePath(_memoryDir, file);
            var topic = relativePath.Replace(".md.enc", "");

            try
            {
                var content = await DecryptFileAsync(file);
                _cache[topic] = content;
                _topicNames.Add(topic);
            }
            catch
            {
                // Skip files we can't decrypt
            }
        }
    }

    private async Task<string> DecryptFileAsync(string filePath)
    {
        var bytes = await File.ReadAllBytesAsync(filePath);
        var text = Encoding.UTF8.GetString(bytes);

        byte[] encryptedData;
        if (text.StartsWith("HYPRCHAT:"))
        {
            // Has header — skip first line
            var newlineIdx = text.IndexOf('\n');
            if (newlineIdx < 0) return "";
            encryptedData = bytes[(newlineIdx + 1)..];
        }
        else
        {
            encryptedData = bytes;
        }

        // Decrypt using openssl via stdin
        var tempIn = Path.GetTempFileName();
        try
        {
            await File.WriteAllBytesAsync(tempIn, encryptedData);
            return await RunProcessAsync("openssl",
                $"enc -d -aes-256-cbc -pbkdf2 -in {tempIn} -pass pass:{_encryptionKey}");
        }
        finally
        {
            File.Delete(tempIn);
        }
    }

    // --- Public API ---

    public List<string> ListTopics() => _topicNames.ToList();

    public string ReadTopic(string topic)
        => _cache.TryGetValue(topic, out var content) ? content : "";

    public string AppendTopic(string topic, string content)
    {
        if (!IsValidTopic(topic)) return "Error: invalid topic name.";

        var existing = _cache.GetValueOrDefault(topic, "");
        var separator = existing.Length > 0 ? "\n\n" : "";
        _cache[topic] = existing + separator + content;
        _topicNames.Add(topic);

        _ = PersistTopicAsync(topic);

        var lines = _cache[topic].Split('\n').Length;
        if (lines > SplitThreshold)
            return $"Appended to '{topic}'. WARNING: {topic} is now {lines} lines (threshold: {SplitThreshold}). Consider using memory_reorganize to split it into subtopics.";
        return $"Appended to '{topic}'.";
    }

    public string EditTopic(string topic, string content)
    {
        if (!IsValidTopic(topic)) return "Error: invalid topic name.";

        _cache[topic] = content;
        _topicNames.Add(topic);

        _ = PersistTopicAsync(topic);

        var lines = content.Split('\n').Length;
        if (lines > SplitThreshold)
            return $"Saved '{topic}'. WARNING: {topic} is now {lines} lines (threshold: {SplitThreshold}). Consider using memory_reorganize to split it into subtopics.";
        return $"Saved '{topic}'.";
    }

    public void DeleteTopic(string topic)
    {
        if (!IsValidTopic(topic)) return;
        _cache.Remove(topic);
        _topicNames.Remove(topic);

        var filePath = Path.Combine(_memoryDir, topic + ".md.enc");
        if (File.Exists(filePath)) File.Delete(filePath);
    }

    public string ReorganizeTopic(string sourceTopic, List<(string Name, string Content)> subtopics)
    {
        if (!IsValidTopic(sourceTopic)) return "Error: invalid topic name.";

        foreach (var (name, content) in subtopics)
        {
            if (!IsValidTopic(name)) continue;
            var fullName = $"{sourceTopic}/{name}";
            _cache[fullName] = content;
            _topicNames.Add(fullName);

            // Ensure subdirectory exists
            var dir = Path.Combine(_memoryDir, sourceTopic);
            Directory.CreateDirectory(dir);

            _ = PersistTopicAsync(fullName);
        }

        // Delete original
        _cache.Remove(sourceTopic);
        _topicNames.Remove(sourceTopic);
        var origFile = Path.Combine(_memoryDir, sourceTopic + ".md.enc");
        if (File.Exists(origFile)) File.Delete(origFile);

        var names = subtopics.Select(s => $"{sourceTopic}/{s.Name}");
        return $"Reorganized '{sourceTopic}' into {subtopics.Count} subtopics: {string.Join(", ", names)}";
    }

    public List<SearchResult> Search(string query)
    {
        var q = query.ToLowerInvariant();
        var results = new List<SearchResult>();

        foreach (var topic in _topicNames)
        {
            var content = _cache.GetValueOrDefault(topic, "");
            if (content.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                topic.Contains(q, StringComparison.OrdinalIgnoreCase))
            {
                var lines = content.Split('\n');
                var matches = lines.Where(l => l.Contains(q, StringComparison.OrdinalIgnoreCase))
                    .Take(5);
                results.Add(new SearchResult { Topic = topic, Matches = string.Join("\n", matches) });
            }
        }

        return results;
    }

    // --- Persist ---

    private async Task PersistTopicAsync(string topic)
    {
        await _writeLock.WaitAsync();
        try
        {
            var content = _cache.GetValueOrDefault(topic, "");
            var filePath = Path.Combine(_memoryDir, topic + ".md.enc");
            var dir = Path.GetDirectoryName(filePath);
            if (dir is not null) Directory.CreateDirectory(dir);

            // Write plaintext to temp, encrypt, prepend header
            var tempPlain = Path.GetTempFileName();
            var tempEnc = Path.GetTempFileName();
            try
            {
                await File.WriteAllTextAsync(tempPlain, content);

                await RunProcessAsync("openssl",
                    $"enc -aes-256-cbc -pbkdf2 -in {tempPlain} -out {tempEnc} -pass pass:{_encryptionKey}");

                // Write header + encrypted data
                await using var outStream = File.Create(filePath);
                var header = Encoding.UTF8.GetBytes(EncHeader + "\n");
                await outStream.WriteAsync(header);
                var encrypted = await File.ReadAllBytesAsync(tempEnc);
                await outStream.WriteAsync(encrypted);
            }
            finally
            {
                File.Delete(tempPlain);
                File.Delete(tempEnc);
            }
        }
        finally
        {
            _writeLock.Release();
        }
    }

    // --- Validation ---

    private static bool IsValidTopic(string name)
    {
        if (string.IsNullOrEmpty(name)) return false;
        if (name.Contains("..")) return false;
        if (name.StartsWith('/') || name.EndsWith('/')) return false;
        return TopicRegex().IsMatch(name);
    }

    [GeneratedRegex(@"^[a-zA-Z0-9_\/-]+$")]
    private static partial Regex TopicRegex();

    // --- Process helpers ---

    private static async Task<string> RunProcessAsync(string fileName, string arguments)
    {
        using var proc = new Process();
        proc.StartInfo = new ProcessStartInfo
        {
            FileName = fileName,
            Arguments = arguments,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        proc.Start();
        var output = await proc.StandardOutput.ReadToEndAsync();
        await proc.WaitForExitAsync();
        return output;
    }

    private static async Task RunProcessWithStdinAsync(string fileName, string arg1, string arg2, string? stdin)
    {
        using var proc = new Process();
        proc.StartInfo = new ProcessStartInfo
        {
            FileName = fileName,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = stdin != null
        };
        proc.StartInfo.ArgumentList.Add(arg1);
        proc.StartInfo.ArgumentList.Add(arg2);
        proc.Start();
        if (stdin != null)
        {
            await proc.StandardInput.WriteAsync(stdin);
            proc.StandardInput.Close();
        }
        await proc.WaitForExitAsync();
    }

    public sealed class SearchResult
    {
        public string Topic { get; set; } = "";
        public string Matches { get; set; } = "";
    }
}
