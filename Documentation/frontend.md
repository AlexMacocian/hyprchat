# Frontend

QML UI, theming, and Hyprland integration.

## UI Overview

Minimal chat interface implemented as QML components in
`src/hyprchat-ui/`:

- **Chat area** — `ListView` with a `ListModel` of messages. Markdown
  rendered via Qt's built-in `TextEdit.MarkdownText` (Qt 6.5+).
- **Input bar** — `TextArea` at the bottom. Enter to send,
  Shift+Enter for newline. Stop button during streaming.
- **Top bar** — Profile switcher, backend/model label, sign-out
  button, memory viewer toggle, preferences toggle.
- **Memory viewer** — overlay panel for browsing, reading, editing,
  and deleting memory topics (fetches from backend via JSON-RPC).
- **Preferences** — scrollable overlay for tool toggles, thresholds,
  profile management.

## QML Components

| File | Purpose |
| ---- | ------- |
| `shell.qml` | Entry point — `ShellRoot` with `ChatWindow` |
| `ChatWindow.qml` | Main window — layout, orchestration, auth |
| `BackendProcess.qml` | JSON-RPC bridge to the NativeAOT backend |
| `ChatView.qml` | Scrollable message list |
| `MessageBubble.qml` | Single message with markdown rendering |
| `InputBar.qml` | Text input with key handling |
| `BackendSwitcher.qml` | Backend/model selection dropdown |
| `ProfileSwitcher.qml` | Profile selection dropdown |
| `MemoryView.qml` | Memory browser/editor panel |
| `PreferencesView.qml` | Settings panel (scrollable) |
| `ApiKeyPrompt.qml` | API key entry prompt |
| `GhLoginFlow.qml` | GitHub OAuth device flow UI |
| `Preferences.qml` | Preferences persistence (JSON file) |
| `Theme.qml` | Theme singleton — colors/fonts |

## Hyprland Integration

QuickShell runs as a resident daemon. Toggle with:

```conf
bind = $mainMod, G, global, hyprchat:toggle
```

The panel is a `FloatingWindow` (Wayland layer-shell surface) — not
managed by the tiling layout. 700×500, centered.

## Theme

Themed via `~/.config/hyprchat/theme.jsonc`. Watched for live reload
via `inotifywait`. If missing, created with defaults.

```jsonc
{
  "bg0": "#0F0808",
  "bg1": "#1C1210",
  "bg2": "#2D1F1A",
  "bg3": "#3E2C25",
  "border": "#C23A22",
  "accent1": "#D4391E",
  "accent2": "#E07A30",
  "text": "#E8CFC0",
  "textDim": "#A08070",
  "fontFamily": "JetBrainsMono Nerd Font",
  "fontSize": 12
}
```

`Theme.qml` loads this file and exposes each value as a QML property.
All UI components bind to `Theme.bg0`, `Theme.accent1`, etc.
