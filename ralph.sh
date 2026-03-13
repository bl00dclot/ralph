#!/bin/bash
# Ralph Wiggum - 3-phase autonomous AI agent loop
# Usage: ./ralph.sh [--timeout 30m] [--dry-run] [--notify] [max_iterations]
#
# Each iteration runs three phases:
#   1. READ  — Serena-based codebase survey (read-only)
#   2. WRITE — Code implementation (write-only, no Read tool)
#   3. VERIFY — Acceptance criteria checks, updates prd.json

set -e

# Parse arguments
MAX_ITERATIONS=10
TIMEOUT="30m"
DRY_RUN=false
NOTIFY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    --timeout=*)
      TIMEOUT="${1#*=}"
      shift
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --notify)
      NOTIFY=true
      shift
      ;;
    --help|-h)
      echo "Usage: ralph.sh [OPTIONS] [max_iterations]"
      echo ""
      echo "3-phase autonomous AI agent loop (Read → Write → Verify)."
      echo ""
      echo "Options:"
      echo "  --timeout DURATION  Max time per phase (default: 30m)"
      echo "  --dry-run           Show next story and exit without running"
      echo "  --notify            Send desktop notification on completion"
      echo "  --help              Show this help"
      echo ""
      echo "Arguments:"
      echo "  max_iterations      Maximum loop iterations (default: 10)"
      echo ""
      echo "Exit codes:"
      echo "  0  All stories passed"
      echo "  1  Max iterations reached / lockfile conflict"
      echo "  2  Stuck — same story failed 3+ consecutive iterations"
      echo "  3  Contract violation — AI mutated immutable data"
      echo ""
      echo "Rate-limited phases are retried automatically (up to 3 times with escalating waits)."
      echo "Configure via env vars: RATE_LIMIT_BASE_WAIT (default: 60s), RATE_LIMIT_MAX_RETRIES (default: 3)."
      exit 0
      ;;
    *)
      # Assume it's max_iterations if it's a number
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        MAX_ITERATIONS="$1"
      fi
      shift
      ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || realpath "$SCRIPT_DIR/../..")"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
LOG_DIR="$SCRIPT_DIR/logs"
PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"
PROMPTS_DIR="$SCRIPT_DIR/prompts"
SERENA_CONFIG_TEMPLATE="$SCRIPT_DIR/serena-mcp.json"

# --- Preflight checks ---
if [ ! -f "$PRD_FILE" ]; then
  echo "Error: $PRD_FILE not found. Create one from prd.json.example."
  exit 1
fi

if ! jq empty "$PRD_FILE" 2>/dev/null; then
  echo "Error: $PRD_FILE is not valid JSON."
  exit 1
fi

BRANCH_NAME=$(jq -r '.branchName // empty' "$PRD_FILE")
if [ -z "$BRANCH_NAME" ]; then
  echo "Error: prd.json missing 'branchName' field."
  exit 1
fi

STORY_COUNT=$(jq '.userStories | length' "$PRD_FILE")
if [ "$STORY_COUNT" -eq 0 ]; then
  echo "Error: prd.json has no user stories."
  exit 1
fi

# --- Schema validation ---
SCHEMA_ERRORS=$(jq -r '
  [.userStories[] | {
    id: (.id // "unknown"),
    missing: (
      [
        (if (.id | type) != "string" then "id must be string" else empty end),
        (if (.title | type) != "string" then "title must be string" else empty end),
        (if (.description | type) != "string" then "description must be string" else empty end),
        (if (.acceptanceCriteria | type) != "array" then "acceptanceCriteria must be array" else empty end),
        (if (.priority | type) != "number" then "priority must be number" else empty end),
        (if (.passes | type) != "boolean" then "passes must be boolean" else empty end),
        (if has("notes") and (.notes | type) != "string" then "notes must be string" else empty end),
        (if (has("id") and has("title") and has("description") and has("acceptanceCriteria") and has("priority") and has("passes")) then empty else "missing required fields" end)
      ]
    )
  } | select(.missing | length > 0) | "\(.id): \(.missing | join(", "))"] | join("\n")
' "$PRD_FILE")

if [ -n "$SCHEMA_ERRORS" ]; then
  echo "Error: prd.json schema invalid:"
  echo "$SCHEMA_ERRORS"
  exit 1
fi

# Validate prompt file exists
if [ ! -f "$PROMPT_FILE" ]; then
  echo "Error: CLAUDE.md not found at $PROMPT_FILE"
  exit 1
fi

# Validate prompt templates exist
for phase_prompt in read-phase.md write-phase.md verify-phase.md; do
  if [ ! -f "$PROMPTS_DIR/$phase_prompt" ]; then
    echo "Error: Missing prompt template: $PROMPTS_DIR/$phase_prompt"
    exit 1
  fi
done

# Warn (don't block) on dirty working tree
if ! git diff --quiet 2>/dev/null; then
  echo "Warning: Working tree has uncommitted changes."
fi

# --- Lockfile ---
RALPH_STATE_DIR="$SCRIPT_DIR/.ralph"
LOCKFILE="$RALPH_STATE_DIR/ralph.lock"
CONTEXT_FILE="$RALPH_STATE_DIR/context.md"
CURRENT_STORY_FILE="$RALPH_STATE_DIR/current-story.json"

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

# Notification helper
notify() {
  local title="$1" body="$2"
  if [ "$NOTIFY" = true ]; then
    if command -v notify-send &>/dev/null; then
      notify-send "$title" "$body" 2>/dev/null || true
    fi
    # macOS fallback
    if command -v osascript &>/dev/null; then
      osascript -e "display notification \"$body\" with title \"$title\"" 2>/dev/null || true
    fi
  fi
}

# --- Helper: extract current story ---
extract_current_story() {
  local story
  story=$(jq '[.userStories[] | select(.passes != true)] | sort_by(.priority) | .[0] // empty' "$PRD_FILE")

  if [ -z "$story" ] || [ "$story" = "null" ]; then
    return 1
  fi

  echo "$story" > "$CURRENT_STORY_FILE"
  CURRENT_STORY_ID=$(echo "$story" | jq -r '.id')
  CURRENT_STORY_TITLE=$(echo "$story" | jq -r '.title')
  return 0
}

# --- Helper: build Serena MCP config ---
build_serena_config() {
  if [ -f "$SERENA_CONFIG_TEMPLATE" ]; then
    sed "s|{{PROJECT_ROOT}}|$PROJECT_ROOT|g" "$SERENA_CONFIG_TEMPLATE" > "$RALPH_STATE_DIR/serena-mcp.json"
    return 0
  else
    return 1
  fi
}

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

# --- Helper: build phase prompt with story data ---
build_phase_prompt() {
  local template_file="$1"
  local template
  template=$(cat "$PROMPTS_DIR/$template_file")

  # Build story block from current-story.json
  local story_block
  story_block=$(jq -r '
    "- **ID:** " + .id + "\n" +
    "- **Title:** " + .title + "\n" +
    "- **Description:** " + .description + "\n" +
    "- **Acceptance Criteria:**\n" +
    (.acceptanceCriteria | map("  - " + .) | join("\n"))
  ' "$CURRENT_STORY_FILE")

  # Substitute placeholders
  local result
  result="${template//\{\{STORY_BLOCK\}\}/$story_block}"
  result="${result//\{\{STORY_ID\}\}/$CURRENT_STORY_ID}"
  result="${result//\{\{STORY_TITLE\}\}/$CURRENT_STORY_TITLE}"
  result="${result//\{\{PRD_FILE\}\}/$PRD_FILE}"
  result="${result//\{\{PROGRESS_FILE\}\}/$PROGRESS_FILE}"

  # For write phase: inject context
  if [ "$template_file" = "write-phase.md" ]; then
    local context=""
    if [ -f "$CONTEXT_FILE" ]; then
      context=$(cat "$CONTEXT_FILE")
    else
      context="No context available from read phase."
    fi
    result="${result//\{\{CONTEXT_BLOCK\}\}/$context}"
  fi

  echo "$result"
}

# --- Rate limit detection and retry ---
RATE_LIMIT_BASE_WAIT="${RATE_LIMIT_BASE_WAIT:-60}"
RATE_LIMIT_MAX_RETRIES="${RATE_LIMIT_MAX_RETRIES:-3}"

is_rate_limited() {
  local log_file="$1"
  local exit_code="$2"
  # Successful phases are never rate-limited
  if [ "$exit_code" -eq 0 ]; then
    return 1
  fi
  if [ ! -f "$log_file" ]; then
    return 1
  fi
  grep -qiE 'rate.?limit|too many requests|429|overloaded' "$log_file"
}

run_phase_with_retry() {
  local phase_name="$1"
  local log_file="$2"
  local output_file="$3"  # optional: file to capture stdout (read phase)

  local attempt=0
  local phase_exit=0

  while true; do
    set +e
    set -o pipefail
    if [ -n "$output_file" ]; then
      "run_${phase_name}_phase" | tee "$log_file" > "$output_file"
    else
      "run_${phase_name}_phase" | tee "$log_file"
    fi
    phase_exit=$?
    set +o pipefail
    set -e

    # Timeout is never retried
    if [ "$phase_exit" -eq 124 ]; then
      echo "  WARNING: ${phase_name} phase timed out after $TIMEOUT"
      break
    fi

    # Check for rate limit
    if is_rate_limited "$log_file" "$phase_exit"; then
      attempt=$((attempt + 1))
      if [ "$attempt" -ge "$RATE_LIMIT_MAX_RETRIES" ]; then
        echo "  ERROR: Rate limited $attempt times on $phase_name phase, giving up"
        echo "[$(date)] Rate limit: $phase_name phase for $CURRENT_STORY_ID - gave up after $attempt retries" >> "$PROGRESS_FILE"
        break
      fi
      local wait_time=$((RATE_LIMIT_BASE_WAIT * attempt))
      echo "  RATE LIMITED: Waiting ${wait_time}s before retry ($attempt/$RATE_LIMIT_MAX_RETRIES)..."
      echo "[$(date)] Rate limit: $phase_name phase for $CURRENT_STORY_ID - retry $attempt in ${wait_time}s" >> "$PROGRESS_FILE"
      sleep "$wait_time"
      continue
    fi

    # No rate limit — phase completed (success or normal failure)
    break
  done

  # Always return 0 — the main loop uses stuck detection, not exit codes
  return 0
}

# --- Phase runners ---

# Serena read-only tools (no write/edit Serena tools)
SERENA_READ_TOOLS="mcp__plugin_serena_serena__activate_project mcp__plugin_serena_serena__get_current_config mcp__plugin_serena_serena__get_symbols_overview mcp__plugin_serena_serena__find_symbol mcp__plugin_serena_serena__read_file mcp__plugin_serena_serena__list_dir mcp__plugin_serena_serena__search_for_pattern mcp__plugin_serena_serena__find_referencing_symbols mcp__plugin_serena_serena__find_file"

run_read_phase() {
  local prompt
  prompt="$(build_phase_prompt read-phase.md)"

  local serena_args=""
  if [ -f "$RALPH_STATE_DIR/serena-mcp.json" ]; then
    serena_args="--mcp-config $RALPH_STATE_DIR/serena-mcp.json --strict-mcp-config"
  fi

  echo "$prompt" | timeout "$TIMEOUT" claude \
    --print \
    --dangerously-skip-permissions \
    --model claude-haiku-4-5-20251001 \
    --allowed-tools "Read $SERENA_READ_TOOLS" \
    $serena_args \
    2>&1
}

run_write_phase() {
  local phase_prompt
  phase_prompt="$(build_phase_prompt write-phase.md)"

  # Combine CLAUDE.md + write phase prompt (which includes context)
  local combined
  combined="$(cat "$PROMPT_FILE")

---

$phase_prompt"

  echo "$combined" | timeout "$TIMEOUT" claude \
    --print \
    --dangerously-skip-permissions \
    --model claude-opus-4-6 \
    --allowed-tools "Read Edit Write Bash" \
    2>&1
}

run_verify_phase() {
  local prompt
  prompt="$(build_phase_prompt verify-phase.md)"

  local serena_args=""
  if [ -f "$RALPH_STATE_DIR/serena-mcp.json" ]; then
    serena_args="--mcp-config $RALPH_STATE_DIR/serena-mcp.json --strict-mcp-config"
  fi

  echo "$prompt" | timeout "$TIMEOUT" claude \
    --print \
    --dangerously-skip-permissions \
    --model claude-haiku-4-5-20251001 \
    --allowed-tools "Bash Read Edit Write $SERENA_READ_TOOLS" \
    $serena_args \
    2>&1
}

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

  # Check immutable top-level fields unchanged
  local IMMUTABLE_DIFF
  IMMUTABLE_DIFF=$(jq -n \
    --slurpfile snap "$snapshot" \
    --slurpfile curr "$current" \
    '
    ($snap[0] | {project, branchName, description}) != ($curr[0] | {project, branchName, description})
    ')

  if [ "$IMMUTABLE_DIFF" = "true" ]; then
    echo ""
    echo "Contract violation: AI mutated immutable top-level fields"
    jq -n --slurpfile snap "$snapshot" --slurpfile curr "$current" \
      '{snapshot: ($snap[0] | {project, branchName, description}), current: ($curr[0] | {project, branchName, description})}'
    cp "$snapshot" "$current"
    echo "Restored prd.json from snapshot."
    return 1
  fi

  # Check story immutable fields (id, title, description, acceptanceCriteria, priority)
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
    ) | if length > 0 then join(", ") else empty end
    ')

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
    ) | if length > 0 then join(", ") else empty end
    ')

  if [ -n "$REVERTED" ]; then
    echo ""
    echo "Contract violation: AI reverted completed stories: $REVERTED"
    cp "$snapshot" "$current"
    echo "Restored prd.json from snapshot."
    return 1
  fi

  # Check at most 1 story flipped false → true
  local PASS_COUNT
  PASS_COUNT=$(jq -n \
    --slurpfile snap "$snapshot" \
    --slurpfile curr "$current" \
    '
    [range($snap[0].userStories | length)] |
    map(
      select(
        $snap[0].userStories[.].passes != true and
        $curr[0].userStories[.].passes == true
      )
    ) | length
    ')

  if [ "$PASS_COUNT" -gt 1 ]; then
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
      ) | join(", ")
      ')
    echo ""
    echo "Contract violation: AI completed multiple stories in one iteration: $NEWLY_PASSED"
    cp "$snapshot" "$current"
    echo "Restored prd.json from snapshot."
    return 1
  fi

  return 0
}

# --- Dry run mode ---
if [ "$DRY_RUN" = true ]; then
  echo "Dry run — current status:"
  echo ""
  jq -r '.userStories[] | "\(if .passes then "  ✓" else "  ·" end)  \(.id)  \(.title)"' "$PRD_FILE"
  PASSED=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
  TOTAL=$(jq '.userStories | length' "$PRD_FILE")
  echo ""
  echo "  ($PASSED/$TOTAL passed)"
  NEXT_ID=$(jq -r '[.userStories[] | select(.passes != true)] | sort_by(.priority) | .[0].id // empty' "$PRD_FILE")
  if [ -n "$NEXT_ID" ]; then
    NEXT_TITLE=$(jq -r --arg id "$NEXT_ID" '.userStories[] | select(.id == $id) | .title' "$PRD_FILE")
    echo "  Next story: $NEXT_ID: $NEXT_TITLE"
  else
    echo "  All stories complete — nothing to do."
  fi
  exit 0
fi

# Archive previous run if branch changed
if [ -f "$PRD_FILE" ] && [ -f "$LAST_BRANCH_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  LAST_BRANCH=$(cat "$LAST_BRANCH_FILE" 2>/dev/null || echo "")

  if [ -n "$CURRENT_BRANCH" ] && [ -n "$LAST_BRANCH" ] && [ "$CURRENT_BRANCH" != "$LAST_BRANCH" ]; then
    # Archive the previous run
    DATE=$(date +%Y-%m-%d)
    # Strip "ralph/" prefix from branch name for folder
    FOLDER_NAME=$(echo "$LAST_BRANCH" | sed 's|^ralph/||')
    ARCHIVE_FOLDER="$ARCHIVE_DIR/$DATE-$FOLDER_NAME"

    echo "Archiving previous run: $LAST_BRANCH"
    mkdir -p "$ARCHIVE_FOLDER"
    [ -f "$PRD_FILE" ] && cp "$PRD_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROGRESS_FILE" ] && cp "$PROGRESS_FILE" "$ARCHIVE_FOLDER/"
    [ -f "$PROMPT_FILE" ] && cp "$PROMPT_FILE" "$ARCHIVE_FOLDER/"
    [ -d "$LOG_DIR" ] && cp -r "$LOG_DIR" "$ARCHIVE_FOLDER/"
    echo "   Archived to: $ARCHIVE_FOLDER"

    # Reset progress file for new run
    echo "# Ralph Progress Log" > "$PROGRESS_FILE"
    echo "Started: $(date)" >> "$PROGRESS_FILE"
    echo "---" >> "$PROGRESS_FILE"
  fi
fi

# Track current branch
if [ -f "$PRD_FILE" ]; then
  CURRENT_BRANCH=$(jq -r '.branchName // empty' "$PRD_FILE" 2>/dev/null || echo "")
  if [ -n "$CURRENT_BRANCH" ]; then
    echo "$CURRENT_BRANCH" > "$LAST_BRANCH_FILE"
  fi
fi

# Initialize progress file if it doesn't exist
if [ ! -f "$PROGRESS_FILE" ]; then
  echo "# Ralph Progress Log" > "$PROGRESS_FILE"
  echo "Started: $(date)" >> "$PROGRESS_FILE"
  echo "---" >> "$PROGRESS_FILE"
fi

echo "Starting Ralph - 3-phase mode - Max iterations: $MAX_ITERATIONS"

# Build Serena config once
SERENA_AVAILABLE=false
if build_serena_config; then
  SERENA_AVAILABLE=true
  echo "  Serena MCP: available"
else
  echo "  Serena MCP: not available (no serena-mcp.json template)"
fi

# Stuck detection: track consecutive failures on the same story
STUCK_STORY=""
STUCK_COUNT=0
MAX_STUCK=3

# Create log directory once
mkdir -p "$LOG_DIR"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS"
  echo "==============================================================="

  # --- Snapshot prd.json before iteration ---
  cp "$PRD_FILE" "$RALPH_STATE_DIR/snapshot.json"

  # --- Extract current story ---
  if ! extract_current_story; then
    echo "All stories already complete."
    TOTAL=$(jq '.userStories | length' "$PRD_FILE")
    echo ""
    echo "Ralph completed all tasks! ($TOTAL/$TOTAL stories passed)"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    notify "Ralph DONE" "All $TOTAL stories passed in $i iterations"
    exit 0
  fi
  echo "  Story: $CURRENT_STORY_ID - $CURRENT_STORY_TITLE"

  # === PHASE 1: READ ===
  echo ""
  echo "  --- Phase 1: READ ($CURRENT_STORY_ID) ---"
  READ_LOG="$LOG_DIR/iteration-$i-read.log"
  rm -f "$CONTEXT_FILE"
  run_phase_with_retry "read" "$READ_LOG" "$CONTEXT_FILE"
  [ "$SERENA_AVAILABLE" = "true" ] && check_serena_init "read" "$READ_LOG"

  # Verify context was produced
  if [ ! -s "$CONTEXT_FILE" ]; then
    echo "  WARNING: Read phase produced no context, using fallback"
    echo "# No context gathered" > "$CONTEXT_FILE"
    echo "Read phase did not produce output. Implement based on acceptance criteria only." >> "$CONTEXT_FILE"
  fi
  echo "  (context: $(wc -l < "$CONTEXT_FILE") lines)"

  # === PHASE 2: WRITE ===
  echo ""
  echo "  --- Phase 2: WRITE ($CURRENT_STORY_ID) ---"
  WRITE_LOG="$LOG_DIR/iteration-$i-write.log"
  run_phase_with_retry "write" "$WRITE_LOG"

  # === PHASE 3: VERIFY ===
  echo ""
  echo "  --- Phase 3: VERIFY ($CURRENT_STORY_ID) ---"
  VERIFY_LOG="$LOG_DIR/iteration-$i-verify.log"
  run_phase_with_retry "verify" "$VERIFY_LOG"
  [ "$SERENA_AVAILABLE" = "true" ] && check_serena_init "verify" "$VERIFY_LOG"

  # --- Contract guard ---
  if ! check_contract; then
    notify "Ralph CONTRACT VIOLATION" "AI broke the contract. Check logs."
    exit 3
  fi

  # --- Stuck detection ---
  NEXT_INCOMPLETE=$(jq -r '[.userStories[] | select(.passes != true)] | sort_by(.priority) | .[0].id // empty' "$PRD_FILE")
  if [ -n "$NEXT_INCOMPLETE" ]; then
    if [ "$NEXT_INCOMPLETE" = "$STUCK_STORY" ]; then
      STUCK_COUNT=$((STUCK_COUNT + 1))
    else
      STUCK_STORY="$NEXT_INCOMPLETE"
      STUCK_COUNT=1
    fi
    if [ "$STUCK_COUNT" -ge "$MAX_STUCK" ]; then
      echo ""
      echo "STUCK: $STUCK_STORY failed $MAX_STUCK consecutive iterations. Aborting."
      echo "Check $LOG_DIR/ and $PROGRESS_FILE for details."
      notify "Ralph STUCK" "$STUCK_STORY failed $MAX_STUCK times"
      exit 2
    fi
  fi

  # --- Print story status table ---
  echo ""
  echo "--- Story Status ---"
  jq -r '.userStories[] | "\(if .passes then "  ✓" else "  ·" end)  \(.id)  \(.title)"' "$PRD_FILE"
  PASSED=$(jq '[.userStories[] | select(.passes == true)] | length' "$PRD_FILE")
  TOTAL=$(jq '.userStories | length' "$PRD_FILE")
  echo "  ($PASSED/$TOTAL passed)"
  echo "--------------------"

  # --- Completion check ---
  REMAINING=$(jq '[.userStories[] | select(.passes != true)] | length' "$PRD_FILE")
  if [ "$REMAINING" -eq 0 ]; then
    echo ""
    echo "Ralph completed all tasks! ($TOTAL/$TOTAL stories passed)"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    notify "Ralph DONE" "All $TOTAL stories passed in $i iterations"
    exit 0
  fi

  echo "Iteration $i complete. Continuing..."
  sleep 2
done

echo ""
echo "Ralph reached max iterations ($MAX_ITERATIONS) without completing all tasks."
echo "Check $PROGRESS_FILE for status."
notify "Ralph FAILED" "Reached $MAX_ITERATIONS iterations without completing"
exit 1
