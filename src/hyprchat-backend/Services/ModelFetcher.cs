using System.Text.Json;
using HyprChat.Protocol;

namespace HyprChat.Services;

/// <summary>
/// Fetches available models from backend APIs.
/// Handles Copilot token exchange, OpenAI, and Ollama model listing.
/// </summary>
public sealed class ModelFetcher(HttpClient http, RpcTransport transport, CopilotTokenManager copilotTokens)
{
    private readonly HttpClient http = http;
    private readonly RpcTransport transport = transport;
    private readonly CopilotTokenManager copilotTokens = copilotTokens;

    // Copilot headers matching VS Code / avante.nvim
    private static readonly (string Name, string Value)[] CopilotHeaders =
    [
        ("Editor-Version", "vscode/1.105.1"),
        ("Editor-Plugin-Version", "copilot-chat/0.26.7"),
        ("Copilot-Integration-Id", "vscode-chat"),
        ("User-Agent", "GitHubCopilotChat/0.26.7"),
    ];

    public async Task<ModelListResult> FetchAsync(ModelFetchParams p, CancellationToken ct = default)
    {
        try
        {
            return p.Backend switch
            {
                "copilot" => await this.FetchCopilotAsync(p.ApiKey, p.CopilotApiBase, ct),
                "ollama" => await this.FetchOllamaAsync(p.ApiUrl, ct),
                "openai" => await this.FetchOpenAiAsync(p.ApiKey, ct),
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
        // Use the token manager to get a valid session token
        var (sessionToken, apiBase) = await this.copilotTokens.GetTokenAsync(ct);
        if (sessionToken is null || apiBase is null)
        {
            // Fallback: try direct exchange if token manager has no cached oauth token yet
            // (e.g. fresh login where QML already exchanged and passed the session token)
            if (!string.IsNullOrEmpty(copilotApiBase))
            {
                sessionToken = apiKeyOrOauth;
                apiBase = copilotApiBase;
            }
            else
            {
                this.transport.SendSignal("models/tokenExpired");
                return new ModelListResult();
            }
        }

        // Fetch models
        using var modelsReq = new HttpRequestMessage(HttpMethod.Get, $"{apiBase}/models");
        modelsReq.Headers.TryAddWithoutValidation("Authorization", $"Bearer {sessionToken}");
        modelsReq.Headers.TryAddWithoutValidation("Accept", "application/json");
        foreach (var (name, value) in CopilotHeaders)
            modelsReq.Headers.TryAddWithoutValidation(name, value);

        using var modelsResp = await this.http.SendAsync(modelsReq, ct);
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
        var json = await this.http.GetStringAsync($"{baseUrl}/api/tags", ct);
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

        using var resp = await this.http.SendAsync(req, ct);
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
