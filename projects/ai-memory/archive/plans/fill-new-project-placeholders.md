---
plan: fill-new-project-placeholders
status: done
completed: 2026-10-07
created: 2026-10-07
owner: claude (orchestrator)
task_provider: local
task_ref: fill-new-project-frontmatter-and-heading-placeholders
---

# Fill new-project frontmatter and heading placeholders

## Goal
Make a freshly scaffolded project carry its real name and a real index summary: `new-project.sh` substitutes `<name>` in the copied template files, and `/new-project` writes the What It Is answer into the frontmatter `summary` and reindexes, so no placeholder reaches `index.md`.

## Success criteria
- `new-project.sh acme` produces `topic: acme` and `# Project: acme` in `memory.md` and no `<name>` in any copied file.
- `/new-project` sets frontmatter `summary:` from the What It Is one-liner and runs `regenerate-index.sh`; the new project appears in `index.md` with that summary.
- Regression assertion in `test_new_project.sh` (shipped defect): no `<name>` left, `topic:` equals the project name.
- Full suite green (signing disabled); `check-docs` clean; `changelog.d/<id>.fix.md` present.

## Design
`sed` substitution of the literal `<name>` across the copied `*.md` files right after `cp -r` (name is validated to the project-dir charset first, so it's safe in a `sed` replacement). The summary needs a human answer, so it stays in the prose command, reusing the What It Is one-liner rather than adding a question.

Rejected:
- `--summary` flag on `new-project.sh` — a second input path for the same field; the interview already collects the line.
- Lint rule flagging the placeholder summary — the source of the defect is fixed; existing `network` project is handled by its trim.

## Decisions (locked)
- Shipped defect → regression assertion allowed (identity exception).
- System change → branch + PR via `git-cli ship --intent`.

## Phases

### Phase 1 — Substitute placeholders and wire summary + reindex
Script substitution with name validation; `/new-project` summary + reindex step; regression assertion; changelog fragment.
**Verify:** sandbox `new-project.sh acme` → `topic: acme`, `# Project: acme`, `grep -r '<name>'` empty; `test_new_project.sh` green and the new assertion fails against `main`'s script; full suite green.

## Risks / open questions
- Project names with `/`, `&` or `\` would break the `sed` replacement — validate the name first (reject anything outside `[A-Za-z0-9._-]`).
