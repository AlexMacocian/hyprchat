# File System MCP

Read/write file access for the LLM.

## Purpose

Lets the model reference and modify local code, configs, or documents.

## Scope

- Scoped to a user-configured root directory (default: `/`)
- Read and write access
- Path traversal blocked (`..` rejected)

## Tools Exposed

| Tool | Description | Parameters |
| ---- | ----------- | ---------- |
| `fs_read_file` | Read the contents of a file | `path` (string) |
| `fs_write_file` | Write content to a file, creating parent dirs | `path` (string), `content` (string) |
| `fs_list_directory` | List files and directories at a path | `path` (string) |
| `fs_search_files` | Search file names matching a glob pattern | `pattern` (string), `root` (string, optional) |

All paths must be absolute and are validated against the configured
root before access.

## Configuration

```json
{
  "file_access_enabled": true,
  "file_access_root": "/"
}
```

## Security

- **Path traversal prevention** — paths containing `..` are rejected.
  All paths checked against the allowed root.
- **Scoped access** — only files under the configured root are accessible.
- **Truncation** — files >50KB are truncated (25KB head + 25KB tail).

## Implementation

`FileService.cs` in the NativeAOT backend. Uses `System.IO` for file
operations and `ls`/`find` for directory listing and search.
