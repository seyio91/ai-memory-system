# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Standardize the hook layer across harnesses (+ move Codex onto native hooks) → [plan](plans/hook-standardization.md)
- [x] P1 — roles + data-driven driver (`[hooks]` map, no hardcoded event names; behavior-preserving) — PR #57 merged (main c818f0b)
- [x] P2 — shared `scripts/hooks/` + Codex onto hooks (hybrid; Fork-4 reversed to /hooks trust; version floor) — PR #58 merged
- [x] P3 — migrate Claude onto shared scripts + fail-closed `settings.json` auto-merge (validator: SHIP) — PR #59 merged (main 8006bc9)
- [x] P4 — docs/consumers + task closure (codex.md hybrid; on-demand-project-load #4; memory.md decision; closed guard task 396f6850). **compaction_recovery deferred** → task 39df6850 (needs a real-compaction spike)

## Done
_(checked items stay above until the file is rolled)_
