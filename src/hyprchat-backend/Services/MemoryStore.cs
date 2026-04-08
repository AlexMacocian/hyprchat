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
    private readonly string memoryDir;
    private string encryptionKey = "";
    private readonly Dictionary<string, string> cache = [];
    private readonly SortedSet<string> topicNames = [];
    private readonly SemaphoreSlim writeLock = new(1, 1);

    private const string EncHeader = "HYPRCHAT:v1:aes-256-cbc";

    public int SplitThreshold { get; set; } = 200;
    public bool IsReady => this.encryptionKey.Length > 0;

    public MemoryStore(string? configDir = null)
    {
        var xdg = Environment.GetEnvironmentVariable("XDG_CONFIG_HOME");
        var home = Environment.GetEnvironmentVariable("HOME") ?? "~";
        var baseDir = string.IsNullOrEmpty(xdg) ? Path.Combine(home, ".config") : xdg;
        this.memoryDir = Path.Combine(configDir ?? baseDir, "hyprchat", "memory");
    }

    public async Task InitializeAsync()
    {
        Directory.CreateDirectory(this.memoryDir);

        // Look up encryption key from keyring
        this.encryptionKey = await RunProcessAsync("secret-tool", "lookup service hyprchat account memory_key");
        this.encryptionKey = this.encryptionKey.Trim();

        if (this.encryptionKey.Length != 64)
        {
            // Generate new key
            this.encryptionKey = (await RunProcessAsync("openssl", "rand -hex 32")).Trim();

            // Store in keyring
            await RunProcessWithStdinAsync(
                "bash", "-c",
                $"printf '%s' '{this.encryptionKey}' | secret-tool store --label='HyprChat Memory Key' service hyprchat account memory_key",
                null);
        }

        await this.LoadAllTopicsAsync();
    }

    private async Task LoadAllTopicsAsync()
    {
        var files = Directory.GetFiles(this.memoryDir, "*.md.enc", SearchOption.AllDirectories);

        foreach (var file in files)
        {
            var relativePath = Path.GetRelativePath(this.memoryDir, file);
            var topic = relativePath.Replace(".md.enc", "");

            try
            {
                var content = await this.DecryptFileAsync(file);
                this.cache[topic] = content;
                this.topicNames.Add(topic);
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
            if (newlineIdx < 0)
            {
                return "";
            }

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
                $"enc -d -aes-256-cbc -pbkdf2 -in {tempIn} -pass pass:{this.encryptionKey}");
        }
        finally
        {
            File.Delete(tempIn);
        }
    }

    // --- Public API ---

    public List<string> ListTopics() => [.. this.topicNames];

    public string ReadTopic(string topic)
        => this.cache.TryGetValue(topic, out var content) ? content : "";

    public string AppendTopic(string topic, string content)
    {
        if (!IsValidTopic(topic)) return "Error: invalid topic name.";

        var existing = this.cache.GetValueOrDefault(topic, "");
        var separator = existing.Length > 0 ? "\n\n" : "";
        this.cache[topic] = existing + separator + content;
        this.topicNames.Add(topic);

        _ = this.PersistTopicAsync(topic);

        var lines = this.cache[topic].Split('\n').Length;
        if (lines > this.SplitThreshold)
        {
            return $"Appended to '{topic}'. WARNING: {topic} is now {lines} lines (threshold: {this.SplitThreshold}). Consider using memory_reorganize to split it into subtopics.";
        }

        return $"Appended to '{topic}'.";
    }

    public string EditTopic(string topic, string content)
    {
        if (!IsValidTopic(topic))
        {
            return "Error: invalid topic name.";
        }

        this.cache[topic] = content;
        this.topicNames.Add(topic);

        _ = this.PersistTopicAsync(topic);

        var lines = content.Split('\n').Length;
        if (lines > this.SplitThreshold)
        {
            return $"Saved '{topic}'. WARNING: {topic} is now {lines} lines (threshold: {this.SplitThreshold}). Consider using memory_reorganize to split it into subtopics.";
        }

        return $"Saved '{topic}'.";
    }

    public void DeleteTopic(string topic)
    {
        if (!IsValidTopic(topic))
        {
            return;
        }

        this.cache.Remove(topic);
        this.topicNames.Remove(topic);

        var filePath = Path.Combine(this.memoryDir, topic + ".md.enc");
        if (File.Exists(filePath))
        {
            File.Delete(filePath);
        }
    }

    public string ReorganizeTopic(string sourceTopic, List<(string Name, string Content)> subtopics)
    {
        if (!IsValidTopic(sourceTopic)) return "Error: invalid topic name.";

        foreach (var (name, content) in subtopics)
        {
            if (!IsValidTopic(name)) continue;
            var fullName = $"{sourceTopic}/{name}";
            this.cache[fullName] = content;
            this.topicNames.Add(fullName);

            // Ensure subdirectory exists
            var dir = Path.Combine(this.memoryDir, sourceTopic);
            Directory.CreateDirectory(dir);

            _ = this.PersistTopicAsync(fullName);
        }

        // Delete original
        this.cache.Remove(sourceTopic);
        this.topicNames.Remove(sourceTopic);
        var origFile = Path.Combine(this.memoryDir, sourceTopic + ".md.enc");
        if (File.Exists(origFile))
        {
            File.Delete(origFile);
        }

        var names = subtopics.Select(s => $"{sourceTopic}/{s.Name}");
        return $"Reorganized '{sourceTopic}' into {subtopics.Count} subtopics: {string.Join(", ", names)}";
    }

    public List<SearchResult> Search(string query)
    {
        var q = query.ToLowerInvariant();
        var results = new List<SearchResult>();

        foreach (var topic in this.topicNames)
        {
            var content = this.cache.GetValueOrDefault(topic, "");
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
        await this.writeLock.WaitAsync();
        try
        {
            var content = this.cache.GetValueOrDefault(topic, "");
            var filePath = Path.Combine(this.memoryDir, topic + ".md.enc");
            var dir = Path.GetDirectoryName(filePath);
            if (dir is not null) Directory.CreateDirectory(dir);

            // Write plaintext to temp, encrypt, prepend header
            var tempPlain = Path.GetTempFileName();
            var tempEnc = Path.GetTempFileName();
            try
            {
                await File.WriteAllTextAsync(tempPlain, content);

                await RunProcessAsync("openssl",
                    $"enc -aes-256-cbc -pbkdf2 -in {tempPlain} -out {tempEnc} -pass pass:{this.encryptionKey}");

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
            this.writeLock.Release();
        }
    }

    // --- Validation ---

    private static bool IsValidTopic(string name)
    {
        if (string.IsNullOrEmpty(name))
        {
            return false;
        }

        if (name.Contains(".."))
        {
            return false;
        }

        if (name.StartsWith('/') || name.EndsWith('/'))
        {
            return false;
        }

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
