#!/usr/bin/env bats

load test_helper

@test "dry run shows story status table" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"US-001"* ]]
  [[ "$output" == *"US-002"* ]]
  [[ "$output" == *"US-003"* ]]
}

@test "dry run shows checkmarks for passed stories" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --dry-run
  [ "$status" -eq 0 ]
  # US-001 passes, should have checkmark
  [[ "$output" == *"✓  US-001"* ]]
  # US-002 does not pass, should have dot
  [[ "$output" == *"·  US-002"* ]]
}

@test "dry run shows correct pass count" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"(1/3 passed)"* ]]
}

@test "dry run shows next story to work on" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Next story: US-002"* ]]
}

@test "dry run shows all complete when all pass" {
  use_fixture "all-complete-prd.json"
  run "$RALPH_DIR/ralph.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"All stories complete"* ]]
  [[ "$output" == *"(2/2 passed)"* ]]
}

@test "dry run does not create log files" {
  use_fixture "valid-prd.json"
  run "$RALPH_DIR/ralph.sh" --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "$RALPH_DIR/logs" ]
}

@test "dry run does not modify progress.txt" {
  use_fixture "valid-prd.json"
  # No progress file exists
  [ ! -f "$RALPH_DIR/progress.txt" ]
  run "$RALPH_DIR/ralph.sh" --dry-run
  [ "$status" -eq 0 ]
  # Still shouldn't exist — dry run doesn't touch it
  [ ! -f "$RALPH_DIR/progress.txt" ]
}
