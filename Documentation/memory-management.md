# Memory Management

Segmentation, growth control, and maintenance of persistent memory.

## The Problem

Memory files grow over time. A single `general.md` that starts at
a few lines could reach thousands of lines after months of use.
Large memory files waste context window tokens when the LLM reads
them, and eventually become too large to fit in a single tool result.

## Segmentation Strategy

### Topic-Based Hierarchy

Memory is organized as topic files. As a topic file grows, it should
be split into subtopics:

```txt
Before:
  linux.md  (500 lines — too large)

After:
  linux/
  ├── packages.md
  ├── hyprland.md
  ├── networking.md
  └── misc.md
```

### When to Split

A topic file should be split when it exceeds a configurable threshold
(default: ~200 lines / ~4KB). Splitting can happen:

1. **Manually** — the user edits the memory directory by hand
2. **LLM-initiated** — the system prompt instructs the LLM to
   recognize when a file is getting long and reorganize it
3. **Automatic** — `ChatService` or the Memory MCP server detects
   file size and prompts the LLM to split on the next conversation

Option 3 is the recommended approach. The Memory MCP server tracks
file sizes and includes a hint in the `memory_append` response when
a file exceeds the threshold:

```json
{
  "content": "Appended to linux.md",
  "hint": "linux.md is 247 lines. Consider splitting into subtopics."
}
```

The LLM can then use `memory_reorganize` (a higher-level tool) to
propose a split, which the user can confirm.

### Subtopic Discovery

When memory is organized into directories, `memory_list_topics`
returns a tree:

```txt
general
linux/
  linux/packages
  linux/hyprland
  linux/networking
projects/
  projects/hyprchat
  projects/theme-engine
```

`memory_read` accepts both flat topics (`general`) and nested
ones (`linux/hyprland`).

## Context Window Budget

Not all memory should be loaded into every conversation. The system
needs a strategy for selecting which memory to recall.

### Token Budget

Reserve a fixed portion of the context window for memory
(configurable, default: ~2000 tokens). This is the maximum
combined size of memory content injected into a conversation.

```json
{
  "memory": {
    "token_budget": 2000
  }
}
```

### Recall Strategy

At conversation start (or when the LLM explicitly reads memory),
the system should prioritize:

1. **Recency** — recently written or accessed memory is more likely
   to be relevant
2. **Relevance** — match the user's first message against topic
   names and memory content (keyword overlap)
3. **Frequency** — topics accessed often are likely important

For the initial implementation, keep it simple:

- The LLM calls `memory_list_topics` and `memory_read` for topics
  it thinks are relevant (self-directed recall)
- No automatic pre-loading beyond what the system prompt encourages

For a future iteration:

- `ChatService` performs a lightweight keyword match of the user's
  message against topic names
- Pre-loads the top 2–3 matches into the context as a system message
- Falls within the token budget

### Summarization

When a memory file exceeds the token budget on its own, reading it
in full would consume the entire budget. Options:

1. **Truncate** — return only the most recent N lines (simple, lossy)
2. **Summarize** — ask the LLM to summarize the file and store the
   summary alongside the original (more tokens up front, better recall)
3. **Index** — maintain a one-line summary per file that `memory_list_topics`
   returns, so the LLM can decide which files are worth reading in full

Option 3 is low-cost and effective. Each memory file can have a
front-matter summary line:

```markdown
<!-- summary: User's Hyprland configuration preferences and tips -->

- Prefer dark themes with warm accent colors
- Monitor: 2560x1440, 144Hz
- ...
```

`memory_list_topics` returns topic + summary, giving the LLM enough
to make an informed read decision without consuming tokens on
irrelevant files.

## Maintenance Tools

Additional MCP tools for memory management (beyond the basic
read/append/list/search):

| Tool | Description | Parameters |
| ---- | ----------- | ---------- |
| `memory_reorganize` | Propose splitting a large topic file | `topic` (string) |
| `memory_summary` | Read or update a file's summary line | `topic` (string), `summary` (string, optional) |
| `memory_prune` | Remove outdated entries from a topic | `topic` (string), `before_date` (string, optional) |

These are optional — not all need to ship in v1. `memory_reorganize`
and `memory_summary` are the highest priority for managing growth.

## Growth Projections

Rough estimates for memory growth:

| Usage | Monthly growth | After 1 year |
| ----- | -------------- | ------------ |
| Light (few chats/day) | ~5 KB | ~60 KB |
| Moderate (10+ chats/day) | ~20 KB | ~240 KB |
| Heavy (power user) | ~50 KB | ~600 KB |

At these sizes, the file-based approach remains viable. A database
or vector store is unnecessary for the foreseeable future.

## Configuration

```json
{
  "memory": {
    "path": "~/.config/hyprchat/memory",
    "enabled_by_default": true,
    "token_budget": 2000,
    "split_threshold_lines": 200
  }
}
```

## Open Questions

- **Who initiates splits?** The LLM (via tool hint), the server
  (automatic), or the user (manual)? Probably start with hints,
  add automatic splitting later.
- **Summary format**: Front-matter comment vs separate `.summary`
  files vs a single `_index.md`?
- **Cross-topic dedup**: Same fact might be saved under multiple
  topics. Worth detecting, or let it be?
- **Versioning**: Should memory support undo/history, or is
  append-only + manual editing enough?
