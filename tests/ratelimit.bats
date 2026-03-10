#!/usr/bin/env bats

load test_helper

@test "rate limit retries and succeeds" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="ratelimit"
  export MOCK_RATELIMIT_COUNTER="$TEST_DIR/ratelimit-count"
  export MOCK_RATELIMIT_FAIL_COUNT=1
  export MOCK_RATELIMIT_THEN="pass"
  export RATE_LIMIT_BASE_WAIT=1
  export RATE_LIMIT_MAX_RETRIES=3

  run "$RALPH_DIR/ralph.sh" 1
  [[ "$output" == *"RATE LIMITED"* ]]
  [[ "$output" == *"Waiting"* ]]
}

@test "rate limit exhausts retries and gives up" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="ratelimit"
  export MOCK_RATELIMIT_COUNTER="$TEST_DIR/ratelimit-count"
  export MOCK_RATELIMIT_FAIL_COUNT=10
  export MOCK_RATELIMIT_THEN="pass"
  export RATE_LIMIT_BASE_WAIT=1
  export RATE_LIMIT_MAX_RETRIES=2

  run "$RALPH_DIR/ralph.sh" 1
  [[ "$output" == *"giving up"* ]]
}

@test "rate limit events logged to progress.txt" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="ratelimit"
  export MOCK_RATELIMIT_COUNTER="$TEST_DIR/ratelimit-count"
  export MOCK_RATELIMIT_FAIL_COUNT=1
  export MOCK_RATELIMIT_THEN="pass"
  export RATE_LIMIT_BASE_WAIT=1
  export RATE_LIMIT_MAX_RETRIES=3

  run "$RALPH_DIR/ralph.sh" 1
  grep -q "Rate limit" "$RALPH_DIR/progress.txt"
}

@test "timeout is not retried as rate limit" {
  use_fixture "valid-prd.json"
  export MOCK_CLAUDE_BEHAVIOR="hang"
  export RATE_LIMIT_BASE_WAIT=1

  run "$RALPH_DIR/ralph.sh" --timeout 3s 1
  [[ "$output" == *"timed out"* ]]
  [[ "$output" != *"RATE LIMITED"* ]]
}
