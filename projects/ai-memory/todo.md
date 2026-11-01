# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Keep newest working.md loaded; warn before the payload cap → [plan](plans/working-md-checkpoint-window.md)
- [x] P1 — Render window filter
- [x] P2 — Checkpoints-last placement
- [x] P3 — Near-cap marker
- [x] P4 — /checkpoint hidden-count warning (needs: P1, P2)
- [x] Checkpoint — pre-ship (needs: P1, P2, P3, P4) — PR #144

## Done
_(checked items stay above until the file is rolled)_
