# Ralph

Autonomous AI agent loop runner with 3-phase iterations. Spawns fresh Claude Code instances in a **Read → Write → Verify** cycle, working through a PRD's user stories one at a time until everything passes.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/). Forked from [snarktank/ralph](https://github.com/snarktank/ralph).

## How It Works

Ralph lives in your project's `scripts/ralph/` directory. It reads `prd.json` containing user stories, then runs three specialized AI phases per iteration:

1. **Read Phase** (`claude-sonnet-4-6`) — Surveys the codebase using [Serena](https://github.com/serena-ai/serena-mcp) semantic tools. Produces a structured context document (relevant files, key symbols, code snippets, implementation notes).
2. **Write Phase** (`claude-opus-4-6`) — Receives the context from the read phase and implements the next story. Has Read, Edit, Write, and Bash (for git). Can read files for verification but has no Serena exploration tools — relies on pre-digested context for architecture decisions.
3. **Verify Phase** (`claude-sonnet-4-6`) — Independently checks acceptance criteria by running tests, typecheck, and inspecting code via Serena. Updates `prd.json` and `progress.txt`.

Memory between iterations persists only through:
- **Git history** (commits from previous iterations)
- **`progress.txt`** (learnings the verify phase appends)
- **`prd.json`** (which stories are done)

```
┌───────────────────────────────────────────────────┐
│  ralph.sh                                          │
│                                                    │
│  for i in 1..N:                                    │
│    snapshot prd.json                                │
│    extract next incomplete story                    │
│                                                    │
│    ┌──────────────────────────────────────────┐    │
│    │  READ PHASE (Serena + Read tools)        │    │
│    │  → Surveys codebase, outputs context.md  │    │
│    └──────────────────────────────────────────┘    │
│                     ↓                              │
│    ┌──────────────────────────────────────────┐    │
│    │  WRITE PHASE (Read + Edit + Write + Bash)  │    │
│    │  → Implements story, commits code          │    │
│    └──────────────────────────────────────────┘    │
│                     ↓                              │
│    ┌──────────────────────────────────────────┐    │
│    │  VERIFY PHASE (Serena + Bash + Read)     │    │
│    │  → Runs tests, updates prd.json/progress │    │
│    └──────────────────────────────────────────┘    │
│                                                    │
│    Contract guard: diff snapshot vs prd.json       │
│    Stuck detection: same story fails 3x → exit 2  │
│    All stories passed? → exit 0                    │
│    Max iterations? → exit 1                        │
└───────────────────────────────────────────────────┘
```

### Why 3 Phases?

- **Token savings** — The write phase gets pre-digested context instead of exploring from scratch; it can read files for details but doesn't have Serena exploration tools
- **Separation of concerns** — The AI that writes code cannot mark its own work as passed
- **Tool restriction** — Each phase only has the tools it needs, preventing accidental side effects

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
- [Serena MCP](https://github.com/serena-ai/serena-mcp) (`uvx --from serena-mcp serena` — installed automatically via MCP config)
- **jq** — JSON processor (`sudo apt install jq` / `brew install jq`)
- **Git** — project must be a git repository
- **Node.js** — only needed for running tests

## Setup

### 1. Add Ralph to your project

Ralph should live in `scripts/ralph/` within your project:

```bash
# From your project root
git clone https://github.com/snarktank/ralph.git scripts/ralph
cd scripts/ralph
npm install  # Only needed for tests (installs bats)
chmod +x ralph.sh
```

### 2. Install Claude Code skills (optional)

Ralph uses two Claude Code skills for generating PRDs interactively:

#### Option A: Claude Code Marketplace (recommended)

```bash
# In Claude Code, run:
/plugin marketplace add snarktank/ralph
/plugin install ralph-skills@ralph-marketplace
```

This installs:
- `/prd` — Generate Product Requirements Documents with guided questions
- `/ralph` — Convert PRDs to `prd.json` format for autonomous execution

#### Option B: Copy skills manually

```bash
cp -r scripts/ralph/skills/prd ~/.claude/skills/
cp -r scripts/ralph/skills/ralph ~/.claude/skills/
```

#### Option C: No skills (manual prd.json)

Skip skills entirely and write `prd.json` by hand. See [PRD Format](#prd-format) below.

### 3. Create a CLAUDE.md prompt

Ralph pipes `CLAUDE.md` into the AI as its system prompt. Copy and customize the template:

```bash
cp scripts/ralph/prompt.md scripts/ralph/CLAUDE.md
```

Edit `CLAUDE.md` to add:
- Your project's quality check commands (typecheck, lint, test)
- Codebase conventions and patterns
- Stack-specific gotchas

### 4. Configure Serena (automatic)

Ralph includes a `serena-mcp.json` template that configures the Serena MCP server. At runtime, Ralph substitutes `{{PROJECT_ROOT}}` with your project's git root and writes the config to `.ralph/serena-mcp.json`. No manual setup needed.

If the Serena template is missing, phases run without semantic analysis (degraded mode with a warning).

## Usage

### Step 1: Prepare a specification

Write your feature specification in `docs/plans/` (your project's docs directory). Refine it until it's strong enough, then convert it to Ralph's format.

### Step 2: Create prd.json

Using the skill (if installed):

```
# In Claude Code:
/ralph Convert docs/plans/my-feature-spec.md to prd.json
```

Or create `scripts/ralph/prd.json` manually (see format below).

### Step 3: Run Ralph

```bash
cd scripts/ralph

# Basic run (default: 10 iterations, 30m timeout per phase)
./ralph.sh

# With options
./ralph.sh --timeout 1h --notify 20
```

### CLI Options

```
Usage: ralph.sh [OPTIONS] [max_iterations]

3-phase autonomous AI agent loop (Read → Write → Verify).

Options:
  --timeout DURATION  Max time per phase (default: 30m)
  --dry-run           Show next story and exit without running
  --notify            Send desktop notification on completion
  --help              Show this help

Arguments:
  max_iterations      Maximum loop iterations (default: 10)
```

### Dry Run

Preview current status without running anything:

```bash
./ralph.sh --dry-run
```

```
Dry run — current status:

  ✓  US-001  Add priority field to database
  ·  US-002  Display priority indicator on task cards
  ·  US-003  Add priority selector to task edit
  ·  US-004  Filter tasks by priority

  (1/4 passed)
  Next story: US-002: Display priority indicator on task cards
```

## PRD Format

`prd.json` is the contract between you and Ralph. Place it at `scripts/ralph/prd.json`.

```json
{
  "project": "MyApp",
  "branchName": "ralph/feature-name",
  "description": "Short description of the feature",
  "userStories": [
    {
      "id": "US-001",
      "title": "Add status field to database",
      "description": "As a developer, I need to store task status.",
      "acceptanceCriteria": [
        "Add status column: 'pending' | 'done' (default 'pending')",
        "Migration runs successfully",
        "Typecheck passes"
      ],
      "priority": 1,
      "passes": false,
      "notes": ""
    }
  ]
}
```

| Field | Description |
|-------|-------------|
| `project` | Project name |
| `branchName` | Git branch Ralph works on (prefix with `ralph/`) |
| `description` | Feature description |
| `userStories[].id` | Story ID (`US-001`, `US-002`, ...) |
| `userStories[].title` | Short title |
| `userStories[].description` | User story format description |
| `userStories[].acceptanceCriteria` | Array of verifiable criteria |
| `userStories[].priority` | Execution order (1 = first) |
| `userStories[].passes` | `false` initially, `true` when complete |
| `userStories[].notes` | Optional developer notes |

See `prd.json.example` for a full example.

### Writing Good Stories

**Right-sized** (completable in one AI context window):
- Add a database column and migration
- Add a UI component to an existing page
- Update a server action with new logic

**Too big** (split these):
- "Build the entire dashboard"
- "Add authentication"
- "Refactor the API"

**Rule of thumb:** If you can't describe the change in 2-3 sentences, it's too big.

**Order by dependencies:** Schema first, then backend, then UI. Earlier stories must not depend on later ones.

**Acceptance criteria must be verifiable:**
- Good: "Filter dropdown has options: All, Active, Completed"
- Bad: "Works correctly"
- Always include: `"Typecheck passes"`

## Data Precision Guard

Ralph guards `prd.json` against AI format drift. Each iteration, Ralph snapshots `prd.json` before running the AI, then diffs after to detect violations.

### What the AI can change

| Field | Allowed |
|-------|---------|
| `userStories[].passes` | `false` → `true` only (max 1 per iteration) |
| `userStories[].notes` | Any change |
| Everything else | Immutable — `project`, `branchName`, `description`, story `id`, `title`, `description`, `acceptanceCriteria`, `priority` |

### What triggers a failure

| Violation | What happens |
|-----------|-------------|
| Immutable field changed | prd.json restored from snapshot, exit 3 |
| Multiple stories completed in one iteration | prd.json restored from snapshot, exit 3 |
| Completed story reverted (`true` → `false`) | prd.json restored from snapshot, exit 3 |
| prd.json corrupted (invalid JSON) | prd.json restored from snapshot, exit 3 |

### Other safeguards

- **Lockfile** (`.ralph/ralph.lock`) prevents concurrent Ralph instances
- **Schema validation** at startup checks field names and types
- **CLAUDE.md existence** validated before running
- **Prompt templates** validated at startup (read-phase.md, write-phase.md, verify-phase.md)
- **Single completion path** — only `prd.json` all-passed triggers completion (no promise tags)

## Project Structure

```
scripts/ralph/
├── ralph.sh                 # Main loop runner (bash)
├── prompt.md                # Prompt template (copy to CLAUDE.md)
├── prd.json.example         # Example PRD format
├── serena-mcp.json          # Serena MCP config template
├── package.json             # Dev dependencies (bats for testing)
├── prompts/                 # Phase prompt templates
│   ├── read-phase.md        # Read phase instructions
│   ├── write-phase.md       # Write phase instructions
│   └── verify-phase.md      # Verify phase instructions
├── .claude/
│   └── settings.local.json  # Claude Code permissions
├── docs/
│   └── plans/               # Design and implementation docs
├── tests/                   # BATS test suite
│   ├── preflight.bats       # PRD + schema validation tests
│   ├── argument_parsing.bats
│   ├── completion.bats
│   ├── dry_run.bats
│   ├── logging.bats
│   ├── timeout.bats
│   ├── stuck_detection.bats
│   ├── archive.bats
│   ├── lockfile.bats        # Concurrent execution tests
│   ├── guard.bats           # Contract violation tests
│   ├── phases.bats          # 3-phase architecture tests
│   ├── fixtures/            # Test PRD files
│   └── mocks/               # Mock claude binary
│
│  Generated at runtime:
├── CLAUDE.md                # System prompt (you create from prompt.md)
├── prd.json                 # Current PRD (you create or /ralph generates)
├── progress.txt             # Append-only progress log
├── logs/                    # Per-phase iteration logs
│   ├── iteration-N-read.log
│   ├── iteration-N-write.log
│   └── iteration-N-verify.log
├── .ralph/                  # Runtime state (gitignored)
│   ├── snapshot.json        # Pre-iteration prd.json backup
│   ├── context.md           # Read phase output (fed to write phase)
│   ├── current-story.json   # Current story being worked on
│   ├── serena-mcp.json      # Rendered Serena config
│   └── ralph.lock           # Lockfile
├── archive/                 # Archived previous runs
│   └── YYYY-MM-DD-branch/
└── .last-branch             # Branch tracking for archiving
```

## How ralph.sh Works Internally

### 1. Preflight Checks
- Validates `prd.json` exists and is valid JSON
- Checks for `branchName` field and non-empty `userStories`
- **Schema validation** — every story must have correct field names and types
- Validates `CLAUDE.md` exists
- Validates prompt templates exist (`prompts/read-phase.md`, `write-phase.md`, `verify-phase.md`)
- Warns (doesn't block) on dirty working tree

### 2. Lockfile
Creates `.ralph/ralph.lock` with PID. If another Ralph is already running, exits. Stale locks from dead processes are cleaned up automatically. Trap ensures cleanup on exit.

### 3. Branch Archiving
If the `branchName` in `prd.json` differs from `.last-branch`, Ralph archives the previous run's `prd.json`, `progress.txt`, `CLAUDE.md`, and `logs/` to `archive/YYYY-MM-DD-branchname/`.

### 4. Serena Config
Reads `serena-mcp.json` template, substitutes `{{PROJECT_ROOT}}` with the git root of the project, writes rendered config to `.ralph/serena-mcp.json`. If the template is missing, phases run without Serena (warning emitted).

### 5. Main Loop

For each iteration:

1. **Snapshot** `prd.json` to `.ralph/snapshot.json`
2. **Extract story** — finds the next incomplete story (lowest priority with `passes: false`), writes to `.ralph/current-story.json`
3. **Read phase** (`claude-sonnet-4-6`) — Serena + Read tools survey the codebase. Output captured to `.ralph/context.md` and logged to `logs/iteration-N-read.log`
4. **Write phase** (`claude-opus-4-6`) — Read + Edit + Write + Bash (no Serena). Receives CLAUDE.md + write prompt + context.md via stdin. Logged to `logs/iteration-N-write.log`
5. **Verify phase** (`claude-sonnet-4-6`) — Serena + Bash + Read + Edit. Runs tests, updates `prd.json` passes field and `progress.txt`. Logged to `logs/iteration-N-verify.log`
6. **Contract guard** — diffs snapshot vs current `prd.json` (see [Data Precision Guard](#data-precision-guard))
7. **Stuck detection** — same story fails 3 consecutive iterations → exit 2
8. **Completion check** — all stories `passes: true` → exit 0

### 6. Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All stories passed |
| 1 | Max iterations reached / lockfile conflict |
| 2 | Stuck — same story failed 3+ times |
| 3 | Contract violation — AI mutated immutable data |

## Debugging

```bash
# Check story status
jq '.userStories[] | {id, title, passes}' prd.json

# Read progress/learnings
cat progress.txt

# Check phase logs for iteration 1
cat logs/iteration-1-read.log
cat logs/iteration-1-write.log
cat logs/iteration-1-verify.log

# See context the read phase produced
cat .ralph/context.md

# See git history from Ralph
git log --oneline -10

# Preview without running
./ralph.sh --dry-run
```

## Running Tests

Tests use [BATS](https://github.com/bats-core/bats-core) (Bash Automated Testing System):

```bash
npm test              # Run all tests
npm run test:verbose  # Verbose output
```

Test suites cover: preflight validation, schema validation, argument parsing, completion logic, dry run, logging, timeout handling, stuck detection, archiving, lockfile, contract guard, and 3-phase architecture.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [snarktank/ralph](https://github.com/snarktank/ralph) — Original repository
- [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code)
- [Serena MCP](https://github.com/serena-ai/serena-mcp) — Semantic code analysis server
