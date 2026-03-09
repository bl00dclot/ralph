#!/usr/bin/env bats

load test_helper

@test "timeout flag is accepted" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --tool claude --timeout 1m --dry-run
  [ "$status" -eq 0 ]
}

@test "timeout kills hung iteration and warns" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="hang"

  # Use a very short timeout (3 seconds)
  run "$RALPH_DIR/ralph.sh" --tool claude --timeout 3s 1
  # Should not hang forever — timeout should kill it
  # Exit code is 1 (max iterations) since the hung iteration didn't complete any story
  [[ "$output" == *"timed out"* ]]
}

@test "timeout=syntax works" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --tool claude --timeout=1m --dry-run
  [ "$status" -eq 0 ]
}
