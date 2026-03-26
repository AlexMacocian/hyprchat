# Profiles

AI personality profiles for HyprChat.

## Overview

Profiles let you define named AI personalities, each with a custom
system prompt, backend, and model. Switch between them instantly
from the top bar.

## What's in a Profile

| Field | Description | Example |
| ----- | ----------- | ------- |
| `name` | Display name | "Steve" |
| `backend` | Which provider to use | "copilot" |
| `model` | Which model to use | "claude-opus-4.6" |
| `systemPrompt` | Personality + instructions | "You are Steve, a senior systems engineer..." |
| `icon` | Optional emoji/icon | "🔧" |

## Default Profile

HyprChat ships with a single default profile:

```json
{
  "name": "Assistant",
  "backend": "copilot",
  "model": "gpt-4o",
  "systemPrompt": "You are a helpful assistant. Be concise.",
  "icon": "🤖"
}
```

This profile is used when no other is selected. It can be edited but
not deleted.

## Example Profiles

```json
[
  {
    "name": "Steve",
    "backend": "copilot",
    "model": "claude-opus-4.6",
    "systemPrompt": "You are Steve, a senior systems engineer and Linux expert. You give precise, technical answers with command examples. You prefer minimal solutions and dislike over-engineering. When unsure, you say so.",
    "icon": "🔧"
  },
  {
    "name": "Coraline",
    "backend": "copilot",
    "model": "gpt-4o",
    "systemPrompt": "You are Coraline, a warm and imaginative storyteller. You speak with a gentle, encouraging tone. You love fantasy, mythology, and creative writing. You use vivid metaphors and occasionally weave small stories into your answers.",
    "icon": "✨"
  },
  {
    "name": "Code Review",
    "backend": "copilot",
    "model": "claude-sonnet-4-20250514",
    "systemPrompt": "You are a strict code reviewer. Point out bugs, security issues, and style problems. Be direct and specific. Suggest fixes with code snippets.",
    "icon": "🔍"
  }
]
```

## Storage

Profiles are stored in the preferences file alongside other settings:

```json
{
  "active_profile": "Steve",
  "profiles": [
    { "name": "Assistant", "backend": "copilot", "model": "gpt-4o", ... },
    { "name": "Steve", ... },
    { "name": "Coraline", ... }
  ],
  ...other preferences...
}
```

## UI

### Profile Switcher (Top Bar)

The current profile name + icon is shown in the top bar (replacing
the plain backend/model label). Clicking it opens a dropdown listing
all profiles. Select one to switch immediately.

Switching a profile:

- Changes the system prompt
- Changes the backend + model on the fly
- Starts a new chat (clears conversation)
- Re-authenticates if the backend changed

### Profile Editor (Preferences)

The Preferences view includes a "Profiles" section where you can:

- **View** all profiles in a list
- **Create** a new profile (name, icon, backend, model, system prompt)
- **Edit** any profile's fields
- **Delete** a profile (except the default)
- **Duplicate** a profile as a starting point

Each profile's backend and model can be selected from the same
backend switcher / model fetcher used in the top bar.

## Interaction with Other Features

### Memory

Memory is **shared across all profiles**. All personalities read
from and write to the same memory files. This means Steve can recall
what you told Coraline.

If per-profile memory isolation is desired in the future, memory
topics could be namespaced (e.g. `steve/user`, `coraline/user`).
For now, shared memory is simpler and more useful.

### Context Management

Each profile's system prompt is what gets assembled into the full
prompt (with memory instructions, tool prompts, etc. appended).
Summarization and context window management work the same regardless
of profile.

### Tools

Tool availability (memory, web search, shell) is controlled by
global preferences, not per-profile. All profiles have access to
the same tools when enabled.

## Implementation Notes

- The `Preferences` service stores profiles as a JSON array
- `activeProfile` property points to the current profile name
- On profile switch, `ChatWindow` updates `backend.systemPrompt`,
  `backend.model`, and re-authenticates if the backend changed
- The backend/model label in the top bar becomes the profile
  name + icon
- The `BackendSwitcher` dropdown is replaced by (or merged with)
  the profile switcher
