# Archived todo — claude-memory-system — 2026-05-19

# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Orchestrator/Executor/Validator workflow → [plan](plans/orchestrator-workflow-plan.md)

**Phase 1 — Rules & documentation**
- [x] Add Orchestration section to `identity.md` (codex-first / subagent-fallback / never apply/merge for executors)
- [x] Add Orchestrator/Executor/Validator section to `~/.claude/CLAUDE.md` with workflow pointers
- [x] Update `README.md` with role table, archive convention, file shapes

**Phase 2 — Directory scaffolding**
- [x] Add `plans/`, `todo.md`, `archive/plans/.gitkeep`, `archive/todos/.gitkeep` to `projects/_template/`
- [x] Backfill missing dirs/files in `client-a-argo-apps`, `client-a-charts`, `client-a-infrastructure`
- [x] Update `scripts/new-project.sh` to scaffold the new structure (no code change needed — `cp -r` inherits `_template/` updates)
- [x] Update `scripts/lint-memory.sh` to flag missing `todo.md` / `plans/` / `archive/`

**Phase 3 — Codex permissions**
- [x] Edit `~/.codex/rules/default.rules` with allow/deny lists (see plan §Phase 3)
- [x] Verify `gh` works under `--sandbox workspace-write -c sandbox_workspace_write.network_access=true` — live test passed; also caught `decision="deny"` was invalid (codex uses `forbidden`) and added `--skip-git-repo-check` to the shorthand
- [x] Update `scripts/codex-mem.sh` — added `--executor` shorthand; verified `-V` and `--executor --help` paths

**Phase 4 — Slash commands**
- [x] `/plan <name>` — scaffold a new plan file in `plans/` with frontmatter
- [x] `/todo-archive` — snapshot `todo.md` to `archive/todos/` and reset
- [x] `/plan-archive <name>` — move a completed plan to `archive/plans/`

**Phase 5 — Codex pickup verification**
- [x] Confirm AGENTS.md contains the Orchestration section after regen (verified via `codex-mem.sh -V` + grep — 10 workflow markers present)

## Done
_(checked items stay above until the file is rolled)_
