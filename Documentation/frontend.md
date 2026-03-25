# Frontend

QML UI, theming, and Hyprland integration.

## UI Overview

Minimal chat interface implemented as QML components:

- **Chat area** — `ListView` with a `ListModel` of messages. Markdown
  rendered via Qt's built-in `TextEdit.MarkdownText` format (Qt 6.5+).
  User messages right-aligned, assistant messages left-aligned.
- **Input bar** — `TextArea` at the bottom. Enter to send, Shift+Enter
  for newline. Escape to toggle the window closed.
- **Backend indicator** — `Label` in the top bar showing active
  backend + model. Click opens a popup to switch backends.
- **New chat** — button or Ctrl+N. Clears the message model, keeps
  the window open.

No sidebar, no chat history browser, no settings panels beyond the
backend switcher. Configuration lives in the JSON file.

## QML Components

| File | Purpose |
| ---- | ------- |
| `ChatWindow.qml` | Main panel window — layer-shell surface, layout container |
| `ChatView.qml` | Scrollable message list (`ListView` + `ListModel`) |
| `MessageBubble.qml` | Single message display with markdown rendering |
| `InputBar.qml` | Text input area with key handling |
| `BackendSwitcher.qml` | Backend selection popup |
| `Theme.qml` | Theme singleton — exposes color/font properties |

## Hyprland Integration

QuickShell runs as a resident daemon and communicates with Hyprland
over its IPC socket (`$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`).

### Keybind Toggle

The keybind dispatches to QuickShell directly — no window rules needed:

```conf
bind = $mainMod, G, exec, quickshell -m hyprchat toggle
```

QuickShell receives the `toggle` message and shows/hides the panel
window. The panel is a Wayland layer-shell surface, so Hyprland
doesn't tile it — it floats above everything by default.

Alternatively, use Hyprland's `global` keybind feature to dispatch
directly without exec:

```conf
bind = $mainMod, G, global, hyprchat:toggle
```

QuickShell listens for the global shortcut and toggles visibility.

### Window Behavior

- **Layer shell surface** — floats above all windows, not managed by
  the tiling layout
- **Centered** — positioned at screen center via anchor + margin
  calculations, or via QuickShell's `PanelWindow` anchoring
- **Focus on show** — grabs keyboard focus when toggled visible
- **Size** — 700×500, fixed

No `windowrulev2` entries needed in the Hyprland config.

### Event Listener (socket2)

HyprChat listens on Hyprland's event socket
(`$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock`)
for compositor events. This is a persistent connection maintained for
the lifetime of the daemon.

Handled events:

| Event | Action |
| ----- | ------ |
| `configreloaded` | Re-read theme JSON, re-read HyprChat config |

The event listener is generic — additional events can be handled as
needed (e.g. `activewindowv2`, `workspace` for future features).

## Theme Integration

Themed via a JSON file, similar to how VS Code loads color themes.
HyprChat reads its theme JSON at startup and re-reads it when a
`configreloaded` event arrives on socket2 (see
[Event Listener](#event-listener-socket2) above).

```json
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

A `Theme` singleton loads this file and exposes each value as a
QML property. All UI components bind to `Theme.bg0`, `Theme.accent1`,
etc. If the theme file is missing, built-in defaults are used.
