#!/usr/bin/env bats

load test_helper

@test "creates log directory and iteration log file" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ -d "$RALPH_DIR/logs" ]
  [ -f "$RALPH_DIR/logs/iteration-1.log" ]
}

@test "log file contains AI tool output" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  # Mock outputs "attempted story but failed"
  grep -q "attempted story but failed" "$RALPH_DIR/logs/iteration-1.log"
}

@test "creates separate log for each iteration" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" --tool claude 2
  [ -f "$RALPH_DIR/logs/iteration-1.log" ]
  [ -f "$RALPH_DIR/logs/iteration-2.log" ]
}

@test "initializes progress.txt when it does not exist" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  [ ! -f "$RALPH_DIR/progress.txt" ]
  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ -f "$RALPH_DIR/progress.txt" ]
  grep -q "Ralph Progress Log" "$RALPH_DIR/progress.txt"
}
