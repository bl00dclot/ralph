# Write Phase: Implementation

Implement the user story below. You have NO Read tool — all context you need is provided in this prompt.

## Current Story

{{STORY_BLOCK}}

## Pre-Digested Context

{{CONTEXT_BLOCK}}

## Instructions

1. Implement the acceptance criteria based on the context provided above
2. Follow existing patterns identified in the context
3. Commit your changes with message: `feat: {{STORY_ID}} - {{STORY_TITLE}}`
4. Do NOT update prd.json or progress.txt — a separate verify phase handles that
5. Do NOT run tests or typecheck — the verify phase handles that
6. Only use Bash for git commands (git add, git commit)

## Available Tools

You can only use: Edit, Write, and Bash (for git commands only).
You do NOT have Read access — rely entirely on the context above.
