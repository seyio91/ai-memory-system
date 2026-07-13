# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Standardize the hook layer across harnesses (+ move Codex onto native hooks) → [plan](plans/hook-standardization.md)
- [x] P1 — roles + data-driven driver (`[hooks]` map, no hardcoded event names; behavior-preserving) — committed `a5df59e` on worktree branch, awaiting PR
- [ ] P2 — shared `scripts/hooks/` + Codex onto hooks (hybrid, requirements.toml trust, version floor)
- [ ] P3 — migrate Claude + fail-closed `settings.json` auto-merge; Antigravity adapter
- [ ] P4 — compaction_recovery + docs/consumers (close guard task 396f6850; on-demand-project-load #4; codex docs)

## Done
_(checked items stay above until the file is rolled)_
