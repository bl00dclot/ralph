#!/usr/bin/env bats

load test_helper

@test "exits 0 when all stories pass via prd.json" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="pass"

  # 3 stories, 1 already passed, mock passes 1 per iteration — needs 2 iterations
  run "$RALPH_DIR/ralph.sh" --tool claude 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ralph completed all tasks!"* ]]
}

@test "exits 0 when AI outputs promise tag" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="promise"

  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"signaled completion"* ]]
}

@test "prd.json completion takes priority over iteration count" {
  use_fixture "all-complete-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  # All stories already pass — should complete on first iteration
  run "$RALPH_DIR/ralph.sh" --tool claude 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ralph completed all tasks!"* ]]
}

@test "exits 1 when max iterations reached without completion" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" --tool claude 2
  [ "$status" -eq 1 ]
  [[ "$output" == *"reached max iterations"* ]]
}

@test "status table prints after each iteration" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="pass"

  run "$RALPH_DIR/ralph.sh" --tool claude 5
  [ "$status" -eq 0 ]
  [[ "$output" == *"Story Status"* ]]
  [[ "$output" == *"passed)"* ]]
}
