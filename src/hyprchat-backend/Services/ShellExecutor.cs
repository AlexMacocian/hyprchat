using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;

namespace HyprChat.Services;

/// <summary>
/// Shell command execution via kitty remote control.
/// Spawns kitty with a postcmd hook; uses inotifywait for completion detection.
/// Mirrors the ShellService.qml approach identically.
/// </summary>
public sealed partial class ShellExecutor : IDisposable
{
    private readonly string _shell;
    private readonly string _workDir;
    private readonly string _socketPath = "/tmp/hyprchat-kitty.sock";
    private readonly string _signalFile = "/tmp/hyprchat-done";

    private Process? _terminalProcess;
    private Process? _watchProcess;
    private readonly SemaphoreSlim _execLock = new(1, 1);
    private TaskCompletionSource<bool>? _commandDone;
    private int _spawnFailCount;
    private const int MaxSpawnRetries = 3;

    public ShellExecutor()
    {
        _shell = Environment.GetEnvironmentVariable("SHELL") ?? "/bin/bash";
        _workDir = Environment.GetEnvironmentVariable("HOME") ?? "/tmp";
    }

    public async Task InitializeAsync()
    {
        // Clean up signal file
        File.Delete(_signalFile);
        await File.WriteAllTextAsync(_signalFile, "");

        StartWatcher();
    }

    public async Task<string> ExecAsync(string command, CancellationToken ct = default)
    {
        await _execLock.WaitAsync(ct);
        try
        {
            await EnsureTerminalAsync();

            // Snapshot buffer before
            var before = await KittyGetTextAsync();

            // Create completion signal
            _commandDone = new TaskCompletionSource<bool>();

            // Send command
            await KittySendTextAsync(command + "\n");

            // Wait for postcmd hook to fire (with timeout)
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(30));
            try
            {
                await _commandDone.Task.WaitAsync(timeoutCts.Token);
            }
            catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested && !ct.IsCancellationRequested)
            {
                return "Command timed out after 30 seconds.";
            }

            // Small delay for output to settle
            await Task.Delay(300, ct);

            // Snapshot buffer after
            var after = await KittyGetTextAsync();

            // Diff
            var result = DiffBuffers(before, after);

            // Strip ANSI codes
            result = AnsiRegex().Replace(result, "");
            result = OscRegex().Replace(result, "");
            result = result.Replace("\r", "").Trim();

            // Truncate
            if (result.Length > 10000)
            {
                result = result[..5000] + "\n\n[... truncated ...]\n\n" + result[^5000..];
            }

            return result.Length > 0 ? result : "(no output)";
        }
        finally
        {
            _commandDone = null;
            _execLock.Release();
        }
    }

    public async Task<string> ExecBackgroundAsync(string command, CancellationToken ct = default)
    {
        await _execLock.WaitAsync(ct);
        try
        {
            await EnsureTerminalAsync();
            await KittySendTextAsync(command + "\n");
            return "Command sent to terminal in background.";
        }
        finally
        {
            _execLock.Release();
        }
    }

    // --- Terminal management ---

    private async Task EnsureTerminalAsync()
    {
        if (_terminalProcess is { HasExited: false }) return;

        if (_spawnFailCount >= MaxSpawnRetries)
            throw new InvalidOperationException("Failed to spawn terminal.");

        _spawnFailCount = 0;

        // Build shell init command with postcmd hook
        string initCmd;
        if (_shell.Contains("fish"))
            initCmd = $"function __hyprchat_postcmd --on-event fish_postexec; echo done > '{_signalFile}'; end";
        else if (_shell.Contains("zsh"))
            initCmd = $"precmd() {{ echo done > '{_signalFile}'; }}";
        else
            initCmd = "PROMPT_COMMAND='echo done > \"" + _signalFile + "\";'\"${PROMPT_COMMAND}\"";
        var initFile = _signalFile + ".init";
        await File.WriteAllTextAsync(initFile, initCmd + "\n");

        // Build shell command to source init
        string shellCmd;
        if (_shell.Contains("fish"))
            shellCmd = $"{_shell} -C 'source {initFile}'";
        else if (_shell.Contains("zsh"))
            shellCmd = $"{_shell} -c 'source {initFile}; exec {_shell}'";
        else
            shellCmd = $"{_shell} --rcfile <(cat ~/.bashrc {initFile} 2>/dev/null)";

        _terminalProcess = new Process();
        _terminalProcess.StartInfo = new ProcessStartInfo
        {
            FileName = "setsid",
            UseShellExecute = false,
            CreateNoWindow = true
        };
        _terminalProcess.StartInfo.ArgumentList.Add("kitty");
        _terminalProcess.StartInfo.ArgumentList.Add("--class");
        _terminalProcess.StartInfo.ArgumentList.Add("hyprchat-shell");
        _terminalProcess.StartInfo.ArgumentList.Add("--title");
        _terminalProcess.StartInfo.ArgumentList.Add("HyprChat Shell");
        _terminalProcess.StartInfo.ArgumentList.Add("--listen-on");
        _terminalProcess.StartInfo.ArgumentList.Add($"unix:{_socketPath}");
        _terminalProcess.StartInfo.ArgumentList.Add("--override");
        _terminalProcess.StartInfo.ArgumentList.Add("allow_remote_control=yes");
        _terminalProcess.StartInfo.ArgumentList.Add("--directory");
        _terminalProcess.StartInfo.ArgumentList.Add(_workDir);
        _terminalProcess.StartInfo.ArgumentList.Add("-e");
        _terminalProcess.StartInfo.ArgumentList.Add("bash");
        _terminalProcess.StartInfo.ArgumentList.Add("-c");
        _terminalProcess.StartInfo.ArgumentList.Add(shellCmd);

        _terminalProcess.EnableRaisingEvents = true;
        _terminalProcess.Exited += (_, _) =>
        {
            _spawnFailCount++;
            _commandDone?.TrySetResult(false);
        };
        _terminalProcess.Start();

        // Wait for kitty to be ready
        await Task.Delay(2000);
    }

    private void StartWatcher()
    {
        _watchProcess?.Kill();
        _watchProcess?.Dispose();

        _watchProcess = new Process();
        _watchProcess.StartInfo = new ProcessStartInfo
        {
            FileName = "bash",
            Arguments = $"-c \"while inotifywait -q -e close_write '{_signalFile}' 2>/dev/null; do echo DONE; done\"",
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        _watchProcess.Start();

        // Read watch output in background
        _ = Task.Run(async () =>
        {
            try
            {
                while (true)
                {
                    var line = await _watchProcess.StandardOutput.ReadLineAsync();
                    if (line is null) break;
                    if (line.Contains("DONE"))
                        _commandDone?.TrySetResult(true);
                }
            }
            catch { /* watcher ended */ }
        });
    }

    // --- Kitty remote control ---

    private async Task<string> KittyGetTextAsync()
    {
        using var proc = new Process();
        proc.StartInfo = new ProcessStartInfo
        {
            FileName = "kitty",
            RedirectStandardOutput = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        proc.StartInfo.ArgumentList.Add("@");
        proc.StartInfo.ArgumentList.Add("--to");
        proc.StartInfo.ArgumentList.Add($"unix:{_socketPath}");
        proc.StartInfo.ArgumentList.Add("get-text");
        proc.StartInfo.ArgumentList.Add("--extent");
        proc.StartInfo.ArgumentList.Add("all");

        proc.Start();
        var output = await proc.StandardOutput.ReadToEndAsync();
        await proc.WaitForExitAsync();
        return output;
    }

    private async Task KittySendTextAsync(string text)
    {
        using var proc = new Process();
        proc.StartInfo = new ProcessStartInfo
        {
            FileName = "kitty",
            UseShellExecute = false,
            CreateNoWindow = true
        };
        proc.StartInfo.ArgumentList.Add("@");
        proc.StartInfo.ArgumentList.Add("--to");
        proc.StartInfo.ArgumentList.Add($"unix:{_socketPath}");
        proc.StartInfo.ArgumentList.Add("send-text");
        proc.StartInfo.ArgumentList.Add("--");
        proc.StartInfo.ArgumentList.Add(text);

        proc.Start();
        await proc.WaitForExitAsync();
    }

    // --- Helpers ---

    private static string DiffBuffers(string before, string after)
    {
        if (before.Length > 0 && after.StartsWith(before))
            return after[before.Length..];

        var beforeLines = before.Split('\n');
        var afterLines = after.Split('\n');
        var startLine = 0;
        for (var i = 0; i < Math.Min(beforeLines.Length, afterLines.Length); i++)
        {
            if (beforeLines[i] == afterLines[i])
                startLine = i + 1;
            else
                break;
        }
        return string.Join('\n', afterLines.Skip(startLine));
    }

    [GeneratedRegex(@"\x1B\[[0-9;]*[a-zA-Z]")]
    private static partial Regex AnsiRegex();

    [GeneratedRegex(@"\x1B\][^\x07]*\x07")]
    private static partial Regex OscRegex();

    public void Dispose()
    {
        _watchProcess?.Kill();
        _watchProcess?.Dispose();
        _terminalProcess?.Kill();
        _terminalProcess?.Dispose();
        _execLock.Dispose();

        // Cleanup temp files
        try { File.Delete(_socketPath); } catch { }
        try { File.Delete(_signalFile); } catch { }
        try { File.Delete(_signalFile + ".init"); } catch { }
    }
}
