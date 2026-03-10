#!/usr/bin/env bats

load test_helper

@test "archives previous run when branch changes" {
  use_fixture "valid-prd.json"

  # Simulate a previous branch
  echo "ralph/old-branch" > "$RALPH_DIR/.last-branch"
  echo "# Old progress" > "$RALPH_DIR/progress.txt"

  export MOCK_CLAUDE_BEHAVIOR="fail"
  run "$RALPH_DIR/ralph.sh" 1

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
  run "$RALPH_DIR/ralph.sh" 1

  # Should not archive
  [[ "$output" != *"Archiving previous run"* ]]
}

@test "updates .last-branch with current branch" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1

  [ -f "$RALPH_DIR/.last-branch" ]
  BRANCH=$(cat "$RALPH_DIR/.last-branch")
  [ "$BRANCH" = "ralph/test-branch" ]
}

@test "archives logs and CLAUDE.md when branch changes" {
  use_fixture "valid-prd.json"

  echo "ralph/old-branch" > "$RALPH_DIR/.last-branch"
  echo "# Old progress" > "$RALPH_DIR/progress.txt"
  mkdir -p "$RALPH_DIR/logs"
  echo "iteration 1 log" > "$RALPH_DIR/logs/iteration-1.log"

  export MOCK_CLAUDE_BEHAVIOR="fail"
  run "$RALPH_DIR/ralph.sh" 1

  # Check logs were archived
  ARCHIVE_FOLDER=$(find "$RALPH_DIR/archive" -mindepth 1 -maxdepth 1 -type d | head -1)
  [ -d "$ARCHIVE_FOLDER/logs" ]
  [ -f "$ARCHIVE_FOLDER/logs/iteration-1.log" ]
  [ -f "$ARCHIVE_FOLDER/CLAUDE.md" ]
}

@test "resets progress.txt after archiving" {
  use_fixture "valid-prd.json"

  echo "ralph/old-branch" > "$RALPH_DIR/.last-branch"
  echo "# Old detailed progress with lots of info" > "$RALPH_DIR/progress.txt"

  export MOCK_CLAUDE_BEHAVIOR="fail"
  run "$RALPH_DIR/ralph.sh" 1

  # Progress file should be fresh (not contain old content)
  ! grep -q "Old detailed progress" "$RALPH_DIR/progress.txt"
  grep -q "Ralph Progress Log" "$RALPH_DIR/progress.txt"
}
