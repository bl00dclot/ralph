# Serena Initiation Confirmation

**Date:** 2026-03-12
**Status:** Approved

## Problem

Each Ralph iteration launches a fresh Claude instance per phase. There is currently no verification that:
1. Serena is activated on the correct project (not the Ralph agent repo itself)
2. Serena tools are actually invoked during read/verify phases

## Solution

Prompt injection + log scan. Force the AI to emit a parseable sentinel line after calling `activate_project` and `get_current_config`, then grep the phase log for it.

## Changes

### 1. `prompts/read-phase.md` and `prompts/verify-phase.md`

Add a mandatory Step 0 before all other instructions:

```
## Step 0: Initialize Serena
Before anything else:
1. Call `activate_project` to initialize Serena on this project
2. Call `get_current_config` to confirm the active project root
3. Output exactly this line (no extra whitespace):
   [SERENA_INIT: <project_root_from_get_current_config>]
```

### 2. `ralph.sh` — allowed tools

Add to `SERENA_READ_TOOLS` (this variable is used by both `run_read_phase` and `run_verify_phase`, so adding here covers both phases):
- `mcp__plugin_serena_serena__activate_project`
- `mcp__plugin_serena_serena__get_current_config`

### 3. `ralph.sh` — `check_serena_init` function

The sentinel line is greppable from `$log_file` in both phases. For the read phase, `run_phase_with_retry` pipes output through `tee "$log_file" > "$output_file"`, so both the log and the context file receive all output including the sentinel.

The function compares the reported project root against `$PROJECT_ROOT` (the expected target). A mismatch prints a warning but does not abort — the run continues, surfacing the misconfiguration visibly without halting work.

```bash
check_serena_init() {
  local phase_name="$1"
  local log_file="$2"
  local match
  match=$(grep -oP '\[SERENA_INIT: [^\]]+\]' "$log_file" | head -1)
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

### 4. `ralph.sh` — main loop

`check_serena_init` is only called when `SERENA_AVAILABLE=true`. When Serena is unavailable, the check is skipped entirely (no spurious warnings). The call is placed immediately after `run_phase_with_retry`, before the context line-count echo for read, and before the contract check for verify:

```bash
# After run_phase_with_retry "read" ...
[ "$SERENA_AVAILABLE" = "true" ] && check_serena_init "read" "$READ_LOG"
echo "  (context: $(wc -l < "$CONTEXT_FILE") lines)"

# After run_phase_with_retry "verify" ...
[ "$SERENA_AVAILABLE" = "true" ] && check_serena_init "verify" "$VERIFY_LOG"
# then contract check follows
```

## Output Example

```
  --- Phase 1: READ (US-001) ---
  Serena: active on /home/user/myproject ✓
  (context: 42 lines)

  --- Phase 3: VERIFY (US-001) ---
  Serena: active on /home/user/myproject ✓
```

## No Changes To

- Write phase (does not use Serena)
- `run_phase_with_retry` internals
- Log file structure
