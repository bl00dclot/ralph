# Data Precision Design

## Problem

Ralph spawns fresh AI instances each iteration. These instances can and do:

1. **Morph prd.json format** — change field names, restructure stories, alter acceptance criteria, delete fields
2. **Complete multiple stories at once** — skip sequential workflow, making it impossible to verify each story was actually implemented
3. **Revert completed work** — flip `passes: true` back to `false`, causing re-work loops

Adding stricter schemas doesn't help — more rules just give the AI more things to break. The solution is a simple guard that detects violations after each iteration and fails fast.

## Guard Rules

### Immutable vs Mutable Fields

prd.json has two zones:

**Immutable** (AI must not change):
- `project`
- `branchName`
- `description`
- `userStories[].id`
- `userStories[].title`
- `userStories[].description`
- `userStories[].acceptanceCriteria`
- `userStories[].priority`

**Mutable** (AI may change):
- `userStories[].passes` — only `false → true`, never `true → false`
- `userStories[].notes` — free text, no restrictions

Any mutation to an immutable field is a contract violation.

### One Story Per Iteration

Each iteration may complete at most one story. If the diff shows more than one story flipped from `passes: false` to `passes: true`, that's a violation.

This enforces sequential execution: iteration 1 completes story 1, iteration 2 completes story 2, etc. The AI cannot claim to have done three stories worth of work in one context window.

### No Reversions

A story that was `passes: true` in the snapshot must still be `passes: true` after the iteration. The AI cannot undo previous work.

## Iteration Lifecycle

```
BEFORE ITERATION
  1. Create .ralph/ directory if needed
  2. Check lockfile (.ralph/ralph.lock) doesn't exist
     - If exists: another Ralph is running → exit 1
  3. Create lockfile with PID and timestamp
  4. Validate prd.json schema (field names, types)
  5. Snapshot: cp prd.json → .ralph/snapshot.json

RUN ITERATION
  6. Feed CLAUDE.md to AI tool via stdin
  7. Capture output to logs/iteration-N.log via tee

AFTER ITERATION
  8. Validate prd.json is still valid JSON
  9. Diff .ralph/snapshot.json vs prd.json:
     a. Extract immutable fields from both, compare
        - Mismatch → FAIL: report which field changed
     b. Count stories that flipped false → true
        - More than 1 → FAIL: report which stories
     c. Check no story flipped true → false
        - Any reversion → FAIL: report which story
  10. If all checks pass, continue to next iteration

ON FAILURE (contract violation)
  11. Print what changed (field name, expected vs actual)
  12. Restore prd.json from .ralph/snapshot.json
  13. Remove lockfile
  14. Exit 3

ON EXIT (any path)
  15. Remove lockfile
```

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All stories passed |
| 1 | Max iterations reached / lockfile conflict |
| 2 | Stuck — same story failed 3+ consecutive iterations |
| 3 | Contract violation — AI mutated immutable data, completed multiple stories, or reverted a pass |

## Schema Validation

Preflight validates prd.json structure before the first iteration:

- Top-level fields: `project` (string), `branchName` (string), `description` (string), `userStories` (array)
- Each story: `id` (string), `title` (string), `description` (string), `acceptanceCriteria` (array of strings), `priority` (number), `passes` (boolean), `notes` (string)
- No empty `userStories` array

This catches malformed prd.json before Ralph starts. It does not run after each iteration — the diff guard handles post-iteration validation.

## Removed: Promise Tag

The `<promise>COMPLETE</promise>` legacy completion signal is removed. There is now a single completion path: all stories in prd.json have `passes: true`.

This eliminates the contradiction where the AI could output the promise tag while only 1 of 4 stories was actually complete.

## Lockfile

`.ralph/ralph.lock` prevents concurrent Ralph instances from corrupting state. Contains PID and start timestamp. Created before first iteration, removed on exit (including crashes via trap).

## Archive Improvements

When Ralph archives a previous run (branch change), it now copies:
- `prd.json`
- `progress.txt`
- `logs/` directory
- `CLAUDE.md`

This makes archives complete enough to understand what happened in a previous run.

## Runtime Directory

`.ralph/` holds runtime state:
- `snapshot.json` — prd.json copy from before current iteration
- `ralph.lock` — lockfile

Added to `.gitignore`. Not archived (runtime-only state).

## What Triggers a Failure

| Trigger | Message | Recovery |
|---------|---------|----------|
| Immutable field changed | "Contract violation: AI mutated [field] in story [id]" | prd.json restored from snapshot |
| Multiple stories completed | "Contract violation: AI completed [N] stories in one iteration: [ids]" | prd.json restored from snapshot |
| Story reverted | "Contract violation: AI reverted [id] from passed to incomplete" | prd.json restored from snapshot |
| prd.json corrupted | "Contract violation: prd.json is no longer valid JSON" | prd.json restored from snapshot |
| Schema invalid | "Error: prd.json schema invalid — [details]" | Exit before running |
| CLAUDE.md missing | "Error: CLAUDE.md not found" | Exit before running |
| Lockfile exists | "Error: Another Ralph instance is running (PID [pid])" | Exit before running |
