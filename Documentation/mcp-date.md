# Date & Time MCP

Real-time date and time tools for the LLM.

## Purpose

LLMs have no real-time clock — they cannot reliably tell today's date,
determine what day of the week a date falls on, or perform date
arithmetic. These tools give the model ground-truth access to date
and time information.

## Scope

- Pure computation — no I/O, no subprocesses
- Implemented as synchronous tools (like memory) directly in
  ChatWindow, no separate service component needed
- Uses the system clock and timezone of the host machine

## Tools Exposed

| Tool | Description | Parameters |
| ---- | ----------- | ---------- |
| `date_now` | Current date/time with timezone and day of week | *(none)* |
| `date_info` | Day of week, ISO week number, day of year, leap year for a given date | `date` (string, YYYY-MM-DD) |
| `date_diff` | Number of days between two dates (with weeks breakdown) | `date1`, `date2` (strings, YYYY-MM-DD) |
| `date_add` | Add or subtract days from a date, returns resulting date and day of week | `date`, `days` (integer, negative to subtract) |

## Configuration

Enabled by default. Toggle in Preferences under "Date & Time".

```json
{
  "date_enabled": true
}
```

## Security

- **Read-only** — only reads the system clock, never modifies it.
- **No I/O** — pure JavaScript `Date` computations, no subprocesses
  or file access.
- **No sensitive data** — only exposes date/time, not system identity
  or location beyond the configured timezone.

## Implementation

Runs as synchronous tool calls inside `ChatWindow.executeTool()`.
Uses JavaScript `Date` and `Intl.DateTimeFormat` APIs available
in the QML runtime.
