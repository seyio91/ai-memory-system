# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Add byte/payload size budgets to memory lint and write guard → [plan](plans/memory-size-budgets.md)
- [x] P1 — Extract the shared slicer
- [x] P2 — check-memory-size.sh with tests (needs: P1)
- [x] P3 — Widen drift regex for project memory; drop date prefix from promote's Decisions Log route
- [x] P4 — Wire into lint and the write guard (needs: P2, P3)
- [ ] Checkpoint — pre-PR (needs: P4)

## Done
_(checked items stay above until the file is rolled)_
