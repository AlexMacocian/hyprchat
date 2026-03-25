# Backends & Models

LLM provider interface and supported backends.

## Backend Interface

Each backend extends a common C++ base class exposed to QML:

```cpp
struct ToolDefinition {
    QString name;
    QString description;
    QJsonObject inputSchema;  // JSON Schema for parameters
};

struct ToolCall {
    QString id;
    QString name;
    QJsonObject arguments;
};

struct ToolResult {
    QString callId;
    QString content;
    bool isError = false;
};

class Backend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(bool supportsTools READ supportsTools CONSTANT)
public:
    virtual QString name() const = 0;
    virtual bool supportsTools() const = 0;

    // Start a streaming request. If tools are provided and the backend
    // supports them, include tool definitions in the API request.
    virtual void stream(
        const QList<ChatMessage>& messages,
        const QList<ToolDefinition>& tools = {}) = 0;

signals:
    void tokenReceived(const QString& token);
    void toolCallRequested(const QList<ToolCall>& calls);
    void streamFinished();
    void streamError(const QString& error);
};
```

Each backend translates the common `ToolDefinition` into its API's
wire format.

## Supported Backends

| Backend | API | Auth | Tools |
| ------- | --- | ---- | ----- |
| **GitHub Copilot** | GitHub Models (`models.inference.ai.azure.com`) | `gh auth token` | Yes — OpenAI-compatible `tools` param |
| **OpenAI** | `api.openai.com/v1/chat/completions` | API key | Yes — native `tools` / `tool_choice` |
| **Claude** | `api.anthropic.com/v1/messages` | API key | Yes — native `tools` param (different format) |
| **Ollama** | `localhost:11434/api/chat` | None (local) | Partial — model-dependent |
| **Custom** | User-configured URL | Configurable | Optional — configurable |

## Streaming

All backends use `QNetworkAccessManager` with chunked response reading
to stream tokens as they arrive. Each chunk is parsed and emitted via
the `tokenReceived` signal. When the LLM responds with a tool call
instead of (or alongside) text, the backend emits `toolCallRequested`.

## Tool Support

Backends report `supportsTools()` so the system can gracefully degrade.
When tools are supported, the backend includes `ToolDefinition` objects
in the API request, translated to the provider's specific format:

- **OpenAI / Copilot**: `tools` array with `function` type objects
- **Claude**: `tools` array with Anthropic's tool schema format
- **Ollama**: OpenAI-compatible format (model must support tool use)
- **Custom**: Configurable — assumes OpenAI format by default

## Authentication

API keys are read from environment variables, never stored in config:

- `OPENAI_API_KEY` for OpenAI
- `ANTHROPIC_API_KEY` for Claude
- Copilot uses `gh auth token` (GitHub CLI)
- Ollama requires no auth (local)
- Custom backends have a configurable `api_key_env` field
