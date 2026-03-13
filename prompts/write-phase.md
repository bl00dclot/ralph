# Write Phase: Implementation

Implement the user story below. Pre-digested context is provided; you also have Read access for verifying details.

## Current Story

{{STORY_BLOCK}}

## Pre-Digested Context

{{CONTEXT_BLOCK}}

## Previous Verify Feedback

{{VERIFY_FEEDBACK}}

### How to use verify feedback

If the section above contains feedback (not empty), a previous iteration attempted
this story and failed verification. You MUST:

1. Read the feedback carefully — it contains specific error messages and fix suggestions
2. If feedback mentions files not in your pre-digested context, use Read to examine those files, then fix them
3. Do NOT declare the story complete while verify feedback lists unresolved issues
4. Address ALL failures listed, including in files outside the original context
5. Treat verify feedback as higher priority than pre-digested context — it reflects the actual current state

## Instructions

1. Implement the acceptance criteria based on the context provided above
2. Follow existing patterns identified in the context
3. Commit your changes with message: `feat: {{STORY_ID}} - {{STORY_TITLE}}`
4. Do NOT update prd.json or progress.txt — a separate verify phase handles that
5. Do NOT run tests or typecheck — the verify phase handles that
6. Only use Bash for git commands (git add, git commit)

## Available Tools

You have Read access for checking file contents before editing.
Rely primarily on the pre-digested context above for architecture
decisions — use Read only to verify specific details (imports,
exact signatures, surrounding code) before making edits.
