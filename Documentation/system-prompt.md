# System Prompt

How HyprChat constructs the system prompt sent to the LLM.

## Structure

The system prompt is assembled by `SystemPromptBuilder.cs` before
each conversation turn:

1. **Base system prompt** — user-configured per profile
2. **Memory instructions** — appended when memory is enabled
3. **Web search instructions** — appended when web search is enabled
4. **Shell instructions** — appended when shell is enabled
5. **File access instructions** — appended when file access is enabled
6. **Date instructions** — appended when date tools are enabled

Each block is omitted entirely when its feature is disabled.

## Memory Instructions

Prescriptive instructions that tell the LLM to proactively use memory:

- **Step 1**: Always read memory first (list topics, read relevant ones)
- **Step 2**: Always save new information (append or edit)
- **Step 3**: Organize memory (broad topics, split when >200 lines)

## Tool Prompts

Each enabled tool category adds a brief instruction block:

- **Web**: "Use web_search for current events, cite sources with URLs"
- **Shell**: "Use shell_exec/shell_exec_background, show commands, confirm destructive ops"
- **File**: "Use fs_read/write/list/search, paths must be absolute"
- **Date**: "Use date tools instead of guessing, training data has no real-time info"

## Context Summary

When summarization has occurred, the summary is injected as a second
system message: `"Previous conversation summary:\n" + summary`

## Customization

The base prompt is fully user-controlled via profiles. The tool
instruction blocks are built into `SystemPromptBuilder.cs`. Memory
instructions are prescriptive — they tell the LLM to use memory
proactively rather than waiting to be asked.
