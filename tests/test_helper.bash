# Common test helper — sourced by all .bats files
# Sets up an isolated temp directory that mimics a ralph working environment

REPO_ROOT="$(cd "$(dirname "${BATS_TEST_FILENAME}")/.." && pwd)"
RALPH="$REPO_ROOT/ralph.sh"
FIXTURES="$REPO_ROOT/tests/fixtures"
MOCKS="$REPO_ROOT/tests/mocks"

setup() {
  # Create isolated temp directory for each test
  TEST_DIR="$(mktemp -d)"

  # Initialize a minimal git repo so ralph's git commands don't fail
  git init --quiet "$TEST_DIR/repo"
  cd "$TEST_DIR/repo"
  git commit --allow-empty -m "init" --quiet

  # Create ralph's working directory inside the repo
  RALPH_DIR="$TEST_DIR/repo/ralph"
  mkdir -p "$RALPH_DIR"

  # Copy ralph.sh into the working dir (it uses SCRIPT_DIR relative paths)
  cp "$RALPH" "$RALPH_DIR/ralph.sh"
  chmod +x "$RALPH_DIR/ralph.sh"

  # Create a minimal CLAUDE.md prompt
  echo "You are Ralph. Do the work." > "$RALPH_DIR/CLAUDE.md"

  # Copy prompt templates
  mkdir -p "$RALPH_DIR/prompts"
  printf "# Read phase template\n\n{{STORY_BLOCK}}" > "$RALPH_DIR/prompts/read-phase.md"
  printf "# Write phase template\n\n{{STORY_BLOCK}}\n\n{{CONTEXT_BLOCK}}" > "$RALPH_DIR/prompts/write-phase.md"
  printf "# Verify phase template\n\n{{STORY_BLOCK}}\n\n{{PRD_FILE}}\n{{PROGRESS_FILE}}" > "$RALPH_DIR/prompts/verify-phase.md"

  # Create .ralph state directory
  mkdir -p "$RALPH_DIR/.ralph"

  # Create Serena MCP config template
  echo '{"mcpServers":{"serena":{"command":"echo","args":["mock"]}}}' > "$RALPH_DIR/serena-mcp.json"

  # Put mocks on PATH (before real tools)
  export PATH="$MOCKS:$PATH"

  # Default: mock claude/amp will fail (no story progress)
  export MOCK_CLAUDE_BEHAVIOR="fail"
  export MOCK_PRD_FILE=""
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Helper: install a prd.json fixture into the test ralph dir
use_fixture() {
  local fixture="$1"
  cp "$FIXTURES/$fixture" "$RALPH_DIR/prd.json"
  # Point mock at the prd file so "pass" behavior can update it
  export MOCK_PRD_FILE="$RALPH_DIR/prd.json"
}
