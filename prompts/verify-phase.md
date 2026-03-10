# Verify Phase: Acceptance Criteria Check

Verify that the user story's acceptance criteria are met by running checks and inspecting the code.

## Current Story

{{STORY_BLOCK}}

## Instructions

For each acceptance criterion, run the appropriate verification:

- **"Typecheck passes"** — run the project's typecheck command
- **"Tests pass"** — run the project's test command
- **"Lint passes"** — run the project's lint command
- **Code/schema criteria** — use Serena to inspect relevant symbols and verify they exist and are correct
- **UI criteria** — verify component structure exists with correct props/markup

### If ALL criteria pass:

1. Update prd.json: set this story's `passes` to `true`
   ```bash
   jq --arg id "{{STORY_ID}}" '(.userStories[] | select(.id == $id)).passes = true' {{PRD_FILE}} > {{PRD_FILE}}.tmp && mv {{PRD_FILE}}.tmp {{PRD_FILE}}
   ```
2. Append a success entry to progress.txt:
   ```
   ## [date] - {{STORY_ID}}: {{STORY_TITLE}}
   - Status: PASSED
   - Verified: [list each criterion and how it was verified]
   ---
   ```

### If ANY criterion fails:

1. Leave `passes` as `false` in prd.json
2. Append a failure entry to progress.txt:
   ```
   ## [date] - {{STORY_ID}}: {{STORY_TITLE}}
   - Status: FAILED
   - Failed criteria: [which ones failed and why]
   - Suggestions: [what the next iteration should fix]
   ---
   ```

## File Paths

- **PRD:** {{PRD_FILE}}
- **Progress:** {{PROGRESS_FILE}}
