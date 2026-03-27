using System.Diagnostics;

namespace HyprChat.Services;

/// <summary>
/// Manages secrets in the system keyring via secret-tool (libsecret).
/// All entries use: service=hyprchat, account=<name>
/// </summary>
public static class KeyringService
{
    public static async Task<(bool Found, string Key)> LookupAsync(string account)
    {
        using var proc = new Process();
        proc.StartInfo = new ProcessStartInfo
        {
            FileName = "secret-tool",
            ArgumentList = { "lookup", "service", "hyprchat", "account", account },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        proc.Start();
        var output = await proc.StandardOutput.ReadToEndAsync();
        await proc.WaitForExitAsync();

        var key = output.Trim();
        return (key.Length > 0 && proc.ExitCode == 0, key);
    }

    public static async Task StoreAsync(string account, string key)
    {
        // Use base64 encoding to avoid shell escaping issues (matching QML approach)
        var b64 = Convert.ToBase64String(System.Text.Encoding.UTF8.GetBytes(key));

        using var proc = new Process();
        proc.StartInfo = new ProcessStartInfo
        {
            FileName = "bash",
            Arguments = $"-c \"echo -n {b64} | base64 -d | secret-tool store --label='HyprChat {account}' service hyprchat account {account}\"",
            UseShellExecute = false,
            CreateNoWindow = true
        };
        proc.Start();
        await proc.WaitForExitAsync();
    }

    public static async Task DeleteAsync(string account)
    {
        using var proc = new Process();
        proc.StartInfo = new ProcessStartInfo
        {
            FileName = "secret-tool",
            ArgumentList = { "clear", "service", "hyprchat", "account", account },
            UseShellExecute = false,
            CreateNoWindow = true
        };
        proc.Start();
        await proc.WaitForExitAsync();
    }
}
