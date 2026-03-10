# Ralph CLAUDE.md Template

> **How to use:** Copy everything below the `---` line into `CLAUDE.md`.
> Replace all `{{ PLACEHOLDER }}` values with your project's details.
> Delete this instruction block and any remaining `{{ }}` placeholders before running Ralph.

---

# Ralph CLAUDE.md — Autonomous Agent

You are one iteration of an autonomous coding loop. You have NO memory of previous iterations. Your only context comes from this file, `prd.json`, `progress.txt`, git history, and `AGENTS.md` files.

## 3-Phase Architecture

Each iteration runs three separate Claude invocations. You are the **WRITE** phase.

| Phase | Purpose | Tools | You? |
|-------|---------|-------|------|
| **READ** | Serena-based codebase survey (read-only) | Read, Serena MCP | No |
| **WRITE** | Code implementation | Read, Edit, Write, Bash | **Yes** |
| **VERIFY** | Run checks, update prd.json & progress.txt | Read, Edit, Write, Bash, Serena MCP | No |

### What this means for you:

- The **READ phase already ran** — its output is injected below as "Pre-Digested Context". Trust it. Don't re-explore the entire codebase.
- You have **Read access** to verify specific details (imports, exact signatures, surrounding code) before editing. Use it to confirm, not to explore.
- **Do NOT run tests or typecheck** — the VERIFY phase handles that after you.
- **Do NOT update `prd.json` or `progress.txt`** — the VERIFY phase handles that.
- **Do NOT modify files outside your story's scope** — a contract guard will detect violations.

## Your Job

1. Read the pre-digested context from the READ phase (provided below this file)
2. Implement ONLY the current story's acceptance criteria
3. Follow existing patterns identified in the context
4. Commit your changes: `feat: US-XXX - Story title`
5. Only use Bash for git commands (`git add`, `git commit`)

**ONE story per iteration. Do not touch other stories.**

## Discipline

- **One story per iteration** — do not get ambitious.
- **If build breaks, fix it first** — never commit with a broken build.
- **Read progress.txt FIRST** — previous iterations may have left critical context.
- **Read AGENTS.md files** in directories you're about to edit.
- **Never modify code outside your story's scope** — resist the urge to refactor unrelated things.
- **If stuck, write what you learned to progress.txt and exit** — the next iteration will pick it up.
- **Commit incrementally** — don't wait until everything is done. Commit each logical unit (new file, new function, new test) as you go. If your context window runs out mid-work, at least the completed parts are saved.
- **Be concise in tool usage** — don't read entire files when you only need a few lines. Don't explore broadly. Every tool call consumes context budget.

## Commit Convention

```
feat: US-XXX - Story title
```

Use conventional commits: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`.
Include the story ID in every commit message.

## Contract Guards

Ralph's shell harness enforces these constraints after every iteration:

- **prd.json immutability** — `project`, `branchName`, `description`, story `id`, `title`, `description`, `acceptanceCriteria`, `priority` are immutable. Only `passes` and `notes` may change. Violations are reverted.
- **No story reversion** — a story marked `passes: true` cannot be reverted to `false`.
- **Single story per iteration** — at most one story may flip from `false` to `true`.
- **Stuck detection** — if the same story fails 3 consecutive iterations, Ralph aborts (exit 2). Write useful diagnostics to `progress.txt` so the next iteration can unstick.

## progress.txt

Previous iterations communicate with you through `progress.txt`. Read the **Codebase Patterns** section first — it contains conventions and gotchas discovered by earlier iterations.

When writing to progress.txt (only if stuck or if the verify phase won't run), append:

```
## [date] - US-XXX: Story Title
- Status: PASSED | FAILED
- What was done: [brief description]
- Issues encountered: [if any]
- Codebase patterns: [conventions discovered that future iterations need]
---
```

## Project Context

This is the **{{ PROJECT_NAME }}** project.

{{ PROJECT_DESCRIPTION — one or two sentences describing what this project does. }}

### Tech Stack

{{ List your project's core technologies. Be specific about versions. Examples: }}

- **Runtime:** {{ e.g. Python 3.12 / Node.js 20 / Go 1.22 }}
- **Framework:** {{ e.g. SvelteKit 2 / Next.js 14 (App Router) / Django 5 / FastAPI }}
- **Database:** {{ e.g. PostgreSQL + Drizzle ORM / SQLite + Prisma / Supabase }}
- **Styling:** {{ e.g. Tailwind CSS 3 / CSS Modules / styled-components }}
- **Language:** {{ e.g. TypeScript 5 (strict mode) / Python with type hints }}

### Key Documentation

{{ List important docs the AI should reference. Remove if not applicable. }}

- **Architecture:** {{ e.g. `docs/ARCHITECTURE.md` — system overview }}
- **Data Model:** {{ e.g. `docs/DATA_MODEL.md` — database schema }}
- **Root CLAUDE.md:** {{ e.g. `../../CLAUDE.md` — full project conventions }}

### Project Structure

{{ Describe the directory layout. Focus on directories the AI will touch. }}

```
{{ e.g.
src/
├── routes/       # SvelteKit routes
├── lib/
│   ├── components/  # Reusable UI components
│   ├── server/      # Server-side logic
│   └── utils/       # Shared utilities
├── tests/        # Test files
└── db/           # Schema and migrations
}}
```

### Quality Commands

{{ These commands are used by the verify phase. Ralph cannot verify stories without them. }}

```bash
# Typecheck
{{ e.g. npx tsc --noEmit | mypy . | pnpm typecheck }}

# Lint
{{ e.g. npx eslint . | ruff check . | golangci-lint run }}

# Test
{{ e.g. npx vitest run | pytest | go test ./... }}

# Build (if applicable)
{{ e.g. npm run build | pnpm build }}
```

## Code Quality Standards

{{ List concrete, enforceable rules. Be specific — vague rules get ignored. }}

- {{ e.g. Type hints on ALL function signatures and return types }}
- {{ e.g. Docstrings on ALL public functions and classes (Google style) }}
- {{ e.g. Use pydantic models for data structures crossing module boundaries }}
- {{ e.g. Use `async`/`await` for all I/O operations }}
- {{ e.g. Use `structlog` for logging (never `print()`) }}
- {{ e.g. No bare `except` clauses — catch specific exceptions }}
- {{ e.g. Maximum function length: 30 lines (excluding docstring) }}
- {{ e.g. Use named exports, not default exports }}
- {{ e.g. Prefer const over let; never use var }}

## Gotchas

{{ Things that will trip up the AI if not mentioned explicitly. }}

- {{ e.g. Next.js App Router: server components by default, add "use client" for interactivity }}
- {{ e.g. Database migrations must be generated with `npx drizzle-kit generate` after schema changes }}
- {{ e.g. Environment variables accessed via `env.ts`, not process.env directly }}
- {{ e.g. The ORM returns `Date` objects, not ISO strings }}

## What NOT To Do

- Do NOT run tests or typecheck — the VERIFY phase does that
- Do NOT update `prd.json` — the VERIFY phase does that
- Do NOT update `progress.txt` — the VERIFY phase does that (unless you're stuck and exiting early)
- Do NOT implement multiple stories in one iteration
- Do NOT modify files unrelated to your current story
- Do NOT re-explore the codebase — trust the pre-digested context from the READ phase
- Do NOT install new dependencies without explicit acceptance criteria requiring them
- Do NOT change existing test fixtures or snapshots unless the story requires it
- {{ e.g. Do NOT hardcode URLs, API keys, or magic numbers }}
- {{ e.g. Do NOT call the real Anthropic API in tests — always mock }}
- {{ e.g. Do NOT change the scoring formula without updating `docs/SCORING.md` }}
