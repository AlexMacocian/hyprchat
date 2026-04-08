using System.Net;
using System.Text.Json;
using HyprChat.Chat;
using HyprChat.Protocol;
using HyprChat.Services;
using HyprChat.Tools;

// --- Bootstrap services ---

var handler = new SocketsHttpHandler
{
    PooledConnectionLifetime = TimeSpan.FromMinutes(10),
    AutomaticDecompression = DecompressionMethods.All,
    // Corporate networks with MITM proxies — match scraper.js behavior
    SslOptions = { RemoteCertificateValidationCallback = (_, _, _, _) => true }
};
using var http = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(60) };

var transport = new RpcTransport(Console.OpenStandardInput(), Console.OpenStandardOutput());

var memory = new MemoryStore();
var files = new FileService();
var web = new WebService(http);
using var shell = new ShellExecutor();
var copilotTokens = new CopilotTokenManager(http, transport);
var toolDispatcher = new ToolDispatcher(memory, files, web, shell);
var chat = new ChatService(http, toolDispatcher, transport, copilotTokens);
var modelFetcher = new ModelFetcher(http, transport, copilotTokens);

// Initialize services
var initTasks = new List<Task>();

try
{
    await memory.InitializeAsync();
}
catch (Exception ex)
{
    Console.Error.WriteLine($"Memory init warning: {ex.Message}");
}

try
{
    await shell.InitializeAsync();
}
catch (Exception ex)
{
    Console.Error.WriteLine($"Shell init warning: {ex.Message}");
}

// Signal ready
transport.SendSignal("ready");

// --- Main JSON-RPC loop ---

using var cts = new CancellationTokenSource();
Console.CancelKeyPress += (_, e) =>
{
    e.Cancel = true;
    cts.Cancel();
};

try
{
    while (!cts.IsCancellationRequested)
    {
        var request = await transport.ReadRequestAsync(cts.Token);
        if (request is null) break; // EOF

        // Dispatch in background to keep reading
        _ = Task.Run(async () =>
        {
            try
            {
                await HandleRequestAsync(request, cts.Token);
            }
            catch (Exception ex)
            {
                if (request.Id.HasValue)
                    transport.SendError(request.Id, -32603, ex.Message);
            }
        }, cts.Token);
    }
}
catch (OperationCanceledException) { }

// --- Request handler ---

async Task HandleRequestAsync(RpcRequest req, CancellationToken ct)
{
    switch (req.Method)
    {
        case "chat/send":
        {
            var p = Deserialize<ChatSendParams>(req.Params);
            if (p is null) { transport.SendError(req.Id, -32602, "Invalid params"); return; }

            // Apply file access root
            files.AllowedRoot = p.FileAccessRoot;
            memory.SplitThreshold = p.MemorySplitThreshold;

            await chat.SendAsync(p, ct);
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, "ok", HyprChatJsonContext.Default.RpcResponseString);
            break;
        }

        case "chat/cancel":
            chat.Cancel();
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, "ok", HyprChatJsonContext.Default.RpcResponseString);
            break;

        case "models/fetch":
        {
            var p = Deserialize<ModelFetchParams>(req.Params);
            if (p is null) { transport.SendError(req.Id, -32602, "Invalid params"); return; }

            var result = await modelFetcher.FetchAsync(p, ct);
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, result, HyprChatJsonContext.Default.RpcResponseModelListResult);
            break;
        }

        case "keyring/lookup":
        {
            var p = Deserialize<KeyringParams>(req.Params);
            if (p is null) { transport.SendError(req.Id, -32602, "Invalid params"); return; }

            var (found, key) = await KeyringService.LookupAsync(p.Account);
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, new KeyringResult
                {
                    Account = p.Account,
                    Found = found,
                    Key = found ? key : null
                }, HyprChatJsonContext.Default.RpcResponseKeyringResult);
            break;
        }

        case "keyring/store":
        {
            var p = Deserialize<KeyringParams>(req.Params);
            if (p is null || p.Key is null) { transport.SendError(req.Id, -32602, "Invalid params"); return; }

            await KeyringService.StoreAsync(p.Account, p.Key);
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, "ok", HyprChatJsonContext.Default.RpcResponseString);
            break;
        }

        case "keyring/delete":
        {
            var p = Deserialize<KeyringParams>(req.Params);
            if (p is null) { transport.SendError(req.Id, -32602, "Invalid params"); return; }

            await KeyringService.DeleteAsync(p.Account);
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, "ok", HyprChatJsonContext.Default.RpcResponseString);
            break;
        }

        // Direct memory access for the MemoryView UI
        case "memory/list":
        {
            var topics = memory.ListTopics();
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, new MemoryListResult { Topics = topics },
                    HyprChatJsonContext.Default.RpcResponseMemoryListResult);
            break;
        }

        case "memory/read":
        {
            var p = Deserialize<MemoryTopicParams>(req.Params);
            if (p is null) { transport.SendError(req.Id, -32602, "Invalid params"); return; }

            var content = memory.ReadTopic(p.Topic);
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, new MemoryReadResult { Topic = p.Topic, Content = content },
                    HyprChatJsonContext.Default.RpcResponseMemoryReadResult);
            break;
        }

        case "memory/edit":
        {
            var p = Deserialize<MemoryTopicParams>(req.Params);
            if (p is null) { transport.SendError(req.Id, -32602, "Invalid params"); return; }

            memory.EditTopic(p.Topic, p.Content ?? "");
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, "ok", HyprChatJsonContext.Default.RpcResponseString);
            break;
        }

        case "memory/delete":
        {
            var p = Deserialize<MemoryTopicParams>(req.Params);
            if (p is null) { transport.SendError(req.Id, -32602, "Invalid params"); return; }

            memory.DeleteTopic(p.Topic);
            if (req.Id.HasValue)
                transport.SendResponse(req.Id, "ok", HyprChatJsonContext.Default.RpcResponseString);
            break;
        }

        default:
            if (req.Id.HasValue)
                transport.SendError(req.Id, -32601, $"Method not found: {req.Method}");
            break;
    }
}

T? Deserialize<T>(JsonElement? element) where T : class
{
    if (element is null) return null;
    return (T?)JsonSerializer.Deserialize(element.Value.GetRawText(),
        typeof(T), HyprChatJsonContext.Default);
}
