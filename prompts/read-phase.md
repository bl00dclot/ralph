# Read Phase: Codebase Survey

## Step 0: Initialize Serena
Before anything else:
1. Call `activate_project` to initialize Serena on this project
2. Call `get_current_config` to confirm the active project root
3. Output exactly this line (no extra whitespace):
   [SERENA_INIT: <project_root_value_from_get_current_config>]

You are performing a READ-ONLY survey of the codebase to gather context for implementing a user story.
Output a structured analysis to stdout. Do NOT modify any files.

## Current Story

{{STORY_BLOCK}}

## Instructions

1. Use Serena tools to explore the project's symbol structure and file layout
2. Identify files and symbols directly relevant to this story's acceptance criteria
3. If acceptance criteria reference broader systems (e.g., "integrates with auth"), expand scope to understand those too
4. Focus on: function signatures, type definitions, component structure, database schemas
5. For exported functions that acceptance criteria require modifying, use `find_referencing_symbols` to discover call sites. Include callers in Relevant Files.
6. Do NOT include full file contents — summarize and extract only key snippets

## Output Format

Structure your output with these sections:

### Relevant Files
List file paths with 1-line descriptions of what they contain and why they matter.

### Key Symbols
Function, class, and type signatures that need modification or understanding.
Include the file path and line number for each.

### Code Snippets
Only the specific code blocks that the write phase needs to see.
Include file path and line numbers. Keep snippets minimal.

### Dependencies
Modules, APIs, database tables, or other systems this story depends on.

### Implementation Notes
Patterns to follow based on existing code, gotchas to avoid, and any conventions discovered.
