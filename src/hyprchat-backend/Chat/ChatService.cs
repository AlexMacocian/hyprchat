using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using HyprChat.Protocol;
using HyprChat.Tools;

namespace HyprChat.Chat;

/// <summary>
/// Streams chat completions from an OpenAI-compatible API.
/// Handles SSE parsing and the tool-use loop internally.
/// Emits notifications via RpcTransport for the QML frontend.
/// </summary>
public sealed class ChatService
{
    private readonly HttpClient _http;
    private readonly ToolDispatcher _tools;
    private readonly RpcTransport _transport;
    private const int MaxToolLoops = 100;

    private CancellationTokenSource? _activeCts;

    public ChatService(HttpClient http, ToolDispatcher tools, RpcTransport transport)
    {
        _http = http;
        _tools = tools;
        _transport = transport;
    }

    public void Cancel()
    {
        _activeCts?.Cancel();
    }

    public async Task SendAsync(ChatSendParams p, CancellationToken externalCt)
    {
        _activeCts?.Cancel();
        using var cts = CancellationTokenSource.CreateLinkedTokenSource(externalCt);
        _activeCts = cts;
        var ct = cts.Token;

        try
        {
            // Build system prompt
            var fullPrompt = SystemPromptBuilder.Build(
                p.SystemPrompt, p.MemoryEnabled, p.WebSearchEnabled,
                p.ShellEnabled, p.FileAccessEnabled, p.DateEnabled);

            // Build tool definitions
            var toolDefs = ToolDefinitions.Build(
                p.MemoryEnabled, p.WebSearchEnabled,
                p.ShellEnabled, p.FileAccessEnabled, p.DateEnabled);

            // Assemble messages
            var messages = new List<ChatMessage>
            {
                new() { Role = "system", Content = fullPrompt }
            };

            if (!string.IsNullOrEmpty(p.ContextSummary))
            {
                messages.Add(new ChatMessage
                {
                    Role = "system",
                    Content = "Previous conversation summary:\n" + p.ContextSummary
                });
            }

            // Add user messages (skip system/placeholder)
            foreach (var msg in p.Messages)
            {
                if (msg.Role == "system" || msg.Content == "...") continue;
                messages.Add(msg);
            }

            // Tool-use loop
            var loopCount = 0;
            while (true)
            {
                ct.ThrowIfCancellationRequested();

                Console.Error.WriteLine($"ChatService: streaming completion, {messages.Count} messages, loop {loopCount}");
                var (content, toolCalls, usage) = await StreamCompletionAsync(
                    p.ApiUrl, p.ApiKey, p.Model, messages, toolDefs, p.ExtraHeaders, ct);
                Console.Error.WriteLine($"ChatService: stream done, content={content.Length} chars, toolCalls={toolCalls.Count}");

                // Report usage
                if (usage is not null)
                {
                    _transport.SendNotification("chat/usage", new UsageParams
                    {
                        PromptTokens = usage.PromptTokens,
                        CompletionTokens = usage.CompletionTokens,
                        TotalTokens = usage.TotalTokens
                    }, HyprChatJsonContext.Default.RpcNotificationUsageParams);
                }

                // No tool calls — we're done
                if (toolCalls.Count == 0)
                {
                    _transport.SendSignal("chat/finished");
                    return;
                }

                // Tool loop guard
                loopCount++;
                if (loopCount > MaxToolLoops)
                {
                    _transport.SendNotification("chat/token",
                        new TokenParams { Token = "\n\n*[Tool loop limit reached]*" },
                        HyprChatJsonContext.Default.RpcNotificationTokenParams);
                    _transport.SendSignal("chat/finished");
                    return;
                }

                // Execute tools
                // Filter out incomplete tool calls (streaming artifacts)
                var validToolCalls = toolCalls
                    .Where(tc => !string.IsNullOrEmpty(tc.Id) && !string.IsNullOrEmpty(tc.Name))
                    .ToList();

                if (validToolCalls.Count == 0)
                {
                    _transport.SendSignal("chat/finished");
                    return;
                }

                // Add assistant message with tool_calls
                messages.Add(new ChatMessage
                {
                    Role = "assistant",
                    Content = string.IsNullOrEmpty(content) ? null : content,
                    ToolCalls = validToolCalls.Select(tc => new ToolCallMessage
                    {
                        Id = tc.Id,
                        Type = "function",
                        Function = new ToolCallFunction
                        {
                            Name = tc.Name,
                            Arguments = tc.Arguments
                        }
                    }).ToList()
                });

                // Execute each tool and collect results
                foreach (var tc in validToolCalls)
                {

                    // Notify UI about tool execution
                    _transport.SendNotification("chat/toolCall", new ToolCallNotification
                    {
                        Name = tc.Name,
                        Args = tc.Arguments
                    }, HyprChatJsonContext.Default.RpcNotificationToolCallNotification);

                    var result = await _tools.ExecuteAsync(tc.Name, tc.Arguments, ct);

                    // Notify UI with result preview
                    _transport.SendNotification("chat/toolResult", new ToolResultNotification
                    {
                        Name = tc.Name,
                        Preview = result.Length > 200 ? result[..200] + "..." : result
                    }, HyprChatJsonContext.Default.RpcNotificationToolResultNotification);

                    messages.Add(new ChatMessage
                    {
                        Role = "tool",
                        ToolCallId = tc.Id,
                        Content = result
                    });
                }

                Console.Error.WriteLine($"ChatService: tool loop iteration {loopCount}, {toolCalls.Count} tools executed, sending {messages.Count} messages back to LLM");
            }
        }
        catch (OperationCanceledException)
        {
            // Cancelled — not an error
        }
        catch (Exception ex)
        {
            _transport.SendNotification("chat/error", new ErrorParams { Error = ex.Message },
                HyprChatJsonContext.Default.RpcNotificationErrorParams);
        }
        finally
        {
            if (_activeCts == cts)
                _activeCts = null;
        }
    }

    private async Task<(string Content, List<AccumulatedToolCall> ToolCalls, OpenAiUsage? Usage)>
        StreamCompletionAsync(
            string apiUrl, string apiKey, string model,
            List<ChatMessage> messages, List<ToolDefinition> tools,
            List<string> extraHeaders, CancellationToken ct)
    {
        // Build request body
        var body = new OpenAiRequestBody
        {
            Model = model,
            Messages = messages,
            Stream = true,
            Tools = tools.Count > 0 ? tools : null
        };

        var json = JsonSerializer.Serialize(body, HyprChatJsonContext.Default.OpenAiRequestBody);

        using var request = new HttpRequestMessage(HttpMethod.Post, apiUrl);
        request.Content = new StringContent(json, Encoding.UTF8, "application/json");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", apiKey);
        // Force Connection: close so the SSE connection is fully closed after we're done
        // This prevents the connection pool from trying to reuse a half-drained SSE stream
        request.Headers.ConnectionClose = true;

        // Add extra headers (each element is "Key: Value")
        foreach (var header in extraHeaders)
        {
            var colonIdx = header.IndexOf(':');
            if (colonIdx > 0)
            {
                var name = header[..colonIdx].Trim();
                var value = header[(colonIdx + 1)..].Trim();
                request.Headers.TryAddWithoutValidation(name, value);
            }
        }

        Console.Error.WriteLine($"ChatService: sending HTTP request to {apiUrl}");
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
        Console.Error.WriteLine($"ChatService: got HTTP {(int)response.StatusCode}");

        if (!response.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync(ct);
            Console.Error.WriteLine($"ChatService: error body: {errorBody[..Math.Min(errorBody.Length, 500)]}");
            if (errorBody.Contains("expired", StringComparison.OrdinalIgnoreCase) ||
                errorBody.Contains("unauthorized", StringComparison.OrdinalIgnoreCase))
            {
                _transport.SendSignal("chat/tokenExpired");
            }
            throw new HttpRequestException($"HTTP {(int)response.StatusCode}: {errorBody}");
        }

        using var stream = await response.Content.ReadAsStreamAsync(ct);
        using var reader = new StreamReader(stream);

        var accumulatedContent = new StringBuilder();
        var toolCalls = new List<AccumulatedToolCall>();
        OpenAiUsage? usage = null;

        while (true)
        {
            var line = await reader.ReadLineAsync(ct);
            if (line is null) break; // End of stream
            if (string.IsNullOrWhiteSpace(line)) continue; // Empty SSE line separator
            if (!line.StartsWith("data: ")) continue;

            var payload = line[6..].Trim();
            if (payload == "[DONE]") break;

            try
            {
                var chunk = JsonSerializer.Deserialize(payload, HyprChatJsonContext.Default.OpenAiStreamChunk);
                if (chunk is null) continue;

                var delta = chunk.Choices?.FirstOrDefault()?.Delta;
                if (delta is not null)
                {
                    // Content tokens
                    if (delta.Content is not null)
                    {
                        accumulatedContent.Append(delta.Content);
                        _transport.SendNotification("chat/token", new TokenParams { Token = delta.Content },
                            HyprChatJsonContext.Default.RpcNotificationTokenParams);
                    }

                    // Tool calls (streamed incrementally)
                    if (delta.ToolCalls is not null)
                    {
                        foreach (var tc in delta.ToolCalls)
                        {
                            var idx = tc.Index;
                            while (toolCalls.Count <= idx)
                                toolCalls.Add(new AccumulatedToolCall());

                            if (tc.Id is not null)
                                toolCalls[idx].Id = tc.Id;
                            if (tc.Function?.Name is not null)
                                toolCalls[idx].Name = tc.Function.Name;
                            if (tc.Function?.Arguments is not null)
                                toolCalls[idx].Arguments += tc.Function.Arguments;
                        }
                    }
                }

                if (chunk.Usage is not null)
                    usage = chunk.Usage;
            }
            catch (JsonException)
            {
                // Malformed chunk — skip
            }
        }

        Console.Error.WriteLine($"ChatService: stream done, content={accumulatedContent.Length} chars, toolCalls={toolCalls.Count}");

        return (accumulatedContent.ToString(), toolCalls, usage);
    }
}

public sealed class AccumulatedToolCall
{
    public string Id { get; set; } = "";
    public string Name { get; set; } = "";
    public string Arguments { get; set; } = "";
}
