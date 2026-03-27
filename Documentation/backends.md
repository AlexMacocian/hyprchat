# Backends & Models

LLM provider interface and supported backends.

## Backend Interface

The NativeAOT backend (`ChatService.cs`) works with any OpenAI-compatible
API. It sends requests via `HttpClient` and streams SSE responses.
Tool definitions are included in the request body when tools are enabled.

## Supported Backends

| Backend | API | Auth | Tools |
| ------- | --- | ---- | ----- |
| **GitHub Copilot** | GitHub Models (`models.inference.ai.azure.com`) | OAuth device flow | Yes — OpenAI-compatible `tools` param |
| **OpenAI** | `api.openai.com/v1/chat/completions` | API key | Yes — native `tools` / `tool_choice` |
| **Claude** | Via Copilot (Claude models on GitHub Models) | Copilot auth | Yes — OpenAI-compatible format |
| **Ollama** | `localhost:11434/api/chat` | None (local) | Partial — model-dependent |
| **Custom** | User-configured URL | Configurable | Optional — configurable |

## Streaming

The backend uses `HttpClient` with `HttpCompletionOption.ResponseHeadersRead`
to stream tokens as they arrive. Each SSE line is parsed and emitted
via `chat/token` notifications to the QML frontend.

## Tool Support

Tool definitions are built by `ToolDefinitions.cs` based on feature
flags (memory, web, shell, file, date). They follow the OpenAI
function calling format and are included in the request body.

## Authentication

API keys are stored in the system keyring via `secret-tool` (libsecret),
not in environment variables or config files.

- **Copilot**: OAuth device flow → session token (keyring `account: copilot_oauth`)
- **OpenAI**: API key from keyring (`account: openai`)
- **Claude**: Via Copilot (no separate auth)
- **Ollama**: None — local, no key needed

See [Authentication](authentication.md) for details.
