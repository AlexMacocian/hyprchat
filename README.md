# HyprChat

Lightweight AI chat panel for Hyprland. Quick, disposable conversations
accessible from a keybind - no editor or browser required.

Built with [QuickShell](https://quickshell.outfoxxed.me) (Qt6/QML) as
a resident Hyprland shell widget, with a NativeAOT .NET backend for
LLM streaming, tool execution, and services.

- Toggle from anywhere with a keybind - no process spawn, instant show
- Multiple LLM backends: GitHub Copilot, OpenAI, Claude, Ollama, custom
- Tool use via MCP (file access, persistent memory, web search, shell, date/time)
- NativeAOT backend — single 11MB binary, no runtime dependencies
- Themed using theme.jsonc file

## Documentation

- [Architecture](Documentation/architecture.md) - system overview,
components, tech stack, project structure
- [Backends & Models](Documentation/backends.md) - LLM provider interface,
tool support, API details
- [Authentication](Documentation/authentication.md) - API key management,
keyring integration, sign-out
- [Frontend](Documentation/frontend.md) - QML UI, theming, Hyprland integration
- [Profiles](Documentation/profiles.md) - AI personality profiles,
per-profile backend/model/prompt
- [Backend Implementation](Documentation/backend-implementation.md) - ChatService,
tool-use loop, configuration
- [System Prompt](Documentation/system-prompt.md) - prompt assembly,
memory instructions, tool guidance
- [Memory](Documentation/memory.md) — persistent memory overview,
per-conversation toggle
- [Memory Management](Documentation/memory-management.md) - segmentation,
growth control, token budgets
- [Context Management](Documentation/context-management.md) - memory-aware
summarization, context window strategy
- [MCP Support](Documentation/mcp.md) - MCP architecture,
transport, tool execution flow
- [File System MCP](Documentation/mcp-filesystem.md) - read-only file access server
- [Memory MCP](Documentation/mcp-memory.md) — persistent memory server and tools
- [Shell MCP](Documentation/mcp-shell.md) — terminal command execution,
visible terminal window
- [Web MCP](Documentation/mcp-web.md) — internet search, reranking, and page scraping
- [Date MCP](Documentation/mcp-date.md) — real-time date/time, day-of-week,
date arithmetic

## Quick Start

### Install from AUR

```bash
paru -S hyprchat
```

### Manual Install

#### Dependencies

- [QuickShell](https://quickshell.outfoxxed.me) (0.2+)
- .NET SDK 10+ (build only — NativeAOT binary has no runtime dependency)
- gnome-keyring + libsecret (for secret storage)
- openssl (for memory encryption)
- inotify-tools (for shell command completion detection)
- kitty (for shell MCP terminal)

### Install

```bash
# Install system dependencies (Arch/CachyOS)
sudo pacman -S gnome-keyring libsecret openssl inotify-tools kitty dotnet-sdk

# Clone and build the NativeAOT backend
cd src/hyprchat-backend && dotnet publish -c Release && cd ../..

# Symlink for development
ln -sf $(pwd)/src/hyprchat-ui ~/.config/quickshell/hyprchat

# Or copy for production
mkdir -p ~/.config/quickshell/hyprchat
cp -r src/hyprchat-ui/* ~/.config/quickshell/hyprchat/

# Launch
quickshell -c hyprchat
```

Add to your Hyprland config:

```conf
bind = $mainMod, G, global, hyprchat:toggle
```

## Configuration

`~/.config/hyprchat/config.json` - see
[Backend Implementation](Documentation/backend-implementation.md#configuration)
for the full schema.
