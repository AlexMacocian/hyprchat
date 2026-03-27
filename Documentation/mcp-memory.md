# Memory MCP

Persistent memory for the LLM.

## Purpose

Gives the LLM the ability to remember information across conversations.
The model can recall past context, save new insights, and build up a
knowledge base over time. Memory files are encrypted at rest.

See also: [Memory overview](memory.md), [Memory Management](memory-management.md)

## Storage

```text
~/.config/hyprchat/memory/
├── general.md.enc
├── user.md.enc
├── linux/
│   ├── hyprland.md.enc
│   └── packages.md.enc
└── ...
```

One file per topic, nested topics use subdirectories.

### Encryption

- AES-256-CBC with PBKDF2
- Key stored in system keyring (`service: hyprchat`, `account: memory_key`)
- Generated automatically on first use
- Files decrypted into in-memory cache at startup
- Changes update cache immediately and write back encrypted

#### File Format

```txt
HYPRCHAT:v1:aes-256-cbc\n<encrypted bytes>
```

## Tools Exposed

| Tool | Description | Parameters |
| ---- | ----------- | ---------- |
| `memory_list_topics` | List all available memory topics | _(none)_ |
| `memory_read` | Read a memory file by topic | `topic` (string) |
| `memory_append` | Append content to a memory file | `topic` (string), `content` (string) |
| `memory_edit` | Replace the full content of a memory file | `topic` (string), `content` (string) |
| `memory_search` | Search across all memory files | `query` (string) |
| `memory_reorganize` | Split a large topic into subtopics | `source_topic` (string), `subtopics` (array) |

## Memory Viewer

Built-in UI panel for browsing, reading, editing, and deleting memory
topics. Fetches data from the backend via JSON-RPC (`memory/list`,
`memory/read`, `memory/edit`, `memory/delete`).

## Security

- **Encrypted at rest** — AES-256-CBC, key in system keyring
- **Scoped** — only accesses files within the memory directory
- **Path validation** — topic names sanitized (alphanumeric, hyphens,
  underscores, `/` for nesting). `..` rejected.
- **Key isolation** — encryption key never exposed to the LLM

## Implementation

`MemoryStore.cs` in the NativeAOT backend. Uses `System.Security.Cryptography`
indirectly via `openssl` CLI for encryption (compatible with existing
file format). Key retrieved via `secret-tool`.
