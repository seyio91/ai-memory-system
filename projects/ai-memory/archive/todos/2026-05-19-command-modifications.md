# Archived todo — claude-memory-system — 2026-05-19

# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Slash command modifications → [plan](plans/command-modifications-plan.md)

**Phase 1 — Auto-suggest slug**
- [x] Update `~/.claude/commands/todo-archive.md` to derive slug from sole referenced plan when none provided

**Phase 2 — /archive-cleanup**
- [x] Write `scripts/archive-cleanup.sh` (--days, --dry-run, --all-projects, MEMORY_ARCHIVE_RETAIN_DAYS env)
- [x] Write `~/.claude/commands/archive-cleanup.md` (dry-run-first + confirm)

**Phase 3 — Rewrite /promote-memory**
- [x] Rewrite `~/.claude/commands/promote-memory.md` for multi-select with per-candidate destination labels

**Phase 4 — Docs**
- [x] Update `README.md` (new command + behavior notes)
- [x] Update `projects/claude-memory-system/memory.md` (Current State + decision note)

**Phase 5 — Verify**
- [x] `bash scripts/lint-memory.sh` clean
- [x] `bash scripts/archive-cleanup.sh --dry-run` reports 0 deletions on the active project's archive (--days 1 --all-projects finds the 2026-05-17 client-a-infrastructure snapshot, confirming the threshold logic)
- [x] Read-through of the rewritten `/promote-memory` end-to-end

### Workflow carve-out: research vs actionable

- [x] Add rule to `identity.md` and `~/.claude/CLAUDE.md`: executor delegation is only for actionable tasks; explore/research/Q&A work bypasses the plan/todo/working-memory machinery
- [x] Reflect the carve-out in `README.md` role descriptions

## Done
_(checked items stay above until the file is rolled)_
