# Archived todo — claude-memory-system — 2026-05-19

# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Consolidate working_archive → archive/working → [plan](plans/working-archive-consolidation-plan.md)

**Phase 1 — Migrate data**
- [x] Move snapshots from each project's `working_archive/` to `archive/working/`; remove old dirs (5 snapshots across 3 projects: argo-apps 1, charts 3, infrastructure 1)
- [x] Add `archive/working/.gitkeep` to `_template/`

**Phase 2 — Tooling**
- [x] Update `~/.claude/commands/promote-memory.md` to write to `archive/working/`
- [x] Extend `scripts/lint-memory.sh` check #4 to require `archive/working/`

**Phase 3 — Docs**
- [x] Update `README.md` (directory tree + governance note)
- [x] Update `~/.claude/CLAUDE.md` (layout + reorganize-memory rule)
- [x] Update `projects/claude-memory-system/memory.md` (Current State)

**Phase 4 — Verify**
- [x] `find projects -name working_archive -type d` returns empty
- [x] `bash scripts/lint-memory.sh` clean
- [x] Spot-check a migrated snapshot opens correctly at new path (client-a-charts/archive/working/2026-05-19-1515.md readable)

## Done
_(checked items stay above until the file is rolled)_
