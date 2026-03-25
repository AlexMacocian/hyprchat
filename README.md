# HyprChat

Lightweight AI chat panel for Hyprland. Quick, disposable conversations
accessible from a keybind — no editor or browser required.

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
- [Frontend](Documentation/frontend.md) - QML UI, theming, Hyprland integration
- [Backend Implementation](Documentation/backend-implementation.md) - ChatService,
tool-use loop, configuration
- [System Prompt](Documentation/system-prompt.md) - prompt assembly,
memory instructions, tool guidance
- [Memory](Documentation/memory.md) — persistent memory overview,
per-conversation toggle
- [Memory Management](Documentation/memory-management.md) - segmentation,
growth control, token budgets
- [MCP Support](Documentation/mcp.md) - MCP architecture,
transport, tool execution flow
- [File System MCP](Documentation/mcp-filesystem.md) - read-only file access server
- [Memory MCP](Documentation/mcp-memory.md) — persistent memory server and tools

## Quick Start

```bash
# Install QuickShell first (https://quickshell.outfoxxed.me)

# Install HyprChat as a QuickShell module
mkdir -p ~/.config/quickshell/hyprchat
cp -r qml/ cpp/ shell.qml ~/.config/quickshell/hyprchat/

# Or symlink for development
ln -sf $(pwd) ~/.config/quickshell/hyprchat

# Build C++ plugin
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
cmake --build .

# Launch
quickshell -m hyprchat
```

Add to your Hyprland config:

```conf
bind = $mainMod, G, global, hyprchat:toggle
```

## Configuration

`~/.config/hyprchat/config.json` - see
[Backend Implementation](Documentation/backend-implementation.md#configuration)
for the full schema.

## License

TODO
