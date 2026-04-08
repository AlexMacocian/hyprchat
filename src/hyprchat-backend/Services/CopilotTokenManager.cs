using System.Text.Json;
using HyprChat.Protocol;

namespace HyprChat.Services;

/// <summary>
/// Manages Copilot session tokens with automatic refresh.
/// Caches the session token and its expiry, re-exchanges from the OAuth
/// token (via keyring) when the session token is expired or about to expire.
/// On 401, transparently refreshes and returns a new token.
/// </summary>
public sealed class CopilotTokenManager(HttpClient http, RpcTransport transport)
{
    // Refresh 2 minutes before expiry
    private const long RefreshMarginSeconds = 120;

    private readonly HttpClient http = http;
    private readonly RpcTransport transport = transport;
    private readonly SemaphoreSlim semaphore = new(1, 1);

    private string? sessionToken;
    private string? apiBase;
    private long expiresAt; // Unix timestamp
    private bool tokenExpiredSignaled; // prevent re-signaling loop

    /// <summary>
    /// Gets a valid session token + API base, refreshing if needed.
    /// Returns (token, apiBase) or (null, null) if refresh fails.
    /// </summary>
    public async Task<(string? Token, string? ApiBase)> GetTokenAsync(CancellationToken ct = default)
    {
        if (this.IsValid())
        {
            return (this.sessionToken, this.apiBase);
        }

        return await this.RefreshTokenAsync(ct);
    }

    /// <summary>
    /// Forces a token refresh (e.g. after a 401). Thread-safe — concurrent
    /// callers wait for the same refresh rather than hammering the API.
    /// </summary>
    public async Task<(string? Token, string? ApiBase)> RefreshTokenAsync(CancellationToken ct = default)
    {
        await this.semaphore.WaitAsync(ct);
        try
        {
            // Double-check: another thread may have refreshed while we waited
            if (this.IsValid())
            {
                return (this.sessionToken, this.apiBase);
            }

            // Look up OAuth token from keyring
            var (found, oauthToken) = await KeyringService.LookupAsync("copilot_oauth");
            if (!found || string.IsNullOrEmpty(oauthToken))
            {
                Console.Error.WriteLine("CopilotTokenManager: no OAuth token in keyring");
                this.SignalTokenExpiredOnce();
                return (null, null);
            }

            // Try exchanging the OAuth token for a session token
            var result = await this.ExchangeOAuthAsync(oauthToken, ct);
            if (result.Token is not null)
            {
                return result;
            }

            // OAuth token may be expired — try refresh token
            Console.Error.WriteLine("CopilotTokenManager: OAuth exchange failed, trying refresh token...");
            var refreshResult = await this.TryRefreshOAuthAsync(ct);
            if (refreshResult.Token is not null)
            {
                return refreshResult;
            }

            // All failed — signal UI to re-login
            Console.Error.WriteLine("CopilotTokenManager: all token refresh attempts failed");
            this.SignalTokenExpiredOnce();
            return (null, null);
        }
        finally
        {
            this.semaphore.Release();
        }
    }

    /// <summary>
    /// Invalidates the cached session token so the next GetTokenAsync forces a refresh.
    /// </summary>
    public void Invalidate()
    {
        this.expiresAt = 0;
        this.sessionToken = null;
    }

    private bool IsValid()
    {
        return this.sessionToken is not null
            && this.apiBase is not null
            && DateTimeOffset.UtcNow.ToUnixTimeSeconds() < this.expiresAt - RefreshMarginSeconds;
    }

    private void SignalTokenExpiredOnce()
    {
        if (this.tokenExpiredSignaled) return;
        this.tokenExpiredSignaled = true;
        this.transport.SendSignal("chat/tokenExpired");
    }

    private async Task<(string? Token, string? ApiBase)> ExchangeOAuthAsync(string oauthToken, CancellationToken ct)
    {
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get,
                "https://api.github.com/copilot_internal/v2/token");
            req.Headers.TryAddWithoutValidation("Authorization", $"token {oauthToken}");
            req.Headers.TryAddWithoutValidation("Accept", "application/json");
            req.Headers.TryAddWithoutValidation("User-Agent", "GitHubCopilotChat/0.26.7");

            using var resp = await this.http.SendAsync(req, ct);
            if (!resp.IsSuccessStatusCode)
            {
                var body = await resp.Content.ReadAsStringAsync(ct);
                Console.Error.WriteLine($"CopilotTokenManager: exchange failed HTTP {(int)resp.StatusCode}: {body[..Math.Min(body.Length, 200)]}");
                return (null, null);
            }

            var json = await resp.Content.ReadAsStringAsync(ct);
            var data = JsonSerializer.Deserialize(json, HyprChatJsonContext.Default.CopilotTokenResponse);
            if (data is null || string.IsNullOrEmpty(data.Token) || string.IsNullOrEmpty(data.Endpoints?.Api))
                return (null, null);

            this.sessionToken = data.Token;
            this.apiBase = data.Endpoints.Api;
            this.expiresAt = data.ExpiresAt;

            Console.Error.WriteLine($"CopilotTokenManager: session token refreshed, expires_at={this.expiresAt}");

            // Reset the signaled flag — we have a valid token now
            this.tokenExpiredSignaled = false;

            // Notify QML so it updates apiKey/apiUrl
            this.transport.SendNotification("models/copilotApiReady", new CopilotApiResult
            {
                ApiBase = this.apiBase,
                Token = this.sessionToken
            }, HyprChatJsonContext.Default.RpcNotificationCopilotApiResult);

            return (this.sessionToken, this.apiBase);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"CopilotTokenManager: exchange error: {ex.Message}");
            return (null, null);
        }
    }

    private async Task<(string? Token, string? ApiBase)> TryRefreshOAuthAsync(CancellationToken ct)
    {
        try
        {
            var (found, refreshToken) = await KeyringService.LookupAsync("copilot_refresh");
            if (!found || string.IsNullOrEmpty(refreshToken))
            {
                Console.Error.WriteLine("CopilotTokenManager: no refresh token in keyring");
                return (null, null);
            }

            using var req = new HttpRequestMessage(HttpMethod.Post,
                "https://github.com/login/oauth/access_token");
            req.Headers.TryAddWithoutValidation("Accept", "application/json");
            req.Headers.TryAddWithoutValidation("User-Agent", "GitHubCopilotChat/0.26.7");
            req.Content = new FormUrlEncodedContent(new Dictionary<string, string>
            {
                ["client_id"] = "Iv1.b507a08c87ecfe98",
                ["grant_type"] = "refresh_token",
                ["refresh_token"] = refreshToken,
            });

            using var resp = await this.http.SendAsync(req, ct);
            var json = await resp.Content.ReadAsStringAsync(ct);
            var data = JsonSerializer.Deserialize(json, HyprChatJsonContext.Default.OAuthTokenResponse);

            if (data is null || string.IsNullOrEmpty(data.AccessToken))
            {
                Console.Error.WriteLine($"CopilotTokenManager: OAuth refresh failed: {data?.Error}");
                return (null, null);
            }

            Console.Error.WriteLine("CopilotTokenManager: OAuth token refreshed via refresh_token");

            // Store new tokens in keyring
            await KeyringService.StoreAsync("copilot_oauth", data.AccessToken);
            if (!string.IsNullOrEmpty(data.RefreshToken))
            {
                await KeyringService.StoreAsync("copilot_refresh", data.RefreshToken);
            }

            // Now exchange the new OAuth token for a session token
            return await this.ExchangeOAuthAsync(data.AccessToken, ct);
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"CopilotTokenManager: refresh error: {ex.Message}");
            return (null, null);
        }
    }
}
