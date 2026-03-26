# Memory MCP

Persistent memory server for the LLM via MCP.

## Purpose

Gives the LLM the ability to remember information across conversations.
The model can recall past context, save new insights, and build up a
knowledge base over time. Memory files are encrypted at rest.

See also: [Memory overview](memory.md), [Memory Management](memory-management.md)

## Storage

```text
~/.config/hyprchat/memory/
├── general.md.enc
├── linux.md.enc
├── cpp.md.enc
├── projects.md.enc
└── ...
```

Files are markdown encrypted with AES-256-GCM. One file per topic,
created on demand when the model writes to a topic that doesn't exist.

### Encryption

- Memory files are encrypted at rest using AES-256-CBC with PBKDF2
- The encryption key is stored in the system keyring
  (`service: hyprchat`, `account: memory_key`)
- On first use, a random 256-bit key is generated and stored in the
  keyring automatically
- Files are decrypted into an in-memory cache at startup
- Changes update the cache immediately, then write back encrypted

#### File Format

Each `.md.enc` file starts with a plaintext header line identifying
the encryption algorithm, followed by the encrypted data:

```txt
HYPRCHAT:v1:aes-256-cbc\n<encrypted bytes>
```

| Field | Value | Purpose |
| ----- | ----- | ------- |
| Magic | `HYPRCHAT` | Identifies the file as HyprChat memory |
| Version | `v1` | Format version for future migration |
| Algorithm | `aes-256-cbc` | Encryption algorithm identifier |

On decrypt, the header is read first. If the header matches a known
format, the corresponding algorithm is used. Files without a header
(legacy) fall back to AES-256-CBC.

## Tools Exposed

| Tool | Description | Parameters |
| ---- | ----------- | ---------- |
| `memory_list_topics` | List all available memory topics | _(none)_ |
| `memory_read` | Read a memory file by topic | `topic` (string) |
| `memory_append` | Append content to a memory file | `topic` (string), `content` (string) |
| `memory_edit` | Replace the full content of a memory file | `topic` (string), `content` (string) |
| `memory_search` | Search across all memory files | `query` (string) |
| `memory_delete_topic` | Delete an entire memory topic | `topic` (string) |
| `memory_reorganize` | Split a large topic into subtopics | `source_topic` (string), `subtopics` (array) |

### Behavior

- `memory_list_topics` — returns topic names (filenames without `.md.enc`)
- `memory_read` — decrypts and returns the full contents of `{topic}.md.enc`
- `memory_append` — appends content to the end of a topic. Creates the
  file if it doesn't exist. Use for quick additions without reading first.
- `memory_edit` — replaces the full content of a topic. Creates the file
  if it doesn't exist. Always read the topic first so existing content
  is not lost. Use when rewriting, restructuring, or removing entries.
- `memory_search` — decrypts all files, performs substring/keyword search,
  returns matching excerpts with topic names.
- `memory_delete_topic` — deletes `{topic}.md.enc` from disk

## Memory Viewer

HyprChat includes a built-in memory viewer accessible from the UI.
It provides:

- **Topic list** — scrollable list of all memory topics with file sizes
- **Content view** — read the decrypted content of any topic
- **Edit** — modify the content of a memory file in a text editor
- **Delete** — remove a memory topic entirely (with confirmation)
- **Search** — search across all memory files

The viewer communicates with the Memory MCP server using the same
tools the LLM uses. No separate file access is needed.

### UI Integration

The memory viewer is a panel/view within HyprChat, toggled via a
button in the top bar or a keyboard shortcut. It does not replace
the chat view — it can be shown alongside or as an overlay.

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
The encryption key is generated and stored in the keyring on first use.

## Implementation

The Memory MCP server is implemented as a script or small binary
spawned by QuickShell via `Process`. It communicates over stdin/stdout
JSON-RPC following the MCP stdio transport spec.

For the initial implementation, a Python or bash script is the
simplest approach. Encryption uses `openssl` CLI for AES-256-GCM:

```bash
# Encrypt
openssl enc -aes-256-gcm -in plain.md -out topic.md.enc -K $KEY_HEX -iv $NONCE_HEX

# Decrypt
openssl enc -d -aes-256-gcm -in topic.md.enc -out - -K $KEY_HEX -iv $NONCE_HEX
```

Alternatively, a Python script using `cryptography` library for
cleaner AES-GCM handling.

The server:

1. Retrieves the encryption key from keyring via `secret-tool`
2. If no key exists, generates one and stores it
3. Receives `initialize` → responds with capabilities
4. Receives `tools/list` → responds with the tool definitions above
5. Receives `tools/call` → decrypts, operates, re-encrypts as needed

## Security

- **Encrypted at rest** — AES-256-GCM, key in system keyring
- **Scoped** — only accesses files within the configured memory path
- **Path validation** — topic names are sanitized (alphanumeric +
  hyphens, no path separators) to prevent traversal
- **Key isolation** — the encryption key never leaves the keyring
  and the MCP server process. It's not exposed to the LLM.
- **Delete support** — users can permanently remove memory topics
  through the viewer
