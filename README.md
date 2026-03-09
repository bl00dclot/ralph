# Ralph

Autonomous AI agent loop runner. Spawns fresh AI coding tool instances (Claude Code or Amp) in a loop, working through a PRD's user stories one at a time until everything passes.

Based on [Geoffrey Huntley's Ralph pattern](https://ghuntley.com/ralph/). Forked from [snarktank/ralph](https://github.com/snarktank/ralph).

## How It Works

Ralph reads a `prd.json` file containing user stories, then runs your AI coding tool in a loop. Each iteration:

1. Spawns a **fresh AI instance** with no memory of previous runs
2. Feeds it `CLAUDE.md` (the system prompt) which tells it to read `prd.json`
3. The AI picks the highest-priority incomplete story and implements it
4. The AI commits code and marks the story as `passes: true` in `prd.json`
5. Ralph checks `prd.json` - if all stories pass, it exits. Otherwise, loop again.

Memory between iterations persists only through:
- **Git history** (commits from previous iterations)
- **`progress.txt`** (learnings and context the AI appends)
- **`prd.json`** (which stories are done)

```
┌─────────────────────────────────────────────┐
│  ralph.sh                                    │
│                                              │
│  for i in 1..N:                              │
│    ┌──────────────────────────────────────┐  │
│    │  Fresh AI Instance                   │  │
│    │                                      │  │
│    │  1. Read prd.json                    │  │
│    │  2. Read progress.txt                │  │
│    │  3. Pick next story (by priority)    │  │
│    │  4. Implement it                     │  │
│    │  5. Run quality checks               │  │
│    │  6. Commit                           │  │
│    │  7. Mark story passes: true          │  │
│    │  8. Append learnings to progress.txt │  │
│    └──────────────────────────────────────┘  │
│                                              │
│    All stories passed? → exit 0              │
│    Same story failed 3x? → exit 2 (stuck)   │
│    Max iterations? → exit 1                  │
└─────────────────────────────────────────────┘
```

## Prerequisites

- **AI coding tool** (one of):
  - [Claude Code](https://docs.anthropic.com/en/docs/claude-code) (`npm install -g @anthropic-ai/claude-code`)
  - [Amp CLI](https://ampcode.com)
- **jq** - JSON processor (`sudo apt install jq` / `brew install jq`)
- **Git** - project must be a git repository
- **Node.js** - only needed for running tests

## Setup

### 1. Clone and install

```bash
git clone https://github.com/snarktank/ralph.git
cd ralph
npm install  # Only needed for tests (installs bats)
chmod +x ralph.sh
```

### 2. Install Claude Code skills (required for Claude Code users)

Ralph uses two Claude Code skills that let you generate PRDs and convert them to `prd.json` interactively. There are three ways to install them:

#### Option A: Claude Code Marketplace (recommended)

```bash
# In Claude Code, run:
/plugin marketplace add snarktank/ralph
/plugin install ralph-skills@ralph-marketplace
```

This installs:
- `/prd` - Generate Product Requirements Documents with guided questions
- `/ralph` - Convert PRDs to `prd.json` format for autonomous execution

#### Option B: Copy skills manually

```bash
# Copy to your Claude Code skills directory
cp -r skills/prd ~/.claude/skills/
cp -r skills/ralph ~/.claude/skills/
```

#### Option C: No skills (manual prd.json)

You can skip skills entirely and write `prd.json` by hand. See [PRD Format](#prd-format) below.

### 3. Install the Ralph Loop plugin (optional)

There's also an official Anthropic plugin that runs Ralph **inside** a Claude Code session (instead of as a standalone bash script):

```bash
# In Claude Code:
/plugin install ralph-loop@claude-plugins-official
```

This gives you:
- `/ralph-loop` - Start an in-session Ralph loop with a prompt
- `/cancel-ralph` - Cancel an active loop

The in-session loop works differently from `ralph.sh`: it uses Claude Code's stop hook to feed the same prompt back after each response, creating a self-referential loop within a single session.

### 4. Create a CLAUDE.md prompt

Ralph pipes `CLAUDE.md` into the AI tool as its system prompt. This file tells the AI how to read the PRD, implement stories, and report progress.

The `prompt.md` file in this repo is the template. Copy and customize it for your project:

```bash
cp prompt.md CLAUDE.md
```

Edit `CLAUDE.md` to add:
- Your project's quality check commands (typecheck, lint, test)
- Codebase conventions and patterns
- Stack-specific gotchas

## Usage

### Step 1: Create a PRD

Using the skill (if installed):

```
# In Claude Code:
/prd Add priority levels to tasks
```

The skill asks 3-5 clarifying questions, then generates a markdown PRD at `tasks/prd-[feature-name].md`.

Or write one manually in markdown.

### Step 2: Convert to prd.json

Using the skill:

```
# In Claude Code:
/ralph Convert tasks/prd-task-priority.md to prd.json
```

Or create `prd.json` manually (see format below).

### Step 3: Run Ralph

```bash
# Using Claude Code (recommended)
./ralph.sh --tool claude

# Using Amp
./ralph.sh --tool amp

# With options
./ralph.sh --tool claude --timeout 1h --notify 20
```

### CLI Options

```
Usage: ralph.sh [OPTIONS] [max_iterations]

Options:
  --tool amp|claude   AI backend to use (default: amp)
  --timeout DURATION  Max time per iteration (default: 30m)
  --dry-run           Show story status and exit without running
  --notify            Send desktop notification on completion
  --help              Show help

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

`prd.json` is the contract between you and Ralph. Here's the schema:

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
- For UI stories, include: `"Verify in browser using dev-browser skill"`

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
- **Single completion path** — only `prd.json` all-passed triggers completion (no promise tags)

### Runtime directory

`.ralph/` holds runtime state (gitignored):
- `snapshot.json` — prd.json copy from before current iteration
- `ralph.lock` — lockfile with PID

## Project Structure

```
ralph/
├── ralph.sh                 # Main loop runner (bash)
├── prompt.md                # Prompt template (copy to CLAUDE.md)
├── prd.json.example         # Example PRD format
├── package.json             # Dev dependencies (bats for testing)
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
│   ├── lockfile.bats         # Concurrent execution tests
│   ├── guard.bats            # Contract violation tests
│   ├── fixtures/             # Test PRD files
│   └── mocks/                # Mock claude/amp binaries
│
│  Generated at runtime:
├── CLAUDE.md                # System prompt (you create from prompt.md)
├── prd.json                 # Current PRD (you create or /ralph generates)
├── progress.txt             # Append-only progress log
├── logs/                    # Per-iteration output logs
│   └── iteration-N.log
├── .ralph/                  # Runtime state (gitignored)
│   ├── snapshot.json        # Pre-iteration prd.json backup
│   └── ralph.lock           # Lockfile
├── archive/                 # Archived previous runs
│   └── YYYY-MM-DD-branch/
└── .last-branch             # Branch tracking for archiving
```

## How ralph.sh Works Internally

Here's what happens when you run it:

### 1. Argument Parsing
Parses `--tool`, `--timeout`, `--dry-run`, `--notify`, and positional `max_iterations`. Supports both `--flag value` and `--flag=value` syntax.

### 2. Preflight Checks
- Validates `prd.json` exists and is valid JSON
- Checks for `branchName` field and non-empty `userStories`
- **Schema validation** — every story must have correct field names and types
- Validates `CLAUDE.md` exists
- Warns (doesn't block) on dirty working tree

### 3. Lockfile
Creates `.ralph/ralph.lock` with PID. If another Ralph is already running, exits. Stale locks from dead processes are cleaned up automatically. Trap ensures cleanup on exit.

### 4. Branch Archiving
If the `branchName` in `prd.json` differs from `.last-branch`, Ralph archives the previous run's `prd.json`, `progress.txt`, `CLAUDE.md`, and `logs/` to `archive/YYYY-MM-DD-branchname/`.

### 5. Main Loop
For each iteration:
- **Snapshot** `prd.json` to `.ralph/snapshot.json`
- Run the AI tool with `CLAUDE.md` piped via stdin
- `timeout` enforces per-iteration time limit
- Output piped through `tee` for live display + log file
- **Contract guard:** diff snapshot vs current prd.json (see [Data Precision Guard](#data-precision-guard))
- **Stuck detection:** same story fails 3 consecutive iterations → exit 2
- **Completion check:** all stories `passes: true` → exit 0

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

# Check iteration logs
cat logs/iteration-1.log

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

Test suites cover: preflight validation, schema validation, argument parsing, completion logic, dry run, logging, timeout handling, stuck detection, archiving, lockfile, and contract guard.

## References

- [Geoffrey Huntley's Ralph article](https://ghuntley.com/ralph/)
- [snarktank/ralph](https://github.com/snarktank/ralph) - Original repository
- [Claude Code docs](https://docs.anthropic.com/en/docs/claude-code)
- [Amp docs](https://ampcode.com/manual)
