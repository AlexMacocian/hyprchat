# File System MCP

Read-only file access for the LLM via MCP.

## Purpose

Lets the model reference local code, configs, or documents when
answering questions. The user asks about a file, and the LLM can
read it directly instead of relying on the user to paste it.

## Scope

- Scoped to user-configured directories (e.g. `~/Dev`, `~/Documents`)
- **Read-only** — no writes, no deletes, no renames
- Files outside configured roots are inaccessible

## Tools Exposed

| Tool | Description | Parameters |
| ---- | ----------- | ---------- |
| `fs_read_file` | Read the contents of a file | `path` (string) |
| `fs_list_directory` | List files and directories at a path | `path` (string) |
| `fs_search_files` | Search file names matching a glob pattern | `pattern` (string), `root` (string, optional) |

All paths are validated against the configured roots before access.
Paths outside the roots return an error.

## Configuration

```json
{
  "mcp": {
    "filesystem": {
      "roots": ["~/Dev", "~/Documents"]
    }
  }
}
```

`roots` is a list of directories the LLM can access. Paths are
expanded (`~` → `$HOME`) at startup. Subdirectories are included
recursively.

## Security

- **Path traversal prevention** — all resolved paths are checked
  against the canonical root paths. Symlinks are resolved before
  checking.
- **Read-only** — the server exposes no write tools.
- **No execution** — the server never runs files, only reads content.
- **Binary files** — detected and reported as binary (not dumped as
  raw bytes).

## Implementation

Spawned by `McpClient` as a `QProcess`. Communicates over stdin/stdout
JSON-RPC following the MCP stdio transport spec.

The server is a small standalone binary (or script) that:

1. Receives `initialize` → responds with capabilities
2. Receives `tools/list` → responds with the tool definitions above
3. Receives `tools/call` → reads the file/directory and returns content
