#!/usr/bin/env bats

load test_helper

@test "creates lockfile on start and cleans up on exit" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1

  # Lockfile should be cleaned up after exit
  [ ! -f "$RALPH_DIR/.ralph/ralph.lock" ]
}

@test "fails when lockfile already exists with running PID" {
  use_fixture "valid-prd.json"

  mkdir -p "$RALPH_DIR/.ralph"
  # Use our own PID (which is running) to simulate active lock
  echo "pid=$$" > "$RALPH_DIR/.ralph/ralph.lock"
  echo "started=$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$RALPH_DIR/.ralph/ralph.lock"

  run "$RALPH_DIR/ralph.sh" 1
  [ "$status" -eq 1 ]
  [[ "$output" == *"Another Ralph instance is running"* ]]
}

@test "ignores stale lockfile from dead process" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  mkdir -p "$RALPH_DIR/.ralph"
  # Use a PID that definitely doesn't exist
  echo "pid=99999" > "$RALPH_DIR/.ralph/ralph.lock"
  echo "started=2025-01-01T00:00:00Z" >> "$RALPH_DIR/.ralph/ralph.lock"

  run "$RALPH_DIR/ralph.sh" 1
  # Should proceed (stale lock cleaned up), not exit 1 for lock
  [[ "$output" != *"Another Ralph instance is running"* ]]
}
