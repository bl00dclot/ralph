#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool amp|claude] [--timeout 30m] [--dry-run] [--notify] [max_iterations]

set -e

# Parse arguments
TOOL="amp"  # Default to amp for backwards compatibility
MAX_ITERATIONS=10
TIMEOUT="30m"
DRY_RUN=false
NOTIFY=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --tool)
      TOOL="$2"
      shift 2
      ;;
    --tool=*)
      TOOL="${1#*=}"
      shift
      ;;
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
      echo "Options:"
      echo "  --tool amp|claude   AI backend (default: amp)"
      echo "  --timeout DURATION  Max time per iteration (default: 30m)"
      echo "  --dry-run           Show next story and exit without running"
      echo "  --notify            Send desktop notification on completion"
      echo "  --help              Show this help"
      echo ""
      echo "Arguments:"
      echo "  max_iterations      Maximum loop iterations (default: 10)"
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

# Validate tool choice
if [[ "$TOOL" != "amp" && "$TOOL" != "claude" ]]; then
  echo "Error: Invalid tool '$TOOL'. Must be 'amp' or 'claude'."
  exit 1
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRD_FILE="$SCRIPT_DIR/prd.json"
PROGRESS_FILE="$SCRIPT_DIR/progress.txt"
ARCHIVE_DIR="$SCRIPT_DIR/archive"
LAST_BRANCH_FILE="$SCRIPT_DIR/.last-branch"
LOG_DIR="$SCRIPT_DIR/logs"
PROMPT_FILE="$SCRIPT_DIR/CLAUDE.md"

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

# Warn (don't block) on dirty working tree
if ! git diff --quiet 2>/dev/null; then
  echo "Warning: Working tree has uncommitted changes."
fi

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

echo "Starting Ralph - Tool: $TOOL - Max iterations: $MAX_ITERATIONS"

# Stuck detection: track consecutive failures on the same story
STUCK_STORY=""
STUCK_COUNT=0
MAX_STUCK=3

# Create log directory once
mkdir -p "$LOG_DIR"

for i in $(seq 1 $MAX_ITERATIONS); do
  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL)"
  echo "==============================================================="

  ITER_LOG="$LOG_DIR/iteration-$i.log"

  # Run the AI tool, streaming output live to terminal AND to log file.
  # tee writes to the log file while stdout goes directly to the terminal
  # (no $() capture = no pipe buffering = live output).
  # pipefail ensures we capture timeout's exit code (124) through the pipe.
  ITER_EXIT=0
  set +e
  set -o pipefail
  if [[ "$TOOL" == "amp" ]]; then
    timeout "$TIMEOUT" bash -c 'cat "$1" | amp --dangerously-allow-all 2>&1' _ "$PROMPT_FILE" | tee "$ITER_LOG"
    ITER_EXIT=$?
  else
    timeout "$TIMEOUT" bash -c 'claude --dangerously-skip-permissions --print < "$1" 2>&1' _ "$PROMPT_FILE" | tee "$ITER_LOG"
    ITER_EXIT=$?
  fi
  set +o pipefail
  set -e

  if [ "$ITER_EXIT" -eq 124 ]; then
    echo "  WARNING: Iteration $i timed out after $TIMEOUT"
  fi

  echo "  (log saved to $ITER_LOG)"
  
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

  # --- Completion check: authoritative (prd.json) + secondary (<promise> tag) ---
  REMAINING=$(jq '[.userStories[] | select(.passes != true)] | length' "$PRD_FILE")
  if [ "$REMAINING" -eq 0 ]; then
    echo ""
    echo "Ralph completed all tasks! ($TOTAL/$TOTAL stories passed)"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    notify "Ralph DONE" "All $TOTAL stories passed in $i iterations"
    exit 0
  fi

  # Also honor the legacy <promise> signal (grep the log file, not a variable)
  if grep -q "<promise>COMPLETE</promise>" "$ITER_LOG" 2>/dev/null; then
    echo ""
    echo "Ralph signaled completion ($PASSED/$TOTAL stories show passed in prd.json)"
    echo "Completed at iteration $i of $MAX_ITERATIONS"
    notify "Ralph DONE" "Signaled complete at iteration $i ($PASSED/$TOTAL passed)"
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
