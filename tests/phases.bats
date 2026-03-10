#!/usr/bin/env bats

load test_helper

@test "creates per-phase log files" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="pass"

  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -ne 3 ]

  [ -f "$RALPH_DIR/logs/iteration-1-read.log" ]
  [ -f "$RALPH_DIR/logs/iteration-1-write.log" ]
  [ -f "$RALPH_DIR/logs/iteration-1-verify.log" ]
}

@test "read phase produces context file" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1

  # Context file should have been created (even if iteration failed)
  [ -f "$RALPH_DIR/.ralph/context.md" ]
}

@test "read phase context contains codebase analysis" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1

  # Mock read phase outputs structured context
  grep -q "Relevant Files" "$RALPH_DIR/.ralph/context.md"
}

@test "verify phase marks story passed on success" {
  use_fixture "valid-prd-3-incomplete.json"
  export MOCK_CLAUDE_BEHAVIOR="pass"

  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -ne 3 ]

  # First story should now be passed
  PASSED=$(jq -r '.userStories[0].passes' "$RALPH_DIR/prd.json")
  [ "$PASSED" = "true" ]
}

@test "verify phase leaves story failed on verification failure" {
  use_fixture "valid-prd-3-incomplete.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1

  # No stories should be passed
  PASSED=$(jq '[.userStories[] | select(.passes == true)] | length' "$RALPH_DIR/prd.json")
  [ "$PASSED" -eq 0 ]
}

@test "full 3-phase cycle completes all stories" {
  use_fixture "valid-prd-3-incomplete.json"
  export MOCK_CLAUDE_BEHAVIOR="pass"

  run "$RALPH_DIR/ralph.sh" 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ralph completed all tasks!"* ]]
}

@test "context fallback when read phase produces empty output" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  # Create a mock that outputs nothing for read phase
  cat > "$MOCKS/claude-empty-read" << 'SCRIPT'
#!/bin/bash
cat > /dev/null
ALLOWED_TOOLS=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --allowed-tools) ALLOWED_TOOLS="$2"; shift 2 ;;
    *) shift ;;
  esac
done
if [[ "$ALLOWED_TOOLS" == *"mcp__plugin_serena"* ]] && [[ "$ALLOWED_TOOLS" != *"Edit"* ]]; then
  # Read phase: output nothing
  :
elif [[ "$ALLOWED_TOOLS" == *"Edit"* ]] && [[ "$ALLOWED_TOOLS" == *"mcp__plugin_serena"* ]]; then
  echo "Verify phase: failed"
else
  echo "Write phase output"
fi
SCRIPT
  chmod +x "$MOCKS/claude-empty-read"
  mv "$MOCKS/claude" "$MOCKS/claude.bak"
  mv "$MOCKS/claude-empty-read" "$MOCKS/claude"

  run "$RALPH_DIR/ralph.sh" 1
  [[ "$output" == *"WARNING: Read phase produced no context"* ]]

  mv "$MOCKS/claude.bak" "$MOCKS/claude"
}
