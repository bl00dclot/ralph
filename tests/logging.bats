#!/usr/bin/env bats

load test_helper

@test "creates log directory and per-phase log files" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1
  [ -d "$RALPH_DIR/logs" ]
  [ -f "$RALPH_DIR/logs/iteration-1-read.log" ]
  [ -f "$RALPH_DIR/logs/iteration-1-write.log" ]
  [ -f "$RALPH_DIR/logs/iteration-1-verify.log" ]
}

@test "verify log file contains AI tool output" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1
  # Mock verify phase outputs "Verification failed"
  grep -q "Verification failed" "$RALPH_DIR/logs/iteration-1-verify.log"
}

@test "creates separate logs for each iteration" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 2
  [ -f "$RALPH_DIR/logs/iteration-1-read.log" ]
  [ -f "$RALPH_DIR/logs/iteration-1-verify.log" ]
  [ -f "$RALPH_DIR/logs/iteration-2-read.log" ]
  [ -f "$RALPH_DIR/logs/iteration-2-verify.log" ]
}

@test "initializes progress.txt when it does not exist" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  [ ! -f "$RALPH_DIR/progress.txt" ]
  run "$RALPH_DIR/ralph.sh" 1
  [ -f "$RALPH_DIR/progress.txt" ]
  grep -q "Ralph Progress Log" "$RALPH_DIR/progress.txt"
}
