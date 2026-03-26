# HyprChat

Lightweight AI chat panel for Hyprland. Quick, disposable conversations
accessible from a keybind - no editor or browser required.

Built with [QuickShell](https://quickshell.outfoxxed.me) (Qt6/QML) as
a resident Hyprland shell widget.

- Toggle from anywhere with a keybind — no process spawn, instant show
- Multiple LLM backends: GitHub Copilot, OpenAI, Claude, Ollama, custom
- Tool use via MCP (file access, persistent memory)
- Themed by the theme engine
- ~20-40MB resident, no WebView

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

## Quick Start

### Dependencies

- [QuickShell](https://quickshell.outfoxxed.me) (0.2+)
- Node.js (for web scraper)
- gnome-keyring + libsecret (for secret storage)
- openssl (for memory encryption)

### Install

```bash
# Install system dependencies (Arch/CachyOS)
sudo pacman -S gnome-keyring libsecret nodejs npm

# Clone and install Node dependencies
cd src/scraper && npm install && cd ../..

# Symlink for development
ln -sf $(pwd)/src ~/.config/quickshell/hyprchat

# Or copy for production
mkdir -p ~/.config/quickshell/hyprchat
cp -r src/* ~/.config/quickshell/hyprchat/

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
