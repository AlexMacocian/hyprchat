# Memory MCP

Persistent memory server for the LLM via MCP.

## Purpose

Gives the LLM the ability to remember information across conversations.
The model can recall past context, save new insights, and build up a
knowledge base over time — all stored as human-readable markdown.

See also: [Memory overview](memory.md), [Memory Management](memory-management.md)

## Storage

```text
~/.config/hyprchat/memory/
├── general.md
├── linux.md
├── cpp.md
├── projects.md
└── ...
```

Files are plain markdown, one per topic. Created on demand when the
model writes to a topic that doesn't exist yet.

## Tools Exposed

| Tool | Description | Parameters |
| ---- | ----------- | ---------- |
| `memory_list_topics` | List all available memory topics | _(none)_ |
| `memory_read` | Read a memory file by topic | `topic` (string) |
| `memory_append` | Append content to a memory file | `topic` (string), `content` (string) |
| `memory_search` | Search across all memory files | `query` (string) |

### Behavior

- `memory_list_topics` — returns topic names (filenames without `.md`)
- `memory_read` — returns the full contents of `{topic}.md`
- `memory_append` — appends `content` as a new section to `{topic}.md`,
  separated by a blank line. Creates the file if it doesn't exist.
- `memory_search` — simple substring/keyword search across all files.
  Returns matching excerpts with topic names.

## Configuration

```json
{
  "mcp": {
    "memory": {
      "path": "~/.config/hyprchat/memory"
    }
  }
}
```

The directory is created automatically if it doesn't exist.

## Implementation

Spawned by `McpClient` as a `QProcess`. Communicates over stdin/stdout
JSON-RPC following the MCP stdio transport spec.

The server is a small standalone binary (or script) that:

1. Receives `initialize` → responds with capabilities
2. Receives `tools/list` → responds with the tool definitions above
3. Receives `tools/call` → performs the file operation and returns result

## Security

- **Scoped** — only accesses files within the configured memory path
- **Append-only writes** — no overwrite, no delete via tools
- **Path validation** — topic names are sanitized (alphanumeric + hyphens,
  no path separators) to prevent traversal
