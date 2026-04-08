using System.Diagnostics;
using System.Text.RegularExpressions;

namespace HyprChat.Services;

/// <summary>
/// Shell command execution via kitty remote control.
/// Spawns kitty with a postcmd hook; uses inotifywait for completion detection.
/// Mirrors the ShellService.qml approach identically.
/// </summary>
public sealed partial class ShellExecutor : IDisposable
{
    private const int MaxSpawnRetries = 3;

    private readonly string shell;
    private readonly string workDir;
    private readonly string socketPath = "/tmp/hyprchat-kitty.sock";
    private readonly string signalFile = "/tmp/hyprchat-done";

    private Process? terminalProcess;
    private Process? watchProcess;
    private readonly SemaphoreSlim execLock = new(1, 1);
    private TaskCompletionSource<bool>? commandDone;
    private int spawnFailCount;

    public ShellExecutor()
    {
        this.shell = Environment.GetEnvironmentVariable("SHELL") ?? "/bin/bash";
        this.workDir = Environment.GetEnvironmentVariable("HOME") ?? "/tmp";
    }

    public async Task InitializeAsync()
    {
        // Clean up signal file
        File.Delete(this.signalFile);
        await File.WriteAllTextAsync(this.signalFile, "");

        this.StartWatcher();
    }

    public async Task<string> ExecAsync(string command, CancellationToken ct = default)
    {
        await this.execLock.WaitAsync(ct);
        try
        {
            await this.EnsureTerminalAsync();

            // Snapshot buffer before
            var before = await this.KittyGetTextAsync();

            // Create completion signal
            this.commandDone = new TaskCompletionSource<bool>();

            // Send command
            await this.KittySendTextAsync(command + "\n");

            // Wait for postcmd hook to fire (with timeout)
            using var timeoutCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
            timeoutCts.CancelAfter(TimeSpan.FromSeconds(30));
            try
            {
                await this.commandDone.Task.WaitAsync(timeoutCts.Token);
            }
            catch (OperationCanceledException) when (timeoutCts.IsCancellationRequested && !ct.IsCancellationRequested)
            {
                return "Command timed out after 30 seconds.";
            }

            // Small delay for output to settle
            await Task.Delay(300, ct);

            // Snapshot buffer after
            var after = await this.KittyGetTextAsync();

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
            this.commandDone = null;
            this.execLock.Release();
        }
    }

    public async Task<string> ExecBackgroundAsync(string command, CancellationToken ct = default)
    {
        await this.execLock.WaitAsync(ct);
        try
        {
            await this.EnsureTerminalAsync();
            await this.KittySendTextAsync(command + "\n");
            return "Command sent to terminal in background.";
        }
        finally
        {
            this.execLock.Release();
        }
    }

    // --- Terminal management ---

    private async Task EnsureTerminalAsync()
    {
        if (this.terminalProcess is { HasExited: false }) return;

        if (this.spawnFailCount >= MaxSpawnRetries)
            throw new InvalidOperationException("Failed to spawn terminal.");

        this.spawnFailCount = 0;

        // Build shell init command with postcmd hook
        string initCmd;
        if (this.shell.Contains("fish"))
            initCmd = $"function __hyprchat_postcmd --on-event fish_postexec; echo done > '{this.signalFile}'; end";
        else if (this.shell.Contains("zsh"))
            initCmd = $"precmd() {{ echo done > '{this.signalFile}'; }}";
        else
            initCmd = "PROMPT_COMMAND='echo done > \"" + this.signalFile + "\";'\"${PROMPT_COMMAND}\"";
        var initFile = this.signalFile + ".init";
        await File.WriteAllTextAsync(initFile, initCmd + "\n");

        // Build shell command to source init
        string shellCmd;
        if (this.shell.Contains("fish"))
            shellCmd = $"{this.shell} -C 'source {initFile}'";
        else if (this.shell.Contains("zsh"))
            shellCmd = $"{this.shell} -c 'source {initFile}; exec {this.shell}'";
        else
            shellCmd = $"{this.shell} --rcfile <(cat ~/.bashrc {initFile} 2>/dev/null)";

        this.terminalProcess = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "setsid",
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };
        this.terminalProcess.StartInfo.ArgumentList.Add("kitty");
        this.terminalProcess.StartInfo.ArgumentList.Add("--class");
        this.terminalProcess.StartInfo.ArgumentList.Add("hyprchat-shell");
        this.terminalProcess.StartInfo.ArgumentList.Add("--title");
        this.terminalProcess.StartInfo.ArgumentList.Add("HyprChat Shell");
        this.terminalProcess.StartInfo.ArgumentList.Add("--listen-on");
        this.terminalProcess.StartInfo.ArgumentList.Add($"unix:{this.socketPath}");
        this.terminalProcess.StartInfo.ArgumentList.Add("--override");
        this.terminalProcess.StartInfo.ArgumentList.Add("allow_remote_control=yes");
        this.terminalProcess.StartInfo.ArgumentList.Add("--directory");
        this.terminalProcess.StartInfo.ArgumentList.Add(this.workDir);
        this.terminalProcess.StartInfo.ArgumentList.Add("-e");
        this.terminalProcess.StartInfo.ArgumentList.Add("bash");
        this.terminalProcess.StartInfo.ArgumentList.Add("-c");
        this.terminalProcess.StartInfo.ArgumentList.Add(shellCmd);

        this.terminalProcess.EnableRaisingEvents = true;
        this.terminalProcess.Exited += (_, _) =>
        {
            this.spawnFailCount++;
            this.commandDone?.TrySetResult(false);
        };
        this.terminalProcess.Start();

        // Wait for kitty to be ready
        await Task.Delay(2000);
    }

    private void StartWatcher()
    {
        this.watchProcess?.Kill();
        this.watchProcess?.Dispose();

        this.watchProcess = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "bash",
                Arguments = $"-c \"while inotifywait -q -e close_write '{this.signalFile}' 2>/dev/null; do echo DONE; done\"",
                RedirectStandardOutput = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };
        this.watchProcess.Start();

        // Read watch output in background
        _ = Task.Run(async () =>
        {
            try
            {
                while (true)
                {
                    var line = await this.watchProcess.StandardOutput.ReadLineAsync();
                    if (line is null) break;
                    if (line.Contains("DONE"))
                        this.commandDone?.TrySetResult(true);
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
        proc.StartInfo.ArgumentList.Add($"unix:{this.socketPath}");
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
        proc.StartInfo.ArgumentList.Add($"unix:{this.socketPath}");
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
        this.watchProcess?.Kill();
        this.watchProcess?.Dispose();
        this.terminalProcess?.Kill();
        this.terminalProcess?.Dispose();
        this.execLock.Dispose();

        // Cleanup temp files
        try { File.Delete(this.socketPath); } catch { }

        try { File.Delete(this.signalFile); } catch { }

        try { File.Delete(this.signalFile + ".init"); } catch { }
    }
}
