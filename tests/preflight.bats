#!/usr/bin/env bats

load test_helper

@test "fails when prd.json is missing" {
  # Don't install any fixture
  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "fails when prd.json is invalid JSON" {
  echo "not json {{{" > "$RALPH_DIR/prd.json"
  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"not valid JSON"* ]]
}

@test "fails when branchName is missing from prd.json" {
  use_fixture "no-branch-prd.json"
  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"missing 'branchName'"* ]]
}

@test "fails when userStories array is empty" {
  use_fixture "empty-stories-prd.json"
  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"no user stories"* ]]
}

@test "warns on dirty working tree but continues" {
  use_fixture "valid-prd.json"
  # Make the repo dirty
  echo "dirty" > "$TEST_DIR/repo/untracked-file.txt"
  git -C "$TEST_DIR/repo" add .
  echo "modified" >> "$TEST_DIR/repo/untracked-file.txt"

  run "$RALPH_DIR/ralph.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Warning: Working tree has uncommitted changes"* ]]
}

@test "fails when story is missing required fields" {
  use_fixture "bad-schema-prd.json"
  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema invalid"* ]]
}

@test "fails when story fields have wrong types" {
  use_fixture "bad-types-prd.json"
  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"schema invalid"* ]]
}

@test "fails when CLAUDE.md is missing" {
  use_fixture "valid-prd.json"
  rm -f "$RALPH_DIR/CLAUDE.md"
  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"CLAUDE.md not found"* ]]
}

@test "fails when prompt templates are missing" {
  use_fixture "valid-prd.json"
  rm -f "$RALPH_DIR/prompts/read-phase.md"
  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Missing prompt template"* ]]
}
