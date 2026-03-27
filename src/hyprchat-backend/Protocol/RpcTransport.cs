using System.Text.Json;
using System.Text.Json.Serialization.Metadata;

namespace HyprChat.Protocol;

/// <summary>
/// Reads newline-delimited JSON-RPC from stdin, writes to stdout.
/// Thread-safe for writes via lock.
/// All types are concrete generics registered in the source-gen context — fully AOT-safe.
/// </summary>
public sealed class RpcTransport
{
    private readonly StreamReader _reader;
    private readonly StreamWriter _writer;
    private readonly object _writeLock = new();

    public RpcTransport(Stream input, Stream output)
    {
        _reader = new StreamReader(input);
        _writer = new StreamWriter(output) { AutoFlush = true };
    }

    public async Task<RpcRequest?> ReadRequestAsync(CancellationToken ct = default)
    {
        var line = await _reader.ReadLineAsync(ct);
        if (line is null) return null;
        if (string.IsNullOrWhiteSpace(line)) return null;
        return JsonSerializer.Deserialize(line, HyprChatJsonContext.Default.RpcRequest);
    }

    public void SendResponse<TResult>(int? id, TResult result, JsonTypeInfo<RpcResponse<TResult>> typeInfo)
    {
        var resp = new RpcResponse<TResult> { Id = id, Result = result };
        WriteLine(JsonSerializer.Serialize(resp, typeInfo));
    }

    public void SendError(int? id, int code, string message)
    {
        var resp = new RpcErrorResponse
        {
            Id = id,
            Error = new RpcError { Code = code, Message = message }
        };
        WriteLine(JsonSerializer.Serialize(resp, HyprChatJsonContext.Default.RpcErrorResponse));
    }

    public void SendNotification<TParams>(string method, TParams @params, JsonTypeInfo<RpcNotification<TParams>> typeInfo)
    {
        var notif = new RpcNotification<TParams> { Method = method, Params = @params };
        WriteLine(JsonSerializer.Serialize(notif, typeInfo));
    }

    public void SendSignal(string method)
    {
        var signal = new RpcSignal { Method = method };
        WriteLine(JsonSerializer.Serialize(signal, HyprChatJsonContext.Default.RpcSignal));
    }

    private void WriteLine(string json)
    {
        lock (_writeLock)
        {
            _writer.WriteLine(json);
        }
    }
}
