using System.Diagnostics;

namespace HyprChat.Services;

/// <summary>
/// Read/write file access scoped to allowed root directories.
/// Replaces FileService.qml — uses direct System.IO instead of subprocess.
/// </summary>
public sealed class FileService
{
    public string AllowedRoot { get; set; } = "/";

    public async Task<string> ReadFileAsync(string path, CancellationToken ct = default)
    {
        if (!IsAllowed(path))
            return $"BLOCKED: Path '{path}' is outside the allowed root '{AllowedRoot}'.";

        try
        {
            if (!File.Exists(path))
                return $"Error reading file: No such file: {path}";

            var content = await File.ReadAllTextAsync(path, ct);
            if (content.Length > 50000)
            {
                content = content[..25000] +
                          $"\n\n[... truncated {content.Length - 50000} chars ...]\n\n" +
                          content[^25000..];
            }
            return content.Length > 0 ? content : "(empty file)";
        }
        catch (Exception ex)
        {
            return $"Error reading file: {ex.Message}";
        }
    }

    public async Task<string> WriteFileAsync(string path, string content, CancellationToken ct = default)
    {
        if (!IsAllowed(path))
            return $"BLOCKED: Path '{path}' is outside the allowed root '{AllowedRoot}'.";

        try
        {
            var dir = Path.GetDirectoryName(path);
            if (dir is not null) Directory.CreateDirectory(dir);

            await File.WriteAllTextAsync(path, content, ct);
            return "File written successfully.";
        }
        catch (Exception ex)
        {
            return $"Error writing file: {ex.Message}";
        }
    }

    public async Task<string> ListDirectoryAsync(string path, CancellationToken ct = default)
    {
        if (!IsAllowed(path))
            return $"BLOCKED: Path '{path}' is outside the allowed root '{AllowedRoot}'.";

        try
        {
            // Use ls for consistent output format matching the original
            using var proc = new Process();
            proc.StartInfo = new ProcessStartInfo
            {
                FileName = "ls",
                ArgumentList = { "-la", "--color=never", path },
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            proc.Start();
            var output = await proc.StandardOutput.ReadToEndAsync(ct);
            await proc.WaitForExitAsync(ct);

            if (output.Length > 10000)
                output = output[..10000] + "\n[... truncated]";
            return output.Length > 0 ? output : "(empty directory)";
        }
        catch (Exception ex)
        {
            return $"Error listing directory: {ex.Message}";
        }
    }

    public async Task<string> SearchFilesAsync(string pattern, string searchRoot, CancellationToken ct = default)
    {
        var root = string.IsNullOrEmpty(searchRoot) ? AllowedRoot : searchRoot;
        if (!IsAllowed(root))
            return $"BLOCKED: Path '{root}' is outside the allowed root '{AllowedRoot}'.";

        try
        {
            using var proc = new Process();
            proc.StartInfo = new ProcessStartInfo
            {
                FileName = "find",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };
            proc.StartInfo.ArgumentList.Add(root);
            proc.StartInfo.ArgumentList.Add("-name");
            proc.StartInfo.ArgumentList.Add(pattern);
            proc.StartInfo.ArgumentList.Add("-not");
            proc.StartInfo.ArgumentList.Add("-path");
            proc.StartInfo.ArgumentList.Add("*/node_modules/*");
            proc.StartInfo.ArgumentList.Add("-not");
            proc.StartInfo.ArgumentList.Add("-path");
            proc.StartInfo.ArgumentList.Add("*/.git/*");

            proc.Start();
            var output = await proc.StandardOutput.ReadToEndAsync(ct);
            await proc.WaitForExitAsync(ct);

            // Limit results
            var lines = output.Split('\n', StringSplitOptions.RemoveEmptyEntries);
            if (lines.Length > 50)
                output = string.Join('\n', lines.Take(50)) + "\n[... more results truncated]";

            return output.TrimEnd().Length > 0 ? output.TrimEnd() : "No files found matching the pattern.";
        }
        catch (Exception ex)
        {
            return $"Error searching files: {ex.Message}";
        }
    }

    private bool IsAllowed(string path)
    {
        if (string.IsNullOrEmpty(path)) return false;
        if (path.Contains("..")) return false;
        if (!path.StartsWith('/')) return false;

        var normalized = path.Replace("//", "/").TrimEnd('/');
        var rootNorm = AllowedRoot.Replace("//", "/").TrimEnd('/');
        if (string.IsNullOrEmpty(rootNorm)) rootNorm = "/";

        return rootNorm == "/" || normalized.StartsWith(rootNorm, StringComparison.Ordinal);
    }
}
