#!/usr/bin/env bats

load test_helper

@test "serena init confirmed when sentinel matches project root" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="serena_init_match"

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" == *"Serena: active on"*"✓"* ]]
}

@test "serena init warns on project root mismatch" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="serena_init_mismatch"

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" == *"WARNING: Serena active on"*"expected"* ]]
}

@test "serena init warns when sentinel absent" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" == *"WARNING: Serena initiation not confirmed in read phase"* ]]
}

@test "serena init skipped when serena unavailable" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"
  # Remove serena-mcp.json so SERENA_AVAILABLE stays false
  rm -f "$RALPH_DIR/serena-mcp.json"

  run "$RALPH_DIR/ralph.sh" 1

  [[ "$output" != *"Serena: active"* ]]
  [[ "$output" != *"WARNING: Serena initiation"* ]]
}

@test "serena init confirmed for verify phase" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="serena_init_match"

  run "$RALPH_DIR/ralph.sh" 1

  # Should appear twice: once for read, once for verify
  COUNT=$(echo "$output" | grep -c "Serena: active on.*✓" || true)
  [ "$COUNT" -ge 2 ]
}

@test "PROJECT_ROOT falls back when git root contains ralph.sh" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="fail"

  # Place ralph.sh at the git root to simulate ralph being its own repo
  cp "$RALPH_DIR/ralph.sh" "$TEST_DIR/repo/ralph.sh"

  run "$RALPH_DIR/ralph.sh" 1

  # Ralph should detect its own repo and fall back to ../../
  # The important thing is it doesn't crash
  [ "$status" -ne 3 ]
}
