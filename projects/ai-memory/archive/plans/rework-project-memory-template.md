---
plan: rework-project-memory-template
status: done
completed: 2026-10-07
created: 2026-10-07
owner: claude (orchestrator)
task_provider: local
task_ref: rework-project-memory-template-and-required-section-lint-around-the-claude-md-include-leave-out-test
---

# Rework project memory template and required-section lint

## Goal
Reshape the project `memory.md` template and its lint around the CLAUDE.md include/leave-out test: add optional Commands/Conventions/Pointers, drop Current State and Current Goal (todo.md owns the goal, and `/state` derives it from there), require only What It Is + Architecture Decisions + Known Constraints / Gotchas, and WARN on the obsolete sections so the per-project trims have a checklist.

## Success criteria
- `projects/_template/memory.md` sections, in order: What It Is → Commands → Conventions → Architecture Decisions → Known Constraints / Gotchas → Pointers → (commented) Related Projects; a one-line HTML comment at the top stating the per-line test and pointing at `docs/file-formats.md`; no Current State / Current Goal.
- `lint-memory.sh` requires exactly What It Is, Architecture Decisions, Known Constraints / Gotchas; WARNs per file on `## Current State` (→ What It Is / Gotchas / working.md) and `## Current Goal` (→ todo.md), naming the new home.
- Real-tree lint diff vs `main`: exactly +38 obsolete-section WARNs (19 × 2), no other line added or removed.
- `/state` goal column = title of the first `###` heading under `## Active` in the project's `todo.md` (plan-link suffix stripped), `—` when none; `## Current Goal` no longer read anywhere (`grep -rn 'Current Goal' scripts commands harnesses docs` returns only the obsolete-section lint and its docs).
- `/promote-memory` routes durable decisions to `## Architecture Decisions` (overwrite-on-supersede kept); no `## Decisions Log` route left.
- `docs/file-formats.md` carries the include/leave-out table and the new section list; `docs/knowledge-lifecycle.md`, `commands/new-project.md`, `commands/state.md`, `harnesses/claude/CLAUDE.md` name the new sections.
- Existing tests that pinned the old sections / goal source updated; `bash scripts/run-tests.sh` green (signing disabled locally), counter reconciled; `check-docs` clean.
- `changelog.d/<id>.feature.md` notes the 2 new WARNs per existing project for consumer instances.

## Design
Keep the two existing core names (no rename churn across 19 files, `/promote-memory`, CLAUDE.md); add three optional sections. Lint rule 3 shrinks to the three core sections and gains an obsolete-section WARN — the trims (D3) remove the old sections, and the WARNs are their checklist. `/state`'s goal comes from `todo.md`, making "todo.md owns the goal" literal. `## Pointers` is separate from `## Related Projects`, whose delegation contract lives in `orchestrator.md`. `/promote-memory`'s unused `## Decisions Log` route folds into `## Architecture Decisions`. Existing project files are not edited here.

Rejected:
- Rename to `## Decisions` / `## Gotchas` (mechanically or with dual-accept lint) — churn across 19 files and every doc for no content gain.
- Keep `## Current Goal` as an optional section `/state` still reads — keeps the invitation to write stale status.
- Optional `## Current State` with a byte cap — the audit found it the dominant source of wrong entries; size isn't the problem.
- Merge Related Projects into Pointers — touches orchestrator.md and 12 files.
- Require Commands + Conventions — not every project has commands (GitOps values repos); would make all 19 WARN.
- Full include/leave-out table as a template comment — ~1 KB injected into every new project each session.

## Decisions (locked)
- Required: What It Is, Architecture Decisions, Known Constraints / Gotchas.
- Obsolete-section WARNs name the destination.
- No new tests (identity rule); existing tests updated where they pin changed behaviour.
- System change → branch + PR via `git-cli ship --intent`.

## Phases

### Phase 1 — Template + lint rule 3
New template; `REQUIRED_PROJECT_SECTIONS` → three core sections; obsolete-section WARN; update `test_lint_memory.sh` where it pins the old set.
**Verify:** real-tree lint diff vs `main` is exactly the 38 obsolete-section WARNs; `test_lint_memory.sh` green.

### Phase 2 — `/state` goal from todo.md
`regenerate-state.sh` reads the first `###` under `## Active` in `todo.md`, strips ` → [plan](…)`; `commands/state.md` updated; existing state tests updated.
**Verify:** `bash scripts/regenerate-state.sh` shows each project's first Active plan title (spot-check ai-memory, k8s-addons) and `—` for projects with an empty todo; state tests green.

### Phase 3 — Docs and commands
`docs/file-formats.md` (include/leave-out table + section list), `docs/knowledge-lifecycle.md`, `commands/new-project.md`, `commands/promote-memory.md` (route to Architecture Decisions), `harnesses/claude/CLAUDE.md`.
**Verify:** `grep -rn 'Current Goal\|Current State\|Decisions Log' commands docs harnesses scripts` returns only obsolete-section references; `check-docs` clean.

### Phase 4 — Changelog, full suite, ship
**Depends:** P1, P2, P3
Feature fragment; full suite; contract wiki "What is enforced today" updated on `main`; ship.
**Verify:** suite green with counter reconciled; fragment present; PR open.

## Execution notes (2026-10-07)
- Lint vs `main`: +38 obsolete-section WARNs, 0 removed, nothing else. Full suite 56/56 (signing disabled); `check-docs` clean.
- `/state` real tree: goals now from `todo.md`. k8s-addons shows `—` — its `todo.md` has no `## Active` section (free-form `##` headings); fix in its trim.
- Also touched beyond the plan's list: `docs/install.md` (section count), `docs/harnesses/claude.md` (`/state` source), `docs/demo-runbook.md`, `docs/showcase.md`, `templates/index.template.md`, `scripts/check-changelog-drift.sh` comment (Decisions Log references).
- Fresh scaffold lints clean; `new-project.sh` never substituted `<name>` (pre-existing — the prose command fills it).

## Risks / open questions
- Consumer instances see 2 WARNs per existing project until trimmed — acceptable (WARN, not failure); stated in the changelog.
- A `todo.md` whose first Active item is an inline checkbox, not a plan heading, shows `—` on `/state`.
- `/new-project` is a prose command — live-exercise its interview path after the edit.
