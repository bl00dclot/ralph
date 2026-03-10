#!/usr/bin/env bats

load test_helper

@test "--help prints usage and exits 0" {
  run "$RALPH_DIR/ralph.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ralph.sh"* ]]
  [[ "$output" == *"--timeout"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--notify"* ]]
}

@test "-h is an alias for --help" {
  run "$RALPH_DIR/ralph.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ralph.sh"* ]]
}

@test "numeric argument sets max iterations" {
  use_fixture "valid-prd.json"
  # Dry run doesn't use max_iterations, so we test it doesn't break parsing
  run "$RALPH_DIR/ralph.sh" 5 --dry-run
  [ "$status" -eq 0 ]
}

@test "3-phase mode is shown in startup banner" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"
  run "$RALPH_DIR/ralph.sh" 1
  [[ "$output" == *"3-phase"* ]]
}
