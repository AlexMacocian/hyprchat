# Date & Time MCP

Real-time date and time tools for the LLM.

## Purpose

LLMs have no real-time clock — they cannot reliably tell today's date,
determine what day of the week a date falls on, or perform date
arithmetic. These tools give the model ground-truth access to date
and time information.

## Tools Exposed

| Tool | Description | Parameters |
| ---- | ----------- | ---------- |
| `date_now` | Current date/time with timezone and day of week | *(none)* |
| `date_info` | Day of week, ISO week number, day of year, leap year | `date` (string, YYYY-MM-DD) |
| `date_diff` | Number of days between two dates (with weeks breakdown) | `date1`, `date2` (strings, YYYY-MM-DD) |
| `date_add` | Add or subtract days from a date | `date`, `days` (integer, negative to subtract) |

## Configuration

Enabled by default. Toggle in Preferences under "Date & Time".

```json
{
  "date_enabled": true
}
```

## Security

- **Read-only** — only reads the system clock, never modifies it.
- **No I/O** — pure computation, no subprocesses or file access.

## Implementation

Handled in `ToolDispatcher.cs` in the NativeAOT backend using
`DateTimeOffset` and `System.Globalization` APIs.
