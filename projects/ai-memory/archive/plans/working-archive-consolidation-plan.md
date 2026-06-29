---
plan: working-archive-consolidation
status: done
completed: 2026-05-19
created: 2026-05-19
owner: claude (orchestrator)
---

# Plan — Consolidate `working_archive/` into `archive/working/`

## Goal
Single per-project `archive/` parent for every persisted artifact. Today `working_archive/` lives alongside `archive/` — confusing. After this plan there is one place to look: `archive/{plans,todos,working}/`. Audit trail is preserved, just relocated.

## Decisions (locked)
- New path: `projects/<name>/archive/working/` (parallel to `archive/plans/`, `archive/todos/`).
- Source snapshots are **moved**, not copied. Old `working_archive/` dirs are removed after migration. Same audit trail, new home.
- `/promote-memory` writes to the new path going forward.
- Archive remains "never auto-read unless the user explicitly asks" — extending to the relocated working snapshots.

## Phases

### Phase 1 — Migrate data
- For every `projects/<name>/working_archive/`: move all files (including non-`.gitkeep`) to `projects/<name>/archive/working/`.
- Create `archive/working/.gitkeep` in each project + `_template/`.
- Remove the now-empty `working_archive/` directory.

### Phase 2 — Update tooling
- `~/.claude/commands/promote-memory.md` line 40 — change snapshot destination from `working_archive/YYYY-MM-DD-HHMM.md` to `archive/working/YYYY-MM-DD-HHMM.md`.
- `scripts/lint-memory.sh` — extend the Phase-4 orchestrator-scaffold check to also require `archive/working/`. Drop nothing (no existing `working_archive` check).

### Phase 3 — Update docs
- `README.md`: directory tree (line 34) + governance note (line 421) — point at new path.
- `~/.claude/CLAUDE.md`: Layout list (line 10) + reorganize-memory rule (line 44).
- `projects/claude-memory-system/memory.md`: Current State entries (lines 17–18).

### Phase 4 — Verify
- Run `bash scripts/lint-memory.sh` — expect clean.
- Confirm `find projects -name working_archive -type d` returns nothing.
- Spot-check one migrated snapshot is readable at the new path.

## Risks / open questions
- None significant. Files are local, moves are reversible from the same session if anything's off.

## Acceptance
- No `working_archive/` directories anywhere under `projects/`.
- All historical snapshots present under `archive/working/` in their original projects.
- `/promote-memory` writes to the new location.
- Lint clean; docs reference only the new path.
