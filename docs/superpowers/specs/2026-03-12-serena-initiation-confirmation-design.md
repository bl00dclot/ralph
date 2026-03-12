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

Add to `SERENA_READ_TOOLS`:
- `mcp__plugin_serena_serena__activate_project`
- `mcp__plugin_serena_serena__get_current_config`

### 3. `ralph.sh` — `check_serena_init` function

```bash
check_serena_init() {
  local phase_name="$1"
  local log_file="$2"
  local match
  match=$(grep -o '\[SERENA_INIT: [^]]*\]' "$log_file" | head -1)
  if [ -n "$match" ]; then
    local project_root="${match#\[SERENA_INIT: }"
    project_root="${project_root%\]}"
    echo "  Serena: active on $project_root ✓"
  else
    echo "  WARNING: Serena initiation not confirmed in $phase_name phase"
  fi
}
```

### 4. `ralph.sh` — main loop

Call `check_serena_init` after read and verify phase completion:

```bash
# After run_phase_with_retry "read" ...
check_serena_init "read" "$READ_LOG"

# After run_phase_with_retry "verify" ...
check_serena_init "verify" "$VERIFY_LOG"
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
