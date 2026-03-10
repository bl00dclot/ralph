# CLAUDE.md Template for Ralph

> **This is a template.** Copy it to `CLAUDE.md` and fill in the sections for your project.
> Delete all `<!-- comments -->` and placeholder text before running Ralph.

---

<!-- COPY BELOW THIS LINE INTO YOUR CLAUDE.md -->

# Project: <!-- PROJECT_NAME -->

<!-- One-line description of what this project is. -->

## Tech Stack

<!-- List your project's core technologies. Examples: -->
<!-- - Runtime: Node.js 20 / Python 3.12 / Go 1.22 -->
<!-- - Framework: Next.js 14 (App Router) / SvelteKit 2 / Django 5 -->
<!-- - Database: PostgreSQL + Drizzle ORM / SQLite + Prisma / Supabase -->
<!-- - Styling: Tailwind CSS 3 / CSS Modules / styled-components -->
<!-- - Language: TypeScript 5 (strict mode) / Python with type hints -->

- Runtime:
- Framework:
- Database:
- Styling:
- Language:

## Quality Commands

<!-- These commands are used by the verify phase to check acceptance criteria. -->
<!-- Ralph cannot verify stories without them. List every command that must pass. -->

```bash
# Typecheck
# e.g.: npx tsc --noEmit | pnpm typecheck | mypy .

# Lint
# e.g.: npx eslint . | ruff check . | golangci-lint run

# Test
# e.g.: npx vitest run | pytest | go test ./...

# Build (if applicable)
# e.g.: npm run build | pnpm build
```

## Project Structure

<!-- Describe the directory layout so the AI knows where things live. -->
<!-- Focus on the directories it will actually touch — skip node_modules, .git, etc. -->

```
src/
├── app/          # <!-- e.g. Routes / pages -->
├── components/   # <!-- e.g. Reusable UI components -->
├── lib/          # <!-- e.g. Utilities, helpers, shared logic -->
├── server/       # <!-- e.g. Server actions, API routes -->
└── db/           # <!-- e.g. Schema, migrations -->
```

## Conventions

<!-- List the patterns the AI must follow when writing code. -->
<!-- Be specific — vague rules get ignored. Examples below. -->

- <!-- e.g. Use named exports, not default exports -->
- <!-- e.g. Components go in src/components/{name}/{name}.tsx -->
- <!-- e.g. Server actions go in src/server/actions/ -->
- <!-- e.g. Database queries use Drizzle ORM, not raw SQL -->
- <!-- e.g. All async functions must handle errors explicitly -->
- <!-- e.g. Use single quotes for strings -->
- <!-- e.g. Prefer const over let; never use var -->

## Gotchas

<!-- Things that will trip up the AI if not mentioned explicitly. -->
<!-- Common examples: -->

- <!-- e.g. Next.js App Router: server components by default, add "use client" for interactivity -->
- <!-- e.g. Database migrations must be generated with `npx drizzle-kit generate` after schema changes -->
- <!-- e.g. Environment variables accessed via `env.ts`, not process.env directly -->
- <!-- e.g. The ORM returns `Date` objects, not ISO strings -->
- <!-- e.g. CSS class names use kebab-case, not camelCase -->

## Do NOT

<!-- Hard rules the AI must never break. -->

- Do not modify files outside the project source directory
- Do not install new dependencies without explicit acceptance criteria requiring them
- Do not change existing test fixtures or snapshots unless the story requires it
- <!-- Add your own: e.g. Do not use any/unknown TypeScript types -->
- <!-- Add your own: e.g. Do not add console.log statements -->
