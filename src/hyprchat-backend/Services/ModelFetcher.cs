using System.Text.Json;
using HyprChat.Protocol;

namespace HyprChat.Services;

/// <summary>
/// Fetches available models from backend APIs.
/// Handles Copilot token exchange, OpenAI, and Ollama model listing.
/// </summary>
public sealed class ModelFetcher
{
    private readonly HttpClient _http;
    private readonly RpcTransport _transport;

    // Copilot headers matching VS Code / avante.nvim
    private static readonly (string Name, string Value)[] CopilotHeaders =
    [
        ("Editor-Version", "vscode/1.105.1"),
        ("Editor-Plugin-Version", "copilot-chat/0.26.7"),
        ("Copilot-Integration-Id", "vscode-chat"),
        ("User-Agent", "GitHubCopilotChat/0.26.7"),
    ];

    public ModelFetcher(HttpClient http, RpcTransport transport)
    {
        _http = http;
        _transport = transport;
    }

    public async Task<ModelListResult> FetchAsync(ModelFetchParams p, CancellationToken ct = default)
    {
        try
        {
            return p.Backend switch
            {
                "copilot" => await FetchCopilotAsync(p.ApiKey, p.CopilotApiBase, ct),
                "ollama" => await FetchOllamaAsync(p.ApiUrl, ct),
                "openai" => await FetchOpenAiAsync(p.ApiKey, ct),
                _ => new ModelListResult()
            };
        }
        catch (Exception ex)
        {
            Console.Error.WriteLine($"ModelFetcher error: {ex.Message}");
            return new ModelListResult();
        }
    }

    private async Task<ModelListResult> FetchCopilotAsync(string apiKeyOrOauth, string copilotApiBase, CancellationToken ct)
    {
        string sessionToken;
        string apiBase;

        if (!string.IsNullOrEmpty(copilotApiBase))
        {
            // Already have session token + API base — skip exchange
            sessionToken = apiKeyOrOauth;
            apiBase = copilotApiBase;
        }
        else
        {
            // Exchange OAuth token for session token
            using var tokenReq = new HttpRequestMessage(HttpMethod.Get,
                "https://api.github.com/copilot_internal/v2/token");
            tokenReq.Headers.TryAddWithoutValidation("Authorization", $"token {apiKeyOrOauth}");
            tokenReq.Headers.TryAddWithoutValidation("Accept", "application/json");

            using var tokenResp = await _http.SendAsync(tokenReq, ct);
            if (!tokenResp.IsSuccessStatusCode)
            {
                var body = await tokenResp.Content.ReadAsStringAsync(ct);
                if (body.Contains("expired", StringComparison.OrdinalIgnoreCase) ||
                    body.Contains("unauthorized", StringComparison.OrdinalIgnoreCase))
                {
                    _transport.SendSignal("models/tokenExpired");
                }
                return new ModelListResult();
            }

            var tokenJson = await tokenResp.Content.ReadAsStringAsync(ct);
            var tokenData = JsonSerializer.Deserialize(tokenJson, HyprChatJsonContext.Default.CopilotTokenResponse);
            if (tokenData is null || string.IsNullOrEmpty(tokenData.Token) ||
                string.IsNullOrEmpty(tokenData.Endpoints?.Api))
                return new ModelListResult();

            apiBase = tokenData.Endpoints.Api;
            sessionToken = tokenData.Token;

            _transport.SendNotification("models/copilotApiReady", new CopilotApiResult
            {
                ApiBase = apiBase,
                Token = sessionToken
            }, HyprChatJsonContext.Default.RpcNotificationCopilotApiResult);
        }

        // Step 2: Fetch models
        using var modelsReq = new HttpRequestMessage(HttpMethod.Get, $"{apiBase}/models");
        modelsReq.Headers.TryAddWithoutValidation("Authorization", $"Bearer {sessionToken}");
        modelsReq.Headers.TryAddWithoutValidation("Accept", "application/json");
        foreach (var (name, value) in CopilotHeaders)
            modelsReq.Headers.TryAddWithoutValidation(name, value);

        using var modelsResp = await _http.SendAsync(modelsReq, ct);
        var modelsJson = await modelsResp.Content.ReadAsStringAsync(ct);
        var modelsData = JsonSerializer.Deserialize(modelsJson, HyprChatJsonContext.Default.ModelsApiResponse);

        if (modelsData?.Data is null) return new ModelListResult();

        var chatModels = modelsData.Data
            .Where(m => m.Capabilities?.Type == "chat")
            .Where(m => !m.Id.EndsWith("-paygo"))
            .OrderBy(m => m.Name ?? m.Id)
            .ToList();

        // Detect duplicate names for disambiguation
        var nameCounts = chatModels
            .GroupBy(m => m.Name ?? m.Id)
            .ToDictionary(g => g.Key, g => g.Count());

        var result = new ModelListResult();
        foreach (var m in chatModels)
        {
            var displayName = m.Name ?? m.Id;
            if (nameCounts.GetValueOrDefault(displayName, 0) > 1)
                displayName = $"{displayName} ({m.Id})";

            var maxTokens = m.Capabilities?.Limits?.MaxPromptTokens ?? 128000;

            result.Models.Add(new ModelInfo
            {
                Id = m.Id,
                Name = displayName,
                MaxTokens = maxTokens
            });
        }

        return result;
    }

    private async Task<ModelListResult> FetchOllamaAsync(string apiUrl, CancellationToken ct)
    {
        var baseUrl = string.IsNullOrEmpty(apiUrl) ? "http://localhost:11434" : apiUrl;
        var json = await _http.GetStringAsync($"{baseUrl}/api/tags", ct);
        var data = JsonSerializer.Deserialize(json, HyprChatJsonContext.Default.ModelsApiResponse);

        var result = new ModelListResult();
        if (data?.Models is not null)
        {
            foreach (var m in data.Models)
                result.Models.Add(new ModelInfo { Id = m.Name, Name = m.Name });
        }
        return result;
    }

    private async Task<ModelListResult> FetchOpenAiAsync(string apiKey, CancellationToken ct)
    {
        using var req = new HttpRequestMessage(HttpMethod.Get, "https://api.openai.com/v1/models");
        req.Headers.TryAddWithoutValidation("Authorization", $"Bearer {apiKey}");

        using var resp = await _http.SendAsync(req, ct);
        var json = await resp.Content.ReadAsStringAsync(ct);
        var data = JsonSerializer.Deserialize(json, HyprChatJsonContext.Default.ModelsApiResponse);

        var result = new ModelListResult();
        if (data?.Data is not null)
        {
            var chatModels = data.Data
                .Where(m => m.Id.Contains("gpt") || m.Id.Contains("o1") || m.Id.Contains("o3"))
                .OrderBy(m => m.Id);

            foreach (var m in chatModels)
                result.Models.Add(new ModelInfo { Id = m.Id, Name = m.Id });
        }
        return result;
    }
}
