#!/usr/bin/env bats

load test_helper

@test "aborts with exit 2 when same story fails 3 consecutive iterations" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  # MAX_STUCK is 3, so 3 failures on US-002 (the first incomplete) should trigger abort
  run "$RALPH_DIR/ralph.sh" 5
  [ "$status" -eq 2 ]
  [[ "$output" == *"STUCK"* ]]
  [[ "$output" == *"US-002"* ]]
}

@test "stuck detection resets when a different story becomes the next incomplete" {
  use_fixture "valid-prd.json"

  # Create a mock that fails twice, then passes on third verify call
  # We'll use a counter file to track verify calls
  CALL_COUNTER="$TEST_DIR/call-count"
  echo "0" > "$CALL_COUNTER"

  # Create a custom mock that passes on 3rd verify call
  cat > "$MOCKS/claude-counter" << 'SCRIPT'
#!/bin/bash
cat > /dev/null
ALLOWED_TOOLS=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --allowed-tools) ALLOWED_TOOLS="$2"; shift 2 ;;
    *) shift ;;
  esac
done
# Read phase
if [[ "$ALLOWED_TOOLS" == *"mcp__plugin_serena"* ]] && [[ "$ALLOWED_TOOLS" != *"Edit"* ]]; then
  echo "### Context"
  exit 0
fi
# Write phase
if [[ "$ALLOWED_TOOLS" == *"Edit Write Bash"* ]] && [[ "$ALLOWED_TOOLS" != *"mcp__plugin_serena"* ]]; then
  echo "Write phase output"
  exit 0
fi
# Verify phase
COUNTER_FILE="${MOCK_COUNTER_FILE}"
COUNT=$(cat "$COUNTER_FILE")
COUNT=$((COUNT + 1))
echo "$COUNT" > "$COUNTER_FILE"
if [ "$COUNT" -eq 3 ]; then
  # Pass the story on 3rd verify call
  if [ -n "$MOCK_PRD_FILE" ] && [ -f "$MOCK_PRD_FILE" ]; then
    NEXT_ID=$(jq -r '[.userStories[] | select(.passes != true)] | sort_by(.priority) | .[0].id // empty' "$MOCK_PRD_FILE")
    if [ -n "$NEXT_ID" ]; then
      jq --arg id "$NEXT_ID" '(.userStories[] | select(.id == $id)).passes = true' "$MOCK_PRD_FILE" > "$MOCK_PRD_FILE.tmp"
      mv "$MOCK_PRD_FILE.tmp" "$MOCK_PRD_FILE"
      echo "Marked $NEXT_ID as passed."
    fi
  fi
else
  echo "Failed attempt $COUNT"
fi
SCRIPT
  chmod +x "$MOCKS/claude-counter"

  # Temporarily replace claude mock
  mv "$MOCKS/claude" "$MOCKS/claude.bak"
  mv "$MOCKS/claude-counter" "$MOCKS/claude"
  export MOCK_COUNTER_FILE="$CALL_COUNTER"

  # 2 failures on US-002, then it passes → US-003 becomes next → counter resets
  # Needs more iterations — but should NOT trigger stuck (only 2 failures before progress)
  run "$RALPH_DIR/ralph.sh" 5
  # Should exit 2 stuck on US-003 (3 more failures) or exit 1 max iterations
  # Either way it should NOT be stuck on US-002
  [[ "$output" != *"STUCK: US-002"* ]]

  # Restore mock
  mv "$MOCKS/claude" "$MOCKS/claude-counter-done"
  mv "$MOCKS/claude.bak" "$MOCKS/claude"
  rm -f "$MOCKS/claude-counter-done"
}
