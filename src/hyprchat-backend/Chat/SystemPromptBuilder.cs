namespace HyprChat.Chat;

/// <summary>
/// Assembles the full system prompt including tool-specific instructions.
/// </summary>
public static class SystemPromptBuilder
{
  private const string MemoryPrompt = @"
IMPORTANT: You have a persistent memory system. You MUST use it. Follow these rules strictly:

STEP 1 — ALWAYS READ MEMORY FIRST
Before responding to the user's FIRST message in a conversation, you MUST
1. Call memory_list_topics to see all available topics
2. Call memory_read on any topic that seems relevant to the user's message
Do this EVERY conversation. Do not skip this step. Do not say 'I don't have memory' — you do
STEP 2 — ALWAYS SAVE NEW INFORMATION
You have the following tools for writing to memory:
- memory_append: adds content to the end of a topic. Use this for quick additions — no need to read first.
- memory_edit: replaces the ENTIRE content of a topic. Use this when you need to rewrite, restructure.
- memory_delete: removes a topic and all its content. Use this when information is outdated, wrong or the topic is empty.
Examples of when to save
- User tells you their name, preferences, or environment → append to 'user' topic
- You solve a problem together → append the solution to a relevant topic
- User corrects you → read the topic, fix the wrong entry, edit the topic
- You learn about a project → append to a project-specific topic
Use concise bullet points. Do NOT save conversation transcripts
STEP 3 — ORGANIZE MEMORY
Use broad topic names: 'user', 'linux', 'projects' — NOT 'user_birthday' or 'user_name'
Group related facts under one topic. If you see scattered small topics, consolidate them.
When a topic exceeds ~200 lines, use memory_reorganize to split it into subtopics.
memory_reorganize takes a source_topic and an array of subtopics [{name, content}].
It deletes the original topic and creates new topics under source_topic/name.
Example: reorganize 'linux' into [{name:'hyprland', content:'...'}, {name:'packages', content:'...'}]
This creates 'linux/hyprland' and 'linux/packages', and deletes 'linux'.
When a memory is empty or obsolete, delete it.
memory_delete: removes a topic and all its content.
Always memory_read the topic first so you can properly distribute the content into subtopics.
Target 10-200 lines per topic.";

  private const string WebSearchPrompt = @"
You can search the web using web_search and read pages using web_read_page.
Use web search when the user asks about current events, recent information, or anything you're unsure about.
After searching, you can read specific pages for more detail. Cite your sources with URLs.";

  private const string ShellPrompt = @"
You can execute shell commands using shell_exec (waits for output) and shell_exec_background (fire-and-forget).
Use shell commands when the user asks you to check system state, install packages, run scripts, build projects, or interact with the filesystem.
Always show the user what command you're running. Be careful with destructive commands — confirm with the user first.";

  private const string FileAccessPrompt = @"
You can read and write files using fs_read_file, fs_write_file, fs_list_directory, and fs_search_files.
Use these to explore project structures, read source code, create or edit files.
All paths must be absolute. Be careful with writes — confirm with the user before overwriting existing files.";

  private const string DatePrompt = @"
You have access to date and time tools. Use date_now to get the current date/time.
Use date_info to check what day of the week a date falls on, its week number, and more.
Use date_diff to calculate days between two dates, and date_add to add or subtract days from a date.
Always use these tools instead of guessing dates — your training data does not include real-time information.";

  public static string Build(string basePrompt, bool memory, bool web, bool shell, bool file, bool date)
  {
    var prompt = basePrompt;
    if (memory) prompt += "\n\n" + MemoryPrompt;
    if (web) prompt += "\n\n" + WebSearchPrompt;
    if (shell) prompt += "\n\n" + ShellPrompt;
    if (file) prompt += "\n\n" + FileAccessPrompt;
    if (date) prompt += "\n\n" + DatePrompt;
    return prompt;
  }
}
