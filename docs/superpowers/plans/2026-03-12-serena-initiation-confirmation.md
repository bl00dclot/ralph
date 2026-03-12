# Serena Initiation Confirmation Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Emit a visible confirmation line (or warning) after each read/verify phase showing whether Serena was activated and on which project root.

**Architecture:** Prompt templates instruct the AI to emit a `[SERENA_INIT: <path>]` sentinel as its first output. After each phase, `ralph.sh` greps the log for that sentinel and compares against `$PROJECT_ROOT`. A helper function `check_serena_init` handles detection and output. Guarded behind `SERENA_AVAILABLE`.

**Tech Stack:** Bash, bats (test framework), existing mock claude at `tests/mocks/claude`

---

## Chunk 1: Tests + Implementation

### Task 1: Write failing tests for `check_serena_init`

**Files:**
- Create: `tests/serena_init.bats`

- [ ] **Step 1: Create the test file**

```bash
cat > tests/serena_init.bats << 'EOF'
#!/usr/bin/env bats

load test_helper

@test "serena init confirmed when sentinel matches project root" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="serena_init_match"

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" == *"Serena: active on"*"✓"* ]]
}

@test "serena init warns on project root mismatch" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="serena_init_mismatch"

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" == *"WARNING: Serena active on"*"expected"* ]]
}

@test "serena init warns when sentinel absent" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" == *"WARNING: Serena initiation not confirmed in read phase"* ]]
}

@test "serena init skipped when serena unavailable" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"
  # Remove serena-mcp.json so SERENA_AVAILABLE stays false
  rm -f "$RALPH_DIR/serena-mcp.json"

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" != *"Serena: active"* ]]
  [[ "$output" != *"WARNING: Serena initiation"* ]]
}

@test "serena init confirmed for verify phase" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="serena_init_match"

  run "$RALPH_DIR/ralph.sh" 1

  # Should appear twice: once for read, once for verify
  COUNT=$(echo "$output" | grep -c "Serena: active on.*✓" || true)
  [ "$COUNT" -ge 2 ]
}
EOF
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
npm test 2>&1 | grep -E "not ok.*serena"
```

Expected: 5 failing tests (behaviors not yet implemented)

---

### Task 2: Add `serena_init_match` and `serena_init_mismatch` mock behaviors

**Files:**
- Modify: `tests/mocks/claude`

The mock needs to know the actual `PROJECT_ROOT` to emit a matching or mismatching path. Ralph exports no env var with this value, but the mock can derive it by finding the git root of its own working directory — which in tests is `TEST_DIR/repo`, the same value ralph computes for `PROJECT_ROOT`.

- [ ] **Step 1: Replace the flat `read)` block with a behavior-aware nested case**

The existing `read)` arm (lines 61–74 of `tests/mocks/claude`) is a flat block that always emits the same output regardless of `$BEHAVIOR`. Replace the entire arm — from `read)` through its closing `;;` — with this nested case structure:

```bash
  read)
    # Compute actual project root the same way ralph.sh does
    ACTUAL_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "/unknown")"
    case "$BEHAVIOR" in
      serena_init_match)
        echo "[SERENA_INIT: $ACTUAL_ROOT]"
        echo "### Relevant Files"
        echo "- src/main.ts: Main entry point"
        echo ""
        echo "### Key Symbols"
        echo "- function main(): entry point"
        echo ""
        echo "### Code Snippets"
        echo "No specific snippets needed."
        echo ""
        echo "### Implementation Notes"
        echo "Follow existing patterns."
        ;;
      serena_init_mismatch)
        echo "[SERENA_INIT: /wrong/path]"
        echo "### Relevant Files"
        echo "- src/main.ts: Main entry point"
        echo ""
        echo "### Key Symbols"
        echo "- function main(): entry point"
        echo ""
        echo "### Code Snippets"
        echo "No specific snippets needed."
        echo ""
        echo "### Implementation Notes"
        echo "Follow existing patterns."
        ;;
      *)
        echo "### Relevant Files"
        echo "- src/main.ts: Main entry point"
        echo ""
        echo "### Key Symbols"
        echo "- function main(): entry point"
        echo ""
        echo "### Code Snippets"
        echo "No specific snippets needed."
        echo ""
        echo "### Implementation Notes"
        echo "Follow existing patterns."
        ;;
    esac
    ;;
```

- [ ] **Step 2: Add `serena_init_match` to the verify phase block**

The verify phase also needs to emit the sentinel when `BEHAVIOR=serena_init_match`. Find the `verify)` case block and add a case for `serena_init_match` that emits the sentinel then runs the `pass` logic:

```bash
      serena_init_match)
        ACTUAL_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "/unknown")"
        echo "[SERENA_INIT: $ACTUAL_ROOT]"
        echo "Ralph verify phase: checking acceptance criteria..."
        if [ -n "$MOCK_PRD_FILE" ] && [ -f "$MOCK_PRD_FILE" ]; then
          NEXT_ID=$(jq -r '[.userStories[] | select(.passes != true)] | sort_by(.priority) | .[0].id // empty' "$MOCK_PRD_FILE")
          if [ -n "$NEXT_ID" ]; then
            jq --arg id "$NEXT_ID" '(.userStories[] | select(.id == $id)).passes = true' "$MOCK_PRD_FILE" > "$MOCK_PRD_FILE.tmp"
            mv "$MOCK_PRD_FILE.tmp" "$MOCK_PRD_FILE"
            echo "Verified $NEXT_ID: all criteria passed."
          fi
        fi
        ;;
```

Also add `serena_init_mismatch` to verify (same as above but with `/wrong/path`):

```bash
      serena_init_mismatch)
        echo "[SERENA_INIT: /wrong/path]"
        echo "Ralph verify phase: checking acceptance criteria..."
        echo "Verification failed: criteria not met."
        ;;
```

- [ ] **Step 3: Run the new tests again — they should still fail (function not yet in ralph.sh)**

```bash
npm test 2>&1 | grep -E "not ok.*serena"
```

Expected: still failing (mock now emits sentinel but ralph.sh doesn't check for it yet)

---

### Task 3: Add `check_serena_init` to `ralph.sh`

**Files:**
- Modify: `ralph.sh`

- [ ] **Step 1: Add the function after `build_serena_config`**

Find the line `build_serena_config() {` block (around line 207). Add `check_serena_init` immediately after it:

```bash
check_serena_init() {
  local phase_name="$1"
  local log_file="$2"
  local match
  match=$(grep -oE '\[SERENA_INIT: [^]]+\]' "$log_file" | head -1)
  if [ -n "$match" ]; then
    local reported_root="${match#\[SERENA_INIT: }"
    reported_root="${reported_root%\]}"
    if [ "$reported_root" = "$PROJECT_ROOT" ]; then
      echo "  Serena: active on $reported_root ✓"
    else
      echo "  WARNING: Serena active on $reported_root (expected $PROJECT_ROOT)"
    fi
  else
    echo "  WARNING: Serena initiation not confirmed in $phase_name phase"
  fi
}
```

- [ ] **Step 2: Run tests — serena_init tests should still fail (calls not wired yet)**

```bash
npm test 2>&1 | grep -E "not ok.*serena"
```

Expected: still failing

---

### Task 4: Wire `check_serena_init` into the main loop

**Files:**
- Modify: `ralph.sh`

- [ ] **Step 1: Add call after read phase**

Find this block in the main loop:

```bash
  run_phase_with_retry "read" "$READ_LOG" "$CONTEXT_FILE"

  # Verify context was produced
```

Add the check between them:

```bash
  run_phase_with_retry "read" "$READ_LOG" "$CONTEXT_FILE"
  [ "$SERENA_AVAILABLE" = "true" ] && check_serena_init "read" "$READ_LOG"

  # Verify context was produced
```

- [ ] **Step 2: Add call after verify phase**

Find this block:

```bash
  run_phase_with_retry "verify" "$VERIFY_LOG"

  # --- Contract guard ---
```

Add the check between them:

```bash
  run_phase_with_retry "verify" "$VERIFY_LOG"
  [ "$SERENA_AVAILABLE" = "true" ] && check_serena_init "verify" "$VERIFY_LOG"

  # --- Contract guard ---
```

- [ ] **Step 3: Run tests — serena_init tests should now pass**

```bash
npm test 2>&1 | grep -E "not ok|ok.*serena"
```

Expected: all 5 serena_init tests pass

---

### Task 5: Add `activate_project` and `get_current_config` to `SERENA_READ_TOOLS`

**Files:**
- Modify: `ralph.sh`

- [ ] **Step 1: Find and extend the variable**

Find line:
```bash
SERENA_READ_TOOLS="mcp__plugin_serena_serena__get_symbols_overview ...
```

Append the two new tools to the end of the string:

```bash
SERENA_READ_TOOLS="mcp__plugin_serena_serena__activate_project mcp__plugin_serena_serena__get_current_config mcp__plugin_serena_serena__get_symbols_overview mcp__plugin_serena_serena__find_symbol mcp__plugin_serena_serena__read_file mcp__plugin_serena_serena__list_dir mcp__plugin_serena_serena__search_for_pattern mcp__plugin_serena_serena__find_referencing_symbols mcp__plugin_serena_serena__find_file"
```

- [ ] **Step 2: Run full test suite to confirm nothing broke**

```bash
npm test 2>&1 | grep -E "not ok|^1\.\."
```

Expected: `1..60` (or updated count) with zero `not ok` lines

---

### Task 6: Update prompt templates

**Files:**
- Modify: `prompts/read-phase.md`
- Modify: `prompts/verify-phase.md`

- [ ] **Step 1: Add Step 0 to `prompts/read-phase.md`**

After the `# Read Phase: Codebase Survey` heading and before `## Current Story`, insert:

```markdown
## Step 0: Initialize Serena
Before anything else:
1. Call `activate_project` to initialize Serena on this project
2. Call `get_current_config` to confirm the active project root
3. Output exactly this line (no extra whitespace):
   [SERENA_INIT: <project_root_value_from_get_current_config>]

```

- [ ] **Step 2: Add Step 0 to `prompts/verify-phase.md`**

Apply the same insertion at the top of `prompts/verify-phase.md`, before the first existing section heading.

- [ ] **Step 3: Run full test suite to confirm nothing broke**

```bash
npm test 2>&1 | grep -E "not ok|^1\.\."
```

Expected: all tests pass (prompt templates are not tested in bats)

---

### Task 7: Commit

- [ ] **Step 1: Stage all changed files**

```bash
git add ralph.sh prompts/read-phase.md prompts/verify-phase.md tests/serena_init.bats tests/mocks/claude
```

- [ ] **Step 2: Commit**

```bash
git commit -m "feat: confirm Serena initiation and project root per phase"
```

- [ ] **Step 3: Verify clean state**

```bash
git status
```

Expected: `nothing to commit, working tree clean`
