# Data Precision Guard Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add snapshot-based diff guard to ralph.sh that detects when the AI mutates immutable prd.json fields, completes multiple stories in one iteration, or reverts completed work.

**Architecture:** Before each iteration, snapshot prd.json. After each iteration, diff snapshot vs current. Only `passes` (false→true, max 1 per iteration) and `notes` may change. Violations restore the snapshot and exit 3. A lockfile prevents concurrent execution. The promise tag completion path is removed.

**Tech Stack:** Bash, jq, BATS (testing)

---

### Task 1: Add .ralph/ to .gitignore

**Files:**
- Modify: `/.gitignore`

**Step 1: Add .ralph/ entry**

Add `.ralph/` to `.gitignore` so runtime state is never committed.

```gitignore
node_modules/
logs/
*.log
.ralph/
```

**Step 2: Commit**

```bash
git add .gitignore
git commit -m "chore: add .ralph/ to gitignore"
```

---

### Task 2: Add schema validation fixture and test

**Files:**
- Create: `tests/fixtures/bad-schema-prd.json`
- Create: `tests/fixtures/bad-types-prd.json`
- Modify: `tests/preflight.bats`

**Step 1: Create bad-schema fixture (missing required fields)**

```json
{
  "project": "TestProject",
  "branchName": "ralph/test",
  "description": "Missing fields in stories",
  "userStories": [
    {
      "id": "US-001",
      "title": "Has no acceptanceCriteria or priority"
    }
  ]
}
```

**Step 2: Create bad-types fixture (wrong types)**

```json
{
  "project": "TestProject",
  "branchName": "ralph/test",
  "description": "Wrong types",
  "userStories": [
    {
      "id": "US-001",
      "title": "Wrong types",
      "description": "Test",
      "acceptanceCriteria": "should be array not string",
      "priority": "high",
      "passes": "yes",
      "notes": ""
    }
  ]
}
```

**Step 3: Write failing tests**

Add to `tests/preflight.bats`:

```bash
@test "fails when story is missing required fields" {
  use_fixture "bad-schema-prd.json"
  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema invalid"* ]]
}

@test "fails when story fields have wrong types" {
  use_fixture "bad-types-prd.json"
  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema invalid"* ]]
}
```

**Step 4: Run tests to verify they fail**

```bash
npm test -- tests/preflight.bats
```

Expected: 2 new tests FAIL (schema validation not yet implemented).

**Step 5: Commit fixtures and tests**

```bash
git add tests/fixtures/bad-schema-prd.json tests/fixtures/bad-types-prd.json tests/preflight.bats
git commit -m "test: add schema validation test fixtures and failing tests"
```

---

### Task 3: Implement schema validation in ralph.sh

**Files:**
- Modify: `ralph.sh` (after line 96, before the dirty-tree warning)

**Step 1: Add validate_schema function**

Insert after the `STORY_COUNT` check (line 97) and before the dirty-tree warning (line 99). This function checks every story has the required fields with correct types.

```bash
# --- Schema validation ---
SCHEMA_ERRORS=$(jq -r '
  [.userStories[] | {
    id: .id,
    missing: (
      [
        (if (.id | type) != "string" then "id must be string" else empty end),
        (if (.title | type) != "string" then "title must be string" else empty end),
        (if (.description | type) != "string" then "description must be string" else empty end),
        (if (.acceptanceCriteria | type) != "array" then "acceptanceCriteria must be array" else empty end),
        (if (.priority | type) != "number" then "priority must be number" else empty end),
        (if (.passes | type) != "boolean" then "passes must be boolean" else empty end),
        (if has("notes") and (.notes | type) != "string" then "notes must be string" else empty end),
        (if has("id") and has("title") and has("description") and has("acceptanceCriteria") and has("priority") and has("passes") then empty else "missing required fields" end)
      ]
    )
  } | select(.missing | length > 0) | "\(.id // "unknown"): \(.missing | join(", "))"] | join("\n")
' "$PRD_FILE")

if [ -n "$SCHEMA_ERRORS" ]; then
  echo "Error: prd.json schema invalid:"
  echo "$SCHEMA_ERRORS"
  exit 1
fi
```

**Step 2: Run the schema tests**

```bash
npm test -- tests/preflight.bats
```

Expected: All tests PASS including the 2 new ones.

**Step 3: Run full test suite to check nothing broke**

```bash
npm test
```

Expected: All existing tests still PASS.

**Step 4: Commit**

```bash
git add ralph.sh
git commit -m "feat: add prd.json schema validation in preflight"
```

---

### Task 4: Add CLAUDE.md preflight check

**Files:**
- Modify: `ralph.sh` (move PROMPT_FILE assignment up, add check)
- Modify: `tests/preflight.bats`

**Step 1: Write failing test**

Add to `tests/preflight.bats`:

```bash
@test "fails when CLAUDE.md is missing" {
  use_fixture "valid-prd.json"
  rm -f "$RALPH_DIR/CLAUDE.md"
  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDE.md not found"* ]]
}
```

**Step 2: Run test to verify it fails**

```bash
npm test -- tests/preflight.bats
```

Expected: New test FAILS (CLAUDE.md check doesn't exist yet, script crashes differently).

**Step 3: Implement the check**

In `ralph.sh`, move `PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"` from line 187 up to line 75 (after LOG_DIR), then add after the dirty-tree warning:

```bash
# Validate prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: CLAUDE.md not found at $PROMPT_FILE"
  exit 1
fi
```

**Step 4: Run tests**

```bash
npm test
```

Expected: All PASS. Note: `test_helper.bash` already creates CLAUDE.md (line 27), so existing tests are unaffected.

**Step 5: Commit**

```bash
git add ralph.sh tests/preflight.bats
git commit -m "feat: add CLAUDE.md existence check in preflight"
```

---

### Task 5: Add lockfile and cleanup trap

**Files:**
- Modify: `ralph.sh`
- Create: `tests/lockfile.bats`

**Step 1: Write failing tests**

Create `tests/lockfile.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "creates lockfile on start" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" --tool claude 1

  # Lockfile should be cleaned up after exit
  [ ! -f "$RALPH_DIR/.ralph/ralph.lock" ]
}

@test "fails when lockfile already exists with running PID" {
  use_fixture "valid-prd.json"

  mkdir -p "$RALPH_DIR/.ralph"
  # Use our own PID (which is running) to simulate active lock
  echo "pid=$$" > "$RALPH_DIR/.ralph/ralph.lock"
  echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RALPH_DIR/.ralph/ralph.lock"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Another Ralph instance is running"* ]]
}

@test "ignores stale lockfile from dead process" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  mkdir -p "$RALPH_DIR/.ralph"
  # Use a PID that definitely doesn't exist
  echo "pid=99999" > "$RALPH_DIR/.ralph/ralph.lock"
  echo "started=2025-01-01T00:00:00Z" >> "$RALPH_DIR/.ralph/ralph.lock"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  # Should proceed (stale lock cleaned up), not exit 1 for lock
  [[ "$output" != *"Another Ralph instance is running"* ]]
}
```

**Step 2: Run tests to verify they fail**

```bash
npm test -- tests/lockfile.bats
```

Expected: All 3 FAIL.

**Step 3: Implement lockfile logic in ralph.sh**

Add after the dirty-tree warning and CLAUDE.md check, before dry-run:

```bash
# --- Lockfile ---
RALPH_STATE_DIR="$SCRIPT_DIR/.ralph"
LOCKFILE="$RALPH_STATE_DIR/ralph.lock"

cleanup() {
  rm -f "$LOCKFILE"
}
trap cleanup EXIT

mkdir -p "$RALPH_STATE_DIR"

if [ -f "$LOCKFILE" ]; then
  LOCK_PID=$(grep '^pid=' "$LOCKFILE" | cut -d= -f2)
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    echo "Error: Another Ralph instance is running (PID $LOCK_PID)"
    # Don't clean up someone else's lock on exit
    trap - EXIT
    exit 1
  else
    echo "Warning: Removing stale lockfile (PID $LOCK_PID not running)"
    rm -f "$LOCKFILE"
  fi
fi

echo "pid=$$" > "$LOCKFILE"
echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$LOCKFILE"
```

**Step 4: Run tests**

```bash
npm test
```

Expected: All PASS.

**Step 5: Commit**

```bash
git add ralph.sh tests/lockfile.bats
git commit -m "feat: add lockfile to prevent concurrent execution"
```

---

### Task 6: Add snapshot + diff guard - mock behaviors

**Files:**
- Modify: `tests/mocks/claude`
- Create: `tests/fixtures/valid-prd-3-incomplete.json`

**Step 1: Add new mock behaviors**

Add to `tests/mocks/claude` case statement:

```bash
  mutate)
    # Mutate an immutable field (change a story title)
    echo "Ralph iteration: implementing story..."
    if [ -n "$MOCK_PRD_FILE" ] && [ -f "$MOCK_PRD_FILE" ]; then
      NEXT_ID=$(jq -r '[.userStories[] | select(.passes != true)] | sort_by(.priority) | .[0].id // empty' "$MOCK_PRD_FILE")
      if [ -n "$NEXT_ID" ]; then
        jq --arg id "$NEXT_ID" '(.userStories[] | select(.id == $id)).title = "MUTATED TITLE" | (.userStories[] | select(.id == $id)).passes = true' "$MOCK_PRD_FILE" > "$MOCK_PRD_FILE.tmp"
        mv "$MOCK_PRD_FILE.tmp" "$MOCK_PRD_FILE"
        echo "Marked $NEXT_ID as passed (and mutated title)."
      fi
    fi
    ;;
  multi-pass)
    # Mark multiple stories as passed in one iteration
    echo "Ralph iteration: implementing ALL stories..."
    if [ -n "$MOCK_PRD_FILE" ] && [ -f "$MOCK_PRD_FILE" ]; then
      jq '(.userStories[] | select(.passes != true)).passes = true' "$MOCK_PRD_FILE" > "$MOCK_PRD_FILE.tmp"
      mv "$MOCK_PRD_FILE.tmp" "$MOCK_PRD_FILE"
      echo "Marked all stories as passed."
    fi
    ;;
  revert)
    # Revert a previously passed story
    echo "Ralph iteration: reverting story..."
    if [ -n "$MOCK_PRD_FILE" ] && [ -f "$MOCK_PRD_FILE" ]; then
      jq '(.userStories[] | select(.passes == true) | limit(1; .)).passes = false' "$MOCK_PRD_FILE" > "$MOCK_PRD_FILE.tmp"
      mv "$MOCK_PRD_FILE.tmp" "$MOCK_PRD_FILE"
      echo "Reverted a story."
    fi
    ;;
  corrupt)
    # Write invalid JSON to prd.json
    echo "Ralph iteration: corrupting prd.json..."
    if [ -n "$MOCK_PRD_FILE" ]; then
      echo "not valid json {{{" > "$MOCK_PRD_FILE"
    fi
    ;;
```

**Step 2: Create fixture with 3 incomplete stories**

`tests/fixtures/valid-prd-3-incomplete.json`:

```json
{
  "project": "TestProject",
  "branchName": "ralph/test-branch",
  "description": "Three incomplete stories",
  "userStories": [
    {
      "id": "US-001",
      "title": "First story",
      "description": "Not done",
      "acceptanceCriteria": ["Something passes"],
      "priority": 1,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-002",
      "title": "Second story",
      "description": "Not done",
      "acceptanceCriteria": ["Something else"],
      "priority": 2,
      "passes": false,
      "notes": ""
    },
    {
      "id": "US-003",
      "title": "Third story",
      "description": "Not done",
      "acceptanceCriteria": ["Another thing"],
      "priority": 3,
      "passes": false,
      "notes": ""
    }
  ]
}
```

**Step 3: Commit**

```bash
git add tests/mocks/claude tests/fixtures/valid-prd-3-incomplete.json
git commit -m "test: add mock behaviors and fixture for diff guard tests"
```

---

### Task 7: Add diff guard tests

**Files:**
- Create: `tests/guard.bats`

**Step 1: Write all guard tests**

```bash
#!/usr/bin/env bats

load test_helper

@test "exits 3 when AI mutates immutable field" {
  use_fixture "valid-prd-3-incomplete.json"
  export MOCK_CLAUDE_BEHAVIOR="mutate"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"Contract violation"* ]]
  [[ "$output" == *"mutated"* ]]
}

@test "exits 3 when AI completes multiple stories in one iteration" {
  use_fixture "valid-prd-3-incomplete.json"
  export MOCK_CLAUDE_BEHAVIOR="multi-pass"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"Contract violation"* ]]
  [[ "$output" == *"multiple stories"* ]]
}

@test "exits 3 when AI reverts a completed story" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="revert"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"Contract violation"* ]]
  [[ "$output" == *"reverted"* ]]
}

@test "exits 3 when AI corrupts prd.json" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="corrupt"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 3 ]
  [[ "$output" == *"Contract violation"* ]]
  [[ "$output" == *"no longer valid JSON"* ]]
}

@test "restores prd.json from snapshot after contract violation" {
  use_fixture "valid-prd-3-incomplete.json"
  export MOCK_CLAUDE_BEHAVIOR="mutate"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 3 ]

  # prd.json should be restored — title should NOT be mutated
  TITLE=$(jq -r '.userStories[0].title' "$RALPH_DIR/prd.json")
  [ "$TITLE" = "First story" ]
}

@test "allows valid single story completion" {
  use_fixture "valid-prd-3-incomplete.json"
  export MOCK_CLAUDE_BEHAVIOR="pass"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  # Should not be exit 3 (not a violation)
  [ "$status" -ne 3 ]
}

@test "allows notes to change without violation" {
  use_fixture "valid-prd-3-incomplete.json"

  # Create a custom mock that only changes notes
  cat > "$MOCKS/claude-notes" << 'SCRIPT'
#!/bin/bash
cat > /dev/null
if [ -n "$MOCK_PRD_FILE" ] && [ -f "$MOCK_PRD_FILE" ]; then
  jq '(.userStories[0]).notes = "AI added a note"' "$MOCK_PRD_FILE" > "$MOCK_PRD_FILE.tmp"
  mv "$MOCK_PRD_FILE.tmp" "$MOCK_PRD_FILE"
fi
echo "Added notes."
SCRIPT
  chmod +x "$MOCKS/claude-notes"
  mv "$MOCKS/claude" "$MOCKS/claude.bak"
  mv "$MOCKS/claude-notes" "$MOCKS/claude"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -ne 3 ]

  mv "$MOCKS/claude.bak" "$MOCKS/claude"
}
```

**Step 2: Run tests to verify they fail**

```bash
npm test -- tests/guard.bats
```

Expected: All 7 FAIL (guard not implemented yet).

**Step 3: Commit**

```bash
git add tests/guard.bats
git commit -m "test: add diff guard tests for contract violations"
```

---

### Task 8: Implement snapshot + diff guard in ralph.sh

**Files:**
- Modify: `ralph.sh`

**Step 1: Add snapshot before iteration**

Inside the main loop, after the iteration banner (line 193) and before running the AI tool (line 201), add:

```bash
  # --- Snapshot prd.json before iteration ---
  cp "$PRD_FILE" "$RALPH_STATE_DIR/snapshot.json"
```

Note: `RALPH_STATE_DIR` was defined in Task 5.

**Step 2: Add diff guard function**

Add this function before the main loop (after the lockfile logic, before `echo "Starting Ralph"`):

```bash
# --- Diff guard: validate AI did not violate the contract ---
check_contract() {
  local snapshot="$RALPH_STATE_DIR/snapshot.json"
  local current="$PRD_FILE"

  # Check prd.json is still valid JSON
  if ! jq empty "$current" 2>/dev/null; then
    echo ""
    echo "Contract violation: prd.json is no longer valid JSON"
    cp "$snapshot" "$current"
    echo "Restored prd.json from snapshot."
    return 1
  fi

  # Check immutable fields unchanged
  local IMMUTABLE_DIFF
  IMMUTABLE_DIFF=$(jq -n \
    --slurpfile snap "$snapshot" \
    --slurpfile curr "$current" \
    '
    ($snap[0] | {project, branchName, description}) != ($curr[0] | {project, branchName, description})
    ' 2>/dev/null)

  if [ "$IMMUTABLE_DIFF" = "true" ]; then
    echo ""
    echo "Contract violation: AI mutated immutable top-level fields"
    jq -n --slurpfile snap "$snapshot" --slurpfile curr "$current" \
      '{snapshot: ($snap[0] | {project, branchName, description}), current: ($curr[0] | {project, branchName, description})}'
    cp "$snapshot" "$current"
    echo "Restored prd.json from snapshot."
    return 1
  fi

  # Check story immutable fields
  local STORY_DIFF
  STORY_DIFF=$(jq -n \
    --slurpfile snap "$snapshot" \
    --slurpfile curr "$current" \
    '
    [range($snap[0].userStories | length)] |
    map(
      select(
        ($snap[0].userStories[.] | {id, title, description, acceptanceCriteria, priority}) !=
        ($curr[0].userStories[.] | {id, title, description, acceptanceCriteria, priority})
      ) | $snap[0].userStories[.].id
    ) | if length > 0 then . else empty end
    ' 2>/dev/null)

  if [ -n "$STORY_DIFF" ]; then
    echo ""
    echo "Contract violation: AI mutated immutable fields in stories: $STORY_DIFF"
    cp "$snapshot" "$current"
    echo "Restored prd.json from snapshot."
    return 1
  fi

  # Check no story reverted (true → false)
  local REVERTED
  REVERTED=$(jq -n \
    --slurpfile snap "$snapshot" \
    --slurpfile curr "$current" \
    '
    [range($snap[0].userStories | length)] |
    map(
      select(
        $snap[0].userStories[.].passes == true and
        $curr[0].userStories[.].passes != true
      ) | $snap[0].userStories[.].id
    ) | if length > 0 then . else empty end
    ' 2>/dev/null)

  if [ -n "$REVERTED" ]; then
    echo ""
    echo "Contract violation: AI reverted completed stories: $REVERTED"
    cp "$snapshot" "$current"
    echo "Restored prd.json from snapshot."
    return 1
  fi

  # Check at most 1 story flipped false → true
  local NEWLY_PASSED
  NEWLY_PASSED=$(jq -n \
    --slurpfile snap "$snapshot" \
    --slurpfile curr "$current" \
    '
    [range($snap[0].userStories | length)] |
    map(
      select(
        $snap[0].userStories[.].passes != true and
        $curr[0].userStories[.].passes == true
      ) | $curr[0].userStories[.].id
    )
    ' 2>/dev/null)

  local PASS_COUNT
  PASS_COUNT=$(echo "$NEWLY_PASSED" | jq 'length' 2>/dev/null || echo "0")

  if [ "$PASS_COUNT" -gt 1 ]; then
    echo ""
    echo "Contract violation: AI completed multiple stories in one iteration: $NEWLY_PASSED"
    cp "$snapshot" "$current"
    echo "Restored prd.json from snapshot."
    return 1
  fi

  return 0
}
```

**Step 3: Call the guard after each iteration**

In the main loop, after the timeout warning (line 216) and before stuck detection (line 220), add:

```bash
  # --- Contract guard ---
  if ! check_contract; then
    notify "Ralph CONTRACT VIOLATION" "AI broke the contract. Check logs."
    exit 3
  fi
```

**Step 4: Run guard tests**

```bash
npm test -- tests/guard.bats
```

Expected: All 7 PASS.

**Step 5: Run full test suite**

```bash
npm test
```

Expected: All tests PASS (existing + new).

**Step 6: Commit**

```bash
git add ralph.sh
git commit -m "feat: add snapshot + diff guard for prd.json contract enforcement"
```

---

### Task 9: Remove promise tag completion path

**Files:**
- Modify: `ralph.sh` (remove lines 257-264)
- Modify: `tests/completion.bats` (update promise test)

**Step 1: Update the promise test**

In `tests/completion.bats`, replace the promise test:

```bash
@test "ignores promise tag — only prd.json completion matters" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="promise"

  # Promise tag without all stories passed should NOT exit 0
  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 1 ]
  [[ "$output" != *"signaled completion"* ]]
}
```

**Step 2: Run test to verify it fails**

```bash
npm test -- tests/completion.bats
```

Expected: Updated test FAILS (promise logic still exists).

**Step 3: Remove promise tag logic from ralph.sh**

Delete these lines (257-264):

```bash
  # Also honor the legacy <promise> signal (grep the log file, not a variable)
  if grep -q "<promise>COMPLETE</promise>" "$ITER_LOG" 2>/dev/null; then
    echo ""
    echo "Ralph signaled completion ($PASSED/$TOTAL stories show passed in prd.json)"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    notify "Ralph DONE" "Signaled complete at iteration $i ($PASSED/$TOTAL passed)"
    exit 0
  fi
```

**Step 4: Run tests**

```bash
npm test
```

Expected: All PASS.

**Step 5: Commit**

```bash
git add ralph.sh tests/completion.bats
git commit -m "feat: remove promise tag completion — single path via prd.json only"
```

---

### Task 10: Improve archive to include logs and CLAUDE.md

**Files:**
- Modify: `ralph.sh` (archive section, lines 149-153)
- Modify: `tests/archive.bats`

**Step 1: Write failing test**

Add to `tests/archive.bats`:

```bash
@test "archives logs and CLAUDE.md when branch changes" {
  use_fixture "valid-prd.json"

  echo "ralph/old-branch" > "$RALPH_DIR/.last-branch"
  echo "# Old progress" > "$RALPH_DIR/progress.txt"
  mkdir -p "$RALPH_DIR/logs"
  echo "iteration 1 log" > "$RALPH_DIR/logs/iteration-1.log"

  export MOCK_CLAUDE_BEHAVIOR="fail"
  run "$RALPH_DIR/ralph.sh" --tool claude 1

  # Check logs were archived
  ARCHIVE_FOLDER=$(find "$RALPH_DIR/archive" -mindepth 1 -maxdepth 1 -type d | head -1)
  [ -d "$ARCHIVE_FOLDER/logs" ]
  [ -f "$ARCHIVE_FOLDER/logs/iteration-1.log" ]
  [ -f "$ARCHIVE_FOLDER/CLAUDE.md" ]
}
```

**Step 2: Run test to verify it fails**

```bash
npm test -- tests/archive.bats
```

Expected: New test FAILS.

**Step 3: Expand archive logic in ralph.sh**

Replace lines 150-152:

```bash
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
```

With:

```bash
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROMPT_FILE" ] && cp "$PROMPT_FILE" "$ARCHIVE_FOLDER/"
    [ -d "$LOG_DIR" ] && cp -r "$LOG_DIR" "$ARCHIVE_FOLDER/"
```

**Step 4: Run tests**

```bash
npm test
```

Expected: All PASS.

**Step 5: Commit**

```bash
git add ralph.sh tests/archive.bats
git commit -m "feat: archive logs and CLAUDE.md alongside prd.json"
```

---

### Task 11: Update README and help text

**Files:**
- Modify: `README.md`
- Modify: `ralph.sh` (help text, line 41-51)

**Step 1: Update help text exit codes**

In ralph.sh help section, add exit code info and update the description.

**Step 2: Update README**

Add a "Data Precision Guard" section to README.md explaining:
- What the guard checks
- Exit code 3
- The `.ralph/` directory
- That promise tag is removed
- What happens on violation (snapshot restore)

**Step 3: Commit**

```bash
git add README.md ralph.sh
git commit -m "docs: update README and help text with guard documentation"
```

---

## Summary

| Task | What | Files |
|------|------|-------|
| 1 | .gitignore | `.gitignore` |
| 2 | Schema test fixtures | `tests/fixtures/`, `tests/preflight.bats` |
| 3 | Schema validation | `ralph.sh` |
| 4 | CLAUDE.md preflight | `ralph.sh`, `tests/preflight.bats` |
| 5 | Lockfile | `ralph.sh`, `tests/lockfile.bats` |
| 6 | Guard mock behaviors | `tests/mocks/claude`, `tests/fixtures/` |
| 7 | Guard tests | `tests/guard.bats` |
| 8 | Snapshot + diff guard | `ralph.sh` |
| 9 | Remove promise tag | `ralph.sh`, `tests/completion.bats` |
| 10 | Archive improvements | `ralph.sh`, `tests/archive.bats` |
| 11 | README + help updates | `README.md`, `ralph.sh` |

All tasks are sequential — each builds on the previous.
