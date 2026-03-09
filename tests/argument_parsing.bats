#!/usr/bin/env bats

load test_helper

@test "--help prints usage and exits 0" {
  run "$RALPH_DIR/ralph.sh" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ralph.sh"* ]]
  [[ "$output" == *"--tool"* ]]
  [[ "$output" == *"--timeout"* ]]
  [[ "$output" == *"--dry-run"* ]]
  [[ "$output" == *"--notify"* ]]
}

@test "-h is an alias for --help" {
  run "$RALPH_DIR/ralph.sh" -h
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: ralph.sh"* ]]
}

@test "--tool=claude works with equals syntax" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --tool=claude --dry-run
  [ "$status" -eq 0 ]
}

@test "--tool claude works with space syntax" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --tool claude --dry-run
  [ "$status" -eq 0 ]
}

@test "numeric argument sets max iterations" {
  use_fixture "valid-prd.json"
  # Dry run doesn't use max_iterations, so we test it doesn't break parsing
  run "$RALPH_DIR/ralph.sh" --tool claude 5 --dry-run
  [ "$status" -eq 0 ]
}

@test "default tool is amp" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"
  # Run with 1 iteration, amp is default
  run "$RALPH_DIR/ralph.sh" 1
  # Should show amp in the banner
  [[ "$output" == *"(amp)"* ]]
}
