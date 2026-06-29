---
plan: command-modifications
status: done
completed: 2026-05-19
created: 2026-05-19
owner: claude (orchestrator)
---

# Plan — Slash command modifications

## Goal
Three independent improvements to existing slash commands:
1. `/todo-archive` (and other slug-taking commands) auto-derive a slug when one isn't provided and the answer is unambiguous — no needless user prompt.
2. New `/archive-cleanup` command: prune `archive/{plans,todos,working}/` files older than 30 days (configurable) to keep the archive bounded.
3. `/promote-memory` rewritten: agent extracts multiple candidate learnings from `working.md`, each labeled with its inferred destination (`[domain:<name>]` or `[project]`); user multi-selects which to keep.

## Decisions (locked)
- Slug auto-suggest fallback: only kick in when there's an *unambiguous* signal (e.g. `todo.md` references exactly one plan). Otherwise ask. Never silently pick a wrong-feeling default.
- `/archive-cleanup` defaults to active project; `--all-projects` walks every project. Retention threshold default 30 days, overridable via `MEMORY_ARCHIVE_RETAIN_DAYS` env var. `.gitkeep` files always preserved. `--dry-run` lists what would be deleted without touching anything.
- `/promote-memory` rewrite: agent labels each candidate with inferred destination, user multi-selects. Per-item destination drill-down skipped (fewest clicks). Working.md archived once at end after all selected promotions complete.

## Phases

### Phase 1 — Slug auto-suggest in /todo-archive
- Update `~/.claude/commands/todo-archive.md`:
  - When `$ARGUMENTS` is empty, scan `todo.md` for `plans/<name>.md` references.
  - If exactly one unique plan is referenced, derive slug from that filename (strip `-plan` suffix if present) and proceed without asking.
  - If zero or multiple plans, fall back to asking the user (current behavior).
- Apply the same idea to any other current commands that take a slug optional arg.

### Phase 2 — /archive-cleanup command
- `scripts/archive-cleanup.sh`:
  - Flags: `--all-projects`, `--dry-run`, `--days N` (default 30, overridable via `MEMORY_ARCHIVE_RETAIN_DAYS`).
  - Walks `projects/<active>/archive/{plans,todos,working}/` (or all projects with `--all-projects`).
  - Deletes regular files with mtime older than threshold. Skips `.gitkeep` always.
  - Reports per-project counts + paths.
- `~/.claude/commands/archive-cleanup.md`:
  - Thin wrapper. Always run with `--dry-run` first and show the user, then ask confirmation before re-running without `--dry-run`.

### Phase 3 — Rewrite /promote-memory for multi-select
- Update `~/.claude/commands/promote-memory.md`:
  - Step 1: resolve active project, read `working.md` (abort if empty).
  - Step 2: agent extracts up to 6 candidate learnings. Each = one-line summary + inferred destination tag.
    - Inference rules (apply per-candidate):
      - Cross-project pattern/gotcha (Terraform/K8s/AWS/ArgoCD/agent-tooling/etc.) → `[domain:<existing-topic>]` if a matching domain file exists, else `[domain:new]` (agent will prompt for triggers + summary if selected).
      - Engagement-specific decision → `[project]`.
  - Step 3: present candidates via multi-select (`AskUserQuestion` with `multiSelect: true`). Each option shows the label = `[<destination-tag>] <summary>`.
  - Step 4: for each selected candidate, write to its destination:
    - `[domain:<existing>]` — append `**[YYYY-MM-DD]** <summary>` to `domain/<existing>.md` `## Knowledge` section.
    - `[domain:new]` — ask name + triggers + summary, scaffold `domain/<name>.md`, then append entry.
    - `[project]` — append to `projects/<active>/memory.md` `## Decisions Log` (create section if missing).
  - Step 5: archive `working.md` to `archive/working/YYYY-MM-DD-HHMM.md`; create fresh empty `working.md`.
  - Step 6: regenerate index. Report what landed where.

### Phase 4 — Docs
- README.md: add `/archive-cleanup` to the slash-commands table; note the auto-slug behavior in `/todo-archive`; note the multi-select promote flow.
- `~/.claude/CLAUDE.md`: update if any of the new behaviors affect the rules section.
- `projects/claude-memory-system/memory.md`: Current State entry for `/archive-cleanup`; Architecture Decision note about multi-select promote.

### Phase 5 — Verify
- Run `bash scripts/lint-memory.sh` — clean.
- `bash scripts/archive-cleanup.sh --dry-run` on this project — should report 0 files to delete (nothing old enough yet).
- Sanity-check the rewritten promote-memory.md reads coherently end-to-end.

## Risks / open questions
- Multi-select UI: per project rules, I should use `AskUserQuestion` with `multiSelect: true` and present a clean labeled list. `AskUserQuestion` caps at 4 options — if more than 4 candidates emerge, present in batches or truncate to the top 4 most-load-bearing.
- `--all-projects` cleanup blast radius: nothing is destructive beyond dropping stale audit-trail files. Dry-run gate by default mitigates.

## Acceptance
- `/todo-archive` (no arg) on a single-plan todo.md derives the slug silently.
- `/archive-cleanup` exists, dry-runs cleanly, deletes only when given the go-ahead, preserves `.gitkeep`.
- `/promote-memory` presents multiple candidates labeled with destinations and respects multi-select.
- Lint clean; docs current.
