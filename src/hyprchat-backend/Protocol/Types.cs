using System.Text.Json;
using System.Text.Json.Serialization;

namespace HyprChat.Protocol;

// --- JSON-RPC envelope ---

public sealed class RpcRequest
{
  [JsonPropertyName("jsonrpc")]
  public string JsonRpc { get; set; } = "2.0";

  [JsonPropertyName("id")]
  public int? Id { get; set; }

  [JsonPropertyName("method")]
  public string Method { get; set; } = "";

  [JsonPropertyName("params")]
  public JsonElement? Params { get; set; }
}

public sealed class RpcResponse<TResult>
{
  [JsonPropertyName("jsonrpc")]
  public string JsonRpc { get; set; } = "2.0";

  [JsonPropertyName("id")]
  public int? Id { get; set; }

  [JsonPropertyName("result")]
  public TResult? Result { get; set; }
}

public sealed class RpcErrorResponse
{
  [JsonPropertyName("jsonrpc")]
  public string JsonRpc { get; set; } = "2.0";

  [JsonPropertyName("id")]
  public int? Id { get; set; }

  [JsonPropertyName("error")]
  public RpcError? Error { get; set; }
}

public sealed class RpcError
{
  [JsonPropertyName("code")]
  public int Code { get; set; }

  [JsonPropertyName("message")]
  public string Message { get; set; } = "";
}

public sealed class RpcNotification<TParams>
{
  [JsonPropertyName("jsonrpc")]
  public string JsonRpc { get; set; } = "2.0";

  [JsonPropertyName("method")]
  public string Method { get; set; } = "";

  [JsonPropertyName("params")]
  public TParams? Params { get; set; }
}

public sealed class RpcSignal
{
  [JsonPropertyName("jsonrpc")]
  public string JsonRpc { get; set; } = "2.0";

  [JsonPropertyName("method")]
  public string Method { get; set; } = "";
}

// --- Chat types ---

public sealed class ChatMessage
{
  [JsonPropertyName("role")]
  public string Role { get; set; } = "";

  [JsonPropertyName("content")]
  [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
  public string? Content { get; set; }

  [JsonPropertyName("tool_calls")]
  [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
  public List<ToolCallMessage>? ToolCalls { get; set; }

  [JsonPropertyName("tool_call_id")]
  [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
  public string? ToolCallId { get; set; }
}

public sealed class ToolCallMessage
{
  [JsonPropertyName("id")]
  public string Id { get; set; } = "";

  [JsonPropertyName("type")]
  public string Type { get; set; } = "function";

  [JsonPropertyName("function")]
  public ToolCallFunction Function { get; set; } = new();
}

public sealed class ToolCallFunction
{
  [JsonPropertyName("name")]
  public string Name { get; set; } = "";

  [JsonPropertyName("arguments")]
  public string Arguments { get; set; } = "";
}

// --- Chat send params ---

public sealed class ChatSendParams
{
  [JsonPropertyName("messages")]
  public List<ChatMessage> Messages { get; set; } = [];

  [JsonPropertyName("backend")]
  public string Backend { get; set; } = "";

  [JsonPropertyName("model")]
  public string Model { get; set; } = "";

  [JsonPropertyName("apiUrl")]
  public string ApiUrl { get; set; } = "";

  [JsonPropertyName("apiKey")]
  public string ApiKey { get; set; } = "";

  [JsonPropertyName("systemPrompt")]
  public string SystemPrompt { get; set; } = "";

  [JsonPropertyName("contextSummary")]
  public string ContextSummary { get; set; } = "";

  [JsonPropertyName("extraHeaders")]
  public List<string> ExtraHeaders { get; set; } = [];

  // Feature flags
  [JsonPropertyName("memoryEnabled")]
  public bool MemoryEnabled { get; set; }

  [JsonPropertyName("webSearchEnabled")]
  public bool WebSearchEnabled { get; set; }

  [JsonPropertyName("shellEnabled")]
  public bool ShellEnabled { get; set; }

  [JsonPropertyName("fileAccessEnabled")]
  public bool FileAccessEnabled { get; set; }

  [JsonPropertyName("dateEnabled")]
  public bool DateEnabled { get; set; }

  [JsonPropertyName("fileAccessRoot")]
  public string FileAccessRoot { get; set; } = "/";

  [JsonPropertyName("memorySplitThreshold")]
  public int MemorySplitThreshold { get; set; } = 200;
}

// --- Notification params ---

public sealed class TokenParams
{
  [JsonPropertyName("token")]
  public string Token { get; set; } = "";
}

public sealed class ToolCallNotification
{
  [JsonPropertyName("name")]
  public string Name { get; set; } = "";

  [JsonPropertyName("args")]
  public string Args { get; set; } = "";
}

public sealed class ToolResultNotification
{
  [JsonPropertyName("name")]
  public string Name { get; set; } = "";

  [JsonPropertyName("preview")]
  public string Preview { get; set; } = "";
}

public sealed class UsageParams
{
  [JsonPropertyName("promptTokens")]
  public int PromptTokens { get; set; }

  [JsonPropertyName("completionTokens")]
  public int CompletionTokens { get; set; }

  [JsonPropertyName("totalTokens")]
  public int TotalTokens { get; set; }
}

public sealed class ErrorParams
{
  [JsonPropertyName("error")]
  public string Error { get; set; } = "";
}

// --- Model fetching ---

public sealed class ModelFetchParams
{
  [JsonPropertyName("backend")]
  public string Backend { get; set; } = "";

  [JsonPropertyName("apiKey")]
  public string ApiKey { get; set; } = "";

  [JsonPropertyName("apiUrl")]
  public string ApiUrl { get; set; } = "";

  [JsonPropertyName("copilotApiBase")]
  public string CopilotApiBase { get; set; } = "";
}

public sealed class ModelInfo
{
  [JsonPropertyName("id")]
  public string Id { get; set; } = "";

  [JsonPropertyName("name")]
  public string Name { get; set; } = "";

  [JsonPropertyName("maxTokens")]
  public int MaxTokens { get; set; }
}

public sealed class ModelListResult
{
  [JsonPropertyName("models")]
  public List<ModelInfo> Models { get; set; } = [];
}

public sealed class CopilotApiResult
{
  [JsonPropertyName("apiBase")]
  public string ApiBase { get; set; } = "";

  [JsonPropertyName("token")]
  public string Token { get; set; } = "";
}

// --- Keyring ---

public sealed class KeyringParams
{
  [JsonPropertyName("account")]
  public string Account { get; set; } = "";

  [JsonPropertyName("key")]
  [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
  public string? Key { get; set; }
}

public sealed class KeyringResult
{
  [JsonPropertyName("account")]
  public string Account { get; set; } = "";

  [JsonPropertyName("found")]
  public bool Found { get; set; }

  [JsonPropertyName("key")]
  [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
  public string? Key { get; set; }
}

// --- Memory direct access (for MemoryView UI) ---

public sealed class MemoryTopicParams
{
  [JsonPropertyName("topic")]
  public string Topic { get; set; } = "";

  [JsonPropertyName("content")]
  [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
  public string? Content { get; set; }
}

public sealed class MemoryListResult
{
  [JsonPropertyName("topics")]
  public List<string> Topics { get; set; } = [];
}

public sealed class MemoryReadResult
{
  [JsonPropertyName("topic")]
  public string Topic { get; set; } = "";

  [JsonPropertyName("content")]
  public string Content { get; set; } = "";
}

// --- OpenAI API response types (for SSE parsing) ---

public sealed class OpenAiStreamChunk
{
  [JsonPropertyName("choices")]
  public List<OpenAiChoice>? Choices { get; set; }

  [JsonPropertyName("usage")]
  public OpenAiUsage? Usage { get; set; }
}

public sealed class OpenAiChoice
{
  [JsonPropertyName("delta")]
  public OpenAiDelta? Delta { get; set; }
}

public sealed class OpenAiDelta
{
  [JsonPropertyName("content")]
  public string? Content { get; set; }

  [JsonPropertyName("tool_calls")]
  public List<OpenAiToolCallDelta>? ToolCalls { get; set; }
}

public sealed class OpenAiToolCallDelta
{
  [JsonPropertyName("index")]
  public int Index { get; set; }

  [JsonPropertyName("id")]
  public string? Id { get; set; }

  [JsonPropertyName("function")]
  public OpenAiToolCallFunctionDelta? Function { get; set; }
}

public sealed class OpenAiToolCallFunctionDelta
{
  [JsonPropertyName("name")]
  public string? Name { get; set; }

  [JsonPropertyName("arguments")]
  public string? Arguments { get; set; }
}

public sealed class OpenAiUsage
{
  [JsonPropertyName("prompt_tokens")]
  public int PromptTokens { get; set; }

  [JsonPropertyName("completion_tokens")]
  public int CompletionTokens { get; set; }

  [JsonPropertyName("total_tokens")]
  public int TotalTokens { get; set; }
}

// --- Copilot token exchange ---

public sealed class CopilotTokenResponse
{
  [JsonPropertyName("token")]
  public string Token { get; set; } = "";

  [JsonPropertyName("expires_at")]
  public long ExpiresAt { get; set; }

  [JsonPropertyName("endpoints")]
  public CopilotEndpoints? Endpoints { get; set; }
}

public sealed class CopilotEndpoints
{
  [JsonPropertyName("api")]
  public string Api { get; set; } = "";
}

// --- OAuth token refresh response ---

public sealed class OAuthTokenResponse
{
  [JsonPropertyName("access_token")]
  public string? AccessToken { get; set; }

  [JsonPropertyName("refresh_token")]
  public string? RefreshToken { get; set; }

  [JsonPropertyName("token_type")]
  public string? TokenType { get; set; }

  [JsonPropertyName("error")]
  public string? Error { get; set; }

  [JsonPropertyName("error_description")]
  public string? ErrorDescription { get; set; }
}

// --- Copilot/OpenAI models response ---

public sealed class ModelsApiResponse
{
  [JsonPropertyName("data")]
  public List<ModelApiEntry>? Data { get; set; }

  [JsonPropertyName("models")]
  public List<OllamaModelEntry>? Models { get; set; }
}

public sealed class ModelApiEntry
{
  [JsonPropertyName("id")]
  public string Id { get; set; } = "";

  [JsonPropertyName("name")]
  public string? Name { get; set; }

  [JsonPropertyName("capabilities")]
  public ModelCapabilities? Capabilities { get; set; }
}

public sealed class ModelCapabilities
{
  [JsonPropertyName("type")]
  public string? Type { get; set; }

  [JsonPropertyName("limits")]
  public ModelLimits? Limits { get; set; }
}

public sealed class ModelLimits
{
  [JsonPropertyName("max_prompt_tokens")]
  public int? MaxPromptTokens { get; set; }
}

public sealed class OllamaModelEntry
{
  [JsonPropertyName("name")]
  public string Name { get; set; } = "";
}

// --- Tool definitions (OpenAI function calling format) ---

public sealed class ToolDefinition
{
  [JsonPropertyName("type")]
  public string Type { get; set; } = "function";

  [JsonPropertyName("function")]
  public ToolFunctionDef Function { get; set; } = new();
}

public sealed class ToolFunctionDef
{
  [JsonPropertyName("name")]
  public string Name { get; set; } = "";

  [JsonPropertyName("description")]
  public string Description { get; set; } = "";

  [JsonPropertyName("parameters")]
  public JsonElement Parameters { get; set; }
}

// --- OpenAI API request body ---

public sealed class OpenAiRequestBody
{
    [JsonPropertyName("model")]
    public string Model { get; set; } = "";

    [JsonPropertyName("messages")]
    public List<ChatMessage> Messages { get; set; } = [];

    [JsonPropertyName("stream")]
    public bool Stream { get; set; } = true;

    [JsonPropertyName("tools")]
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)]
    public List<ToolDefinition>? Tools { get; set; }
}

// --- Source gen context ---

[JsonSerializable(typeof(OpenAiRequestBody))]
[JsonSerializable(typeof(RpcRequest))]
[JsonSerializable(typeof(RpcErrorResponse))]
[JsonSerializable(typeof(RpcSignal))]
// Response<T> — every concrete result type
[JsonSerializable(typeof(RpcResponse<string>))]
[JsonSerializable(typeof(RpcResponse<ModelListResult>))]
[JsonSerializable(typeof(RpcResponse<KeyringResult>))]
[JsonSerializable(typeof(RpcResponse<MemoryListResult>))]
[JsonSerializable(typeof(RpcResponse<MemoryReadResult>))]
// Notification<T> — every concrete params type
[JsonSerializable(typeof(RpcNotification<TokenParams>))]
[JsonSerializable(typeof(RpcNotification<UsageParams>))]
[JsonSerializable(typeof(RpcNotification<ToolCallNotification>))]
[JsonSerializable(typeof(RpcNotification<ToolResultNotification>))]
[JsonSerializable(typeof(RpcNotification<ErrorParams>))]
[JsonSerializable(typeof(RpcNotification<CopilotApiResult>))]
// Inner types
[JsonSerializable(typeof(ChatSendParams))]
[JsonSerializable(typeof(TokenParams))]
[JsonSerializable(typeof(ToolCallNotification))]
[JsonSerializable(typeof(ToolResultNotification))]
[JsonSerializable(typeof(UsageParams))]
[JsonSerializable(typeof(ErrorParams))]
[JsonSerializable(typeof(ModelFetchParams))]
[JsonSerializable(typeof(ModelInfo))]
[JsonSerializable(typeof(ModelListResult))]
[JsonSerializable(typeof(CopilotApiResult))]
[JsonSerializable(typeof(KeyringParams))]
[JsonSerializable(typeof(KeyringResult))]
[JsonSerializable(typeof(MemoryTopicParams))]
[JsonSerializable(typeof(MemoryListResult))]
[JsonSerializable(typeof(MemoryReadResult))]
[JsonSerializable(typeof(OpenAiStreamChunk))]
[JsonSerializable(typeof(CopilotTokenResponse))]
[JsonSerializable(typeof(OAuthTokenResponse))]
[JsonSerializable(typeof(ModelsApiResponse))]
[JsonSerializable(typeof(ChatMessage))]
[JsonSerializable(typeof(ToolCallMessage))]
[JsonSerializable(typeof(ToolDefinition))]
[JsonSerializable(typeof(List<ChatMessage>))]
[JsonSerializable(typeof(List<ToolCallMessage>))]
[JsonSerializable(typeof(List<ToolDefinition>))]
[JsonSerializable(typeof(List<ModelInfo>))]
[JsonSerializable(typeof(List<string>))]
[JsonSerializable(typeof(Dictionary<string, JsonElement>))]
[JsonSerializable(typeof(bool))]
[JsonSerializable(typeof(string))]
[JsonSerializable(typeof(int))]
[JsonSourceGenerationOptions(
    PropertyNamingPolicy = JsonKnownNamingPolicy.CamelCase,
    DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull)]
public partial class HyprChatJsonContext : JsonSerializerContext;
