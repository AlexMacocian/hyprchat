# Memory

Persistent memory system for HyprChat.

## Overview

HyprChat supports persistent memory that survives across chat sessions.
The model can read existing memories for context and append new ones
when it learns something worth retaining.

Memory is implemented as an [MCP server](mcp-memory.md) that exposes
tools to the LLM via the standard MCP protocol.

## Storage

Memories are stored as encrypted markdown files organized by topic:

```
~/.config/hyprchat/memory/
├── general.md.enc
├── linux.md.enc
├── cpp.md.enc
├── projects.md.enc
└── ...
```

### Design Principles

- **Encrypted at rest** — AES-256-GCM, key stored in system keyring
- **Topic-based** — one file per topic, created on demand
- **Append-friendly** — the model primarily appends to memory files
- **Editable** — users can view and edit memories via the built-in
  memory viewer
- **Deletable** — users can remove memory topics entirely
- **Persistent** — survives across chats and daemon restarts
- **Simple** — no database, no indexing, just encrypted files

## How It Works

1. On startup, `McpClient` spawns the Memory MCP server and discovers
   its tools via `tools/list`
2. Tool definitions are passed to the LLM alongside the user's message
3. The LLM can choose to:
   - **Read** a memory file to recall context from past conversations
   - **Append** to a memory file to save new information
   - **List** available memory topics to see what's stored
4. Tool results are fed back into the conversation so the LLM can
   use the recalled information in its response

## Configuration

Memory path is configured in `~/.config/hyprchat/config.json`:

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

## Per-Conversation Toggle

Memory can be disabled for individual conversations. When toggled off:

- Memory MCP tools are excluded from the tool definitions sent to the
  backend — the LLM doesn't know memory exists
- No reads or writes to memory occur during that conversation
- The toggle is a UI control (button or keyboard shortcut) in the
  chat window, not a config file setting
- Default state (on/off) is configurable in `config.json`:

```json
{
  "memory": {
    "enabled_by_default": true
  }
}
```

Use cases for disabling memory:

- **Sensitive conversations** — don't want the model to persist anything
- **Throwaway questions** — quick lookup, no value in remembering
- **Testing** — isolate a conversation from accumulated memory context

The toggle is per-conversation, not global. Starting a new chat resets
to the configured default.

## Related

- [Memory MCP](mcp-memory.md) — tool interface and server implementation
- [Memory Management](memory-management.md) — segmentation, growth, and maintenance
- [System Prompt](system-prompt.md) — how the LLM is instructed to use memory
