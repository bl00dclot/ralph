#!/usr/bin/env bats

load test_helper

@test "archives previous run when branch changes" {
  use_fixture "valid-prd.json"

  # Simulate a previous branch
  echo "ralph/old-branch" > "$RALPH_DIR/.last-branch"
  echo "# Old progress" > "$RALPH_DIR/progress.txt"

  export MOCK_CLAUDE_BEHAVIOR="fail"
  run "$RALPH_DIR/ralph.sh" --tool claude 1

  # Archive directory should exist with old files
  ARCHIVE_COUNT=$(find "$RALPH_DIR/archive" -name "prd.json" 2>/dev/null | wc -l)
  [ "$ARCHIVE_COUNT" -ge 1 ]
  [[ "$output" == *"Archiving previous run"* ]]
}

@test "does not archive when branch is the same" {
  use_fixture "valid-prd.json"

  # Same branch as prd.json
  echo "ralph/test-branch" > "$RALPH_DIR/.last-branch"
  echo "# Current progress" > "$RALPH_DIR/progress.txt"

  export MOCK_CLAUDE_BEHAVIOR="fail"
  run "$RALPH_DIR/ralph.sh" --tool claude 1

  # Should not archive
  [[ "$output" != *"Archiving previous run"* ]]
}

@test "updates .last-branch with current branch" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" --tool claude 1

  [ -f "$RALPH_DIR/.last-branch" ]
  BRANCH=$(cat "$RALPH_DIR/.last-branch")
  [ "$BRANCH" = "ralph/test-branch" ]
}

@test "resets progress.txt after archiving" {
  use_fixture "valid-prd.json"

  echo "ralph/old-branch" > "$RALPH_DIR/.last-branch"
  echo "# Old detailed progress with lots of info" > "$RALPH_DIR/progress.txt"

  export MOCK_CLAUDE_BEHAVIOR="fail"
  run "$RALPH_DIR/ralph.sh" --tool claude 1

  # Progress file should be fresh (not contain old content)
  ! grep -q "Old detailed progress" "$RALPH_DIR/progress.txt"
  grep -q "Ralph Progress Log" "$RALPH_DIR/progress.txt"
}
