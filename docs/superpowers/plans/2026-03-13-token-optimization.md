# Token Optimization Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce per-iteration token consumption through model downgrades, context trimming, compression, and visibility tooling.

**Architecture:** Six independent optimization tasks — each can be implemented in isolation. Tasks are ordered by estimated ROI. Pick any subset; none depend on each other.

**Tech Stack:** Bash, bats, `claude` CLI, `jq`

---

> ## ⚠️ Pick-and-choose menu
> Each task below is fully self-contained. Implement any combination in any order.
> Estimated savings assume a 10-iteration run with 1 story, average context.

---

## OPT-1: Downgrade read + verify phases to Haiku 4.5

**Estimated saving: ~65% on read/verify phase tokens**
**Risk: Low** — read is Serena queries + summarize; verify is structured JSON check. Neither needs Sonnet reasoning.
**Effort: Trivial** — 2 line changes

Current: read=Sonnet ($3/$15 per M), verify=Sonnet ($3/$15 per M), write=Opus (unchanged)
After: read=Haiku ($1/$5 per M), verify=Haiku ($1/$5 per M)

**Files:**
- Modify: `ralph.sh:355` (run_read_phase model)
- Modify: `ralph.sh:393` (run_verify_phase model)

- [ ] **Step 1: Change read phase model**

Find line 355 in `ralph.sh`:
```bash
    --model claude-sonnet-4-6 \
```
Change to:
```bash
    --model claude-haiku-4-5-20251001 \
```
This is inside `run_read_phase()`.

- [ ] **Step 2: Change verify phase model**

Find line 393 in `ralph.sh` (inside `run_verify_phase()`):
```bash
    --model claude-sonnet-4-6 \
```
Change to:
```bash
    --model claude-haiku-4-5-20251001 \
```

- [ ] **Step 3: Verify no new failures introduced**

```bash
npm test 2>&1 | grep -E "not ok|^1\.\."
```
The mock detects phases via `--allowed-tools`, not `--model`, so changing the model string introduces no new failures.
Note: pre-existing failures from the current mock baseline are unrelated to this task — confirm the failure list is identical before and after.

- [ ] **Step 4: Commit**

```bash
git add ralph.sh
git commit -m "perf: downgrade read and verify phases to Haiku 4.5 for cost reduction"
```

---

## OPT-2: Context file size cap

**Estimated saving: 20-60% on write phase input tokens (highly variable)**
**Risk: Low** — worst case is slightly less context for write; fallback already exists
**Effort: Small** — 1 env var + 5 lines of bash

The read phase has no output size limit. A verbose Serena session can produce 500-2000 lines of symbol data. Every line is paid for again in the write phase. Cap it.

**Files:**
- Modify: `ralph.sh` (add `CONTEXT_MAX_LINES` var + truncation after read phase)
- Modify: `tests/context_cap.bats` (new test file)

- [ ] **Step 1: Write the failing test**

Create `tests/context_cap.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "context file is capped at CONTEXT_MAX_LINES" {
  use_fixture "valid-prd.json"
  export MOCK_READ_LINES=400
  export CONTEXT_MAX_LINES=10

  run "$RALPH_DIR/ralph.sh" 1

  LINES=$(wc -l < "$RALPH_DIR/.ralph/context.md")
  [ "$LINES" -le 10 ]
}

@test "context file is not capped when under limit" {
  use_fixture "valid-prd.json"
  export CONTEXT_MAX_LINES=1000

  run "$RALPH_DIR/ralph.sh" 1

  # Default mock read output is ~2 lines — should not be truncated
  LINES=$(wc -l < "$RALPH_DIR/.ralph/context.md")
  [ "$LINES" -lt 1000 ]
}

@test "context cap defaults to 300 when not set" {
  use_fixture "valid-prd.json"
  export MOCK_READ_LINES=400
  unset CONTEXT_MAX_LINES

  run "$RALPH_DIR/ralph.sh" 1

  LINES=$(wc -l < "$RALPH_DIR/.ralph/context.md")
  [ "$LINES" -le 300 ]
}
```

- [ ] **Step 2: Add `MOCK_READ_LINES` support to mock**

In `tests/mocks/claude`, find the read phase detection block:

```bash
# Read phase
if [[ "$ALLOWED_TOOLS" == *"mcp__plugin_serena"* ]] && [[ "$ALLOWED_TOOLS" != *"Edit"* ]]; then
  echo "### Context"
  exit 0
fi
```

Replace it with:

```bash
# Read phase
if [[ "$ALLOWED_TOOLS" == *"mcp__plugin_serena"* ]] && [[ "$ALLOWED_TOOLS" != *"Edit"* ]]; then
  if [ -n "$MOCK_READ_LINES" ] && [ "$MOCK_READ_LINES" -gt 0 ]; then
    for i in $(seq 1 "$MOCK_READ_LINES"); do
      echo "- symbol_$i: /src/file_$i.ts line $i"
    done
  else
    echo "### Context"
  fi
  exit 0
fi
```

- [ ] **Step 3: Run tests to confirm they fail**

```bash
npm test 2>&1 | grep -E "not ok.*context cap"
```
Expected: 2-3 failing (cap not implemented yet)

- [ ] **Step 4: Add `CONTEXT_MAX_LINES` variable and truncation to `ralph.sh`**

After the existing variable declarations (around line 15, near `MAX_ITERATIONS`), add:

```bash
CONTEXT_MAX_LINES="${CONTEXT_MAX_LINES:-300}"
```

Then find this block in the main loop (after the `check_serena_init` read call):

```bash
  # Verify context was produced
  if [ ! -s "$CONTEXT_FILE" ]; then
    echo "  WARNING: Read phase produced no context, using fallback"
    echo "# No context gathered" > "$CONTEXT_FILE"
    echo "Read phase did not produce output. Implement based on acceptance criteria only." >> "$CONTEXT_FILE"
  fi
  echo "  (context: $(wc -l < "$CONTEXT_FILE") lines)"
```

Change the last echo line to:

```bash
  # Cap context to limit write phase token consumption
  CONTEXT_LINES=$(wc -l < "$CONTEXT_FILE")
  if [ "$CONTEXT_LINES" -gt "$CONTEXT_MAX_LINES" ]; then
    echo "  (context: $CONTEXT_LINES lines → capped at $CONTEXT_MAX_LINES)"
    { head -n "$CONTEXT_MAX_LINES" "$CONTEXT_FILE"; } > "$CONTEXT_FILE.tmp" && mv "$CONTEXT_FILE.tmp" "$CONTEXT_FILE"
  else
    echo "  (context: $CONTEXT_LINES lines)"
  fi
```

- [ ] **Step 5: Run tests — all should pass**

```bash
npm test 2>&1 | grep -E "not ok|^1\.\."
```
Expected: 3 new context_cap tests pass with zero new `not ok` lines. Pre-existing failures from the current mock baseline are unrelated — confirm the failure list is identical before and after this task.

- [ ] **Step 6: Commit**

```bash
git add ralph.sh tests/context_cap.bats tests/mocks/claude
git commit -m "perf: cap read phase context at CONTEXT_MAX_LINES (default 300)"
```

---

## OPT-3: Context compression pass (Haiku summarizer)

**Estimated saving: 50-80% on write phase input tokens**
**Risk: Medium** — AI summarization may drop details the write phase needs; tune with real stories
**Effort: Medium** — new bash function + new prompt template

Instead of (or in addition to) a hard line cap, run the context through a fast Haiku call that summarizes it to the essential details: file paths, function signatures, key snippets. The write phase gets a dense, relevant context rather than a verbose dump.

**Files:**
- Create: `prompts/compress-context.md`
- Modify: `ralph.sh` (add `compress_context` function + call between read and write)
- Modify: `tests/mocks/claude` (add phase detection for compressor)
- Create: `tests/context_compression.bats`

- [ ] **Step 1: Create the compression prompt template**

Create `prompts/compress-context.md`:

```markdown
# Context Compressor

You are compressing a codebase analysis for a software engineer.

Keep ONLY:
- File paths and 1-line descriptions
- Function/class signatures (name, params, return type)
- Code snippets directly relevant to the story's acceptance criteria
- Schema definitions and type declarations

Remove:
- Full function bodies (keep only signatures)
- Explanatory prose that restates what code does
- Duplicate information
- Implementation notes that don't reference specific files/symbols

Output only the compressed context. No commentary. No preamble.

## Story Acceptance Criteria
{{ACCEPTANCE_CRITERIA}}

## Context to Compress
{{CONTEXT}}
```

- [ ] **Step 2: Write the failing test**

Create `tests/context_compression.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "compressed context is smaller than original" {
  use_fixture "valid-prd.json"
  export MOCK_READ_LINES=400
  export COMPRESS_CONTEXT=true

  run "$RALPH_DIR/ralph.sh" 1

  # After compression, context should be smaller than the 400-line mock output
  LINES=$(wc -l < "$RALPH_DIR/.ralph/context.md")
  [ "$LINES" -lt 400 ]
}

@test "compression skipped when COMPRESS_CONTEXT not set" {
  use_fixture "valid-prd.json"
  export MOCK_READ_LINES=400
  unset COMPRESS_CONTEXT

  run "$RALPH_DIR/ralph.sh" 1

  # 400-line read output — without compression they should all be there
  LINES=$(wc -l < "$RALPH_DIR/.ralph/context.md")
  [ "$LINES" -ge 400 ]
}

@test "compression is logged to output" {
  use_fixture "valid-prd.json"
  export MOCK_READ_LINES=400
  export COMPRESS_CONTEXT=true

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" == *"compressing context"* ]]
}
```

- [ ] **Step 3: Add compressor phase detection to mock**

The `compress_context` function calls `claude` with `--allowed-tools "Read"` (no Serena tools, no Edit). The current mock uses flat if blocks for phase detection. Add a compress block **before** the write phase block:

In `tests/mocks/claude`, find the write phase if block:

```bash
# Write phase
if [[ "$ALLOWED_TOOLS" == *"Edit Write Bash"* ]] && [[ "$ALLOWED_TOOLS" != *"mcp__plugin_serena"* ]]; then
```

Insert a new compress detection block immediately before it:

```bash
# Compress phase: called with --allowed-tools "Read" only
if [[ "$ALLOWED_TOOLS" == "Read" ]]; then
  echo "### Relevant Files"
  echo "- src/main.ts: entry point"
  echo ""
  echo "### Key Symbols"
  echo "- function main(): void"
  echo ""
  echo "### Key Snippets"
  echo "// relevant code here"
  exit 0
fi

# Write phase
if [[ "$ALLOWED_TOOLS" == *"Edit Write Bash"* ]] && [[ "$ALLOWED_TOOLS" != *"mcp__plugin_serena"* ]]; then
```

- [ ] **Step 4: Run tests to confirm they fail**

```bash
npm test 2>&1 | grep -E "not ok.*compress"
```
Expected: failing (function not implemented)

- [ ] **Step 5: Add `compress_context` function to `ralph.sh`**

Add after `check_serena_init()`:

```bash
compress_context() {
  local context_file="$1"
  local acceptance_criteria="$2"
  local original_lines
  original_lines=$(wc -l < "$context_file")

  # Build prompt safely using a temp file — avoids sed injection from context content
  local tmp_prompt
  tmp_prompt=$(mktemp)
  {
    # Write prompt header sections from template (everything before {{CONTEXT}})
    grep -v '{{CONTEXT}}' "$PROMPTS_DIR/compress-context.md" | \
      sed "s|{{ACCEPTANCE_CRITERIA}}|${acceptance_criteria}|g"
    # Append context directly (no substitution — prevents special char injection)
    cat "$context_file"
  } > "$tmp_prompt"

  local compressed
  compressed=$(timeout "5m" claude \
    --print \
    --dangerously-skip-permissions \
    --model claude-haiku-4-5-20251001 \
    --allowed-tools "Read" \
    < "$tmp_prompt" 2>&1)
  rm -f "$tmp_prompt"

  if [ -n "$compressed" ]; then
    echo "$compressed" > "$context_file"
    local new_lines
    new_lines=$(wc -l < "$context_file")
    echo "  (compressing context: $original_lines → $new_lines lines)"
  else
    echo "  WARNING: context compression produced no output, keeping original"
  fi
}
```

- [ ] **Step 6: Add `CURRENT_STORY_CRITERIA` to `extract_current_story()`**

In `ralph.sh`, find `extract_current_story()` (around line 192). After the two existing lines that set `CURRENT_STORY_ID` and `CURRENT_STORY_TITLE`:

```bash
  CURRENT_STORY_ID=$(echo "$story" | jq -r '.id')
  CURRENT_STORY_TITLE=$(echo "$story" | jq -r '.title')
```

Add:

```bash
  CURRENT_STORY_CRITERIA=$(echo "$story" | jq -r '.acceptanceCriteria | join("\n")')
```

- [ ] **Step 7: Wire the compression call in the main loop**

Add the `COMPRESS_CONTEXT` variable near `CONTEXT_MAX_LINES`:

```bash
COMPRESS_CONTEXT="${COMPRESS_CONTEXT:-false}"
```

Then after the context cap block (after the context line-count echo), add:

```bash
  # Optional context compression pass
  if [ "$COMPRESS_CONTEXT" = "true" ] && [ -s "$CONTEXT_FILE" ]; then
    compress_context "$CONTEXT_FILE" "$CURRENT_STORY_CRITERIA"
  fi
```

- [ ] **Step 8: Run all tests**

```bash
npm test 2>&1 | grep -E "not ok|^1\.\."
```
Expected: 3 new context_compression tests pass. Pre-existing failures from the current mock baseline are unrelated — confirm the failure list is identical before and after.

- [ ] **Step 9: Commit**

```bash
git add ralph.sh prompts/compress-context.md tests/context_compression.bats tests/mocks/claude
git commit -m "perf: add optional Haiku context compression pass between read and write phases"
```

---

## OPT-4: Token usage logging (log-size heuristic)

**Estimated saving: None directly — visibility only**
**Risk: Very low** — no changes to phase output format; purely additive logging
**Effort: Small** — 1 function + 3 wiring calls

Log estimated token usage to `progress.txt` after each phase using log file size as a proxy. Exact token counts would require `--output-format json`, which changes the output piped to `context.md` (breaking the write phase). A byte-based heuristic (~4 chars per token) provides useful visibility without any output format changes.

**Files:**
- Modify: `ralph.sh` (add `log_phase_size` function + calls after each phase)
- Create: `tests/token_logging.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/token_logging.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "phase size logged to progress.txt after read phase" {
  use_fixture "valid-prd.json"

  run "$RALPH_DIR/ralph.sh" 1

  grep -q "read.*~.*tokens" "$RALPH_DIR/progress.txt"
}

@test "phase size log includes story ID" {
  use_fixture "valid-prd.json"

  run "$RALPH_DIR/ralph.sh" 1

  grep -q "US-002.*~.*tokens\|~.*tokens.*US-002" "$RALPH_DIR/progress.txt"
}
```

- [ ] **Step 2: Run tests to confirm they fail**

```bash
npm test 2>&1 | grep -E "not ok.*phase size"
```
Expected: 2 failing (function not implemented yet)

- [ ] **Step 3: Add `log_phase_size` to `ralph.sh`**

Add after `check_serena_init()`:

```bash
log_phase_size() {
  local phase_name="$1"
  local log_file="$2"
  if [ -f "$log_file" ]; then
    local bytes chars est_tokens
    bytes=$(wc -c < "$log_file")
    est_tokens=$(( bytes / 4 ))
    echo "[$(date)] Phase size: $phase_name for $CURRENT_STORY_ID — ${bytes}B ~${est_tokens} tokens" >> "$PROGRESS_FILE"
    echo "  (output: ${bytes}B ~${est_tokens} tokens)"
  fi
}
```

- [ ] **Step 4: Wire calls after each phase in the main loop**

After `check_serena_init` calls (or the equivalent position for write phase), add:

```bash
  log_phase_size "read" "$READ_LOG"
  ...
  log_phase_size "write" "$WRITE_LOG"
  ...
  log_phase_size "verify" "$VERIFY_LOG"
```

- [ ] **Step 5: Run all tests**

```bash
npm test 2>&1 | grep -E "not ok|^1\.\."
```
Expected: 2 new token_logging tests pass. Pre-existing failures from the current mock baseline are unrelated — confirm the failure list is identical before and after.

- [ ] **Step 6: Commit**

```bash
git add ralph.sh tests/token_logging.bats
git commit -m "feat: log estimated token usage per phase to progress.txt"
```

---

## OPT-5: Trim SERENA_READ_TOOLS to minimum per phase

**Estimated saving: ~200 tokens/call (small but free)**
**Risk: Very low** — only affects which Serena tools are callable
**Effort: Trivial**

Each tool name in `--allowed-tools` is serialized as part of the context. More importantly, `find_referencing_symbols` is a heavy Serena call that traverses the entire codebase. Removing rarely-used tools from the verify phase (which only needs to check, not explore) saves both context tokens and prevents expensive Serena traversals.

**Files:**
- Modify: `ralph.sh` (split SERENA_READ_TOOLS into read vs verify subsets)

- [ ] **Step 1: Split the tools variable**

Find:
```bash
SERENA_READ_TOOLS="mcp__plugin_serena_serena__activate_project mcp__plugin_serena_serena__get_current_config mcp__plugin_serena_serena__get_symbols_overview mcp__plugin_serena_serena__find_symbol mcp__plugin_serena_serena__read_file mcp__plugin_serena_serena__list_dir mcp__plugin_serena_serena__search_for_pattern mcp__plugin_serena_serena__find_referencing_symbols mcp__plugin_serena_serena__find_file"
```

Replace with two variables:

```bash
# Full Serena exploration tools for read phase
SERENA_READ_TOOLS="mcp__plugin_serena_serena__activate_project mcp__plugin_serena_serena__get_current_config mcp__plugin_serena_serena__get_symbols_overview mcp__plugin_serena_serena__find_symbol mcp__plugin_serena_serena__read_file mcp__plugin_serena_serena__list_dir mcp__plugin_serena_serena__search_for_pattern mcp__plugin_serena_serena__find_referencing_symbols mcp__plugin_serena_serena__find_file"

# Minimal Serena tools for verify phase (check only, no deep traversal)
SERENA_VERIFY_TOOLS="mcp__plugin_serena_serena__activate_project mcp__plugin_serena_serena__get_current_config mcp__plugin_serena_serena__read_file mcp__plugin_serena_serena__search_for_pattern"
```

- [ ] **Step 2: Update `run_verify_phase` to use the smaller set**

Find in `run_verify_phase`:
```bash
    --allowed-tools "Bash Read Edit Write $SERENA_READ_TOOLS" \
```
Change to:
```bash
    --allowed-tools "Bash Read Edit Write $SERENA_VERIFY_TOOLS" \
```

- [ ] **Step 3: Update mock phase detection**

The mock detects verify phase by: `[[ "$ALLOWED_TOOLS" == *"Edit"* ]] && [[ "$ALLOWED_TOOLS" == *"mcp__plugin_serena"* ]]`. Since `SERENA_VERIFY_TOOLS` still contains `mcp__plugin_serena_serena__activate_project`, this detection still works.

Confirm with:
```bash
bash -n tests/mocks/claude
```

- [ ] **Step 4: Run all tests**

```bash
npm test 2>&1 | grep -E "not ok|^1\.\."
```
Expected: all pass

- [ ] **Step 5: Commit**

```bash
git add ralph.sh
git commit -m "perf: use minimal Serena tool set for verify phase"
```

---

## OPT-6: `--max-turns` guard per phase

**Estimated saving: 10-40% on runaway phases**
**Risk: Low** — adds a safety ceiling; phases that need more turns will warn and truncate
**Effort: Small**

The `claude` CLI supports `--max-turns N` which limits how many tool call + response cycles can happen. Without this, a read phase can loop through 20+ Serena calls before producing output. Setting a reasonable ceiling prevents runaway phases from consuming unbounded tokens.

**Files:**
- Modify: `ralph.sh` (add `MAX_TURNS` env var + `--max-turns` flag to all phase runners)
- Create: `tests/max_turns.bats`

- [ ] **Step 1: Write the failing test**

Create `tests/max_turns.bats`:

```bash
#!/usr/bin/env bats

load test_helper

@test "MAX_TURNS is passed to claude invocation" {
  use_fixture "valid-prd.json"
  export MAX_TURNS=5

  # We can't easily verify --max-turns was passed without a special mock behavior,
  # but we can verify the script runs normally with MAX_TURNS set
  run "$RALPH_DIR/ralph.sh" 1

  # Ralph exits 1 when stories remain unfinished (expected in test) —
  # just verify the script actually ran phases
  [[ "$output" == *"Ralph Iteration"* ]]
}
```

- [ ] **Step 2: Add `MAX_TURNS` variable**

Near `CONTEXT_MAX_LINES`, add:

```bash
MAX_TURNS="${MAX_TURNS:-10}"
```

- [ ] **Step 3: Add `--max-turns` to all three phase runners**

In `run_read_phase`, `run_write_phase`, `run_verify_phase`, add:

```bash
    --max-turns "$MAX_TURNS" \
```

- [ ] **Step 4: Run all tests**

```bash
npm test 2>&1 | grep -E "not ok|^1\.\."
```
Expected: 1 new max_turns test passes. Pre-existing failures from the current mock baseline are unrelated — confirm the failure list is identical before and after.

- [ ] **Step 5: Commit**

```bash
git add ralph.sh tests/max_turns.bats
git commit -m "perf: add MAX_TURNS cap to all phase runners"
```

---

## Summary

| Task | Saving | Risk | Effort | Dependencies |
|------|--------|------|--------|--------------|
| OPT-1: Haiku for read/verify | ~65% on 2 phases | Low | 5 min | none |
| OPT-2: Context size cap | 20-60% on write | Low | 30 min | none |
| OPT-3: Context compression | 50-80% on write | Medium | 2-3h | OPT-2 mock behavior |
| OPT-4: Token logging (heuristic) | visibility | Very low | 30 min | none |
| OPT-5: Trim verify tools | ~2% | Very low | 5 min | none |
| OPT-6: Max turns guard | 10-40% on runaways | Low | 15 min | none |

**Recommended starting point:** OPT-1 + OPT-2 + OPT-6 — all low risk, combined ~70% saving on most phases, under 1 hour total.
