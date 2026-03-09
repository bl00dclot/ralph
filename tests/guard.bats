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
