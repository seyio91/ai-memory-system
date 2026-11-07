# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Write-path robustness: index regen and local task provider → [plan](plans/write-path-robustness.md)
- [ ] P1 — regenerate-index.sh: path-safe enumeration + atomic temp handling
- [ ] P2 — local task provider: exclusive create + atomic writes
- [ ] P3 — gate and ship (needs: P1, P2)

## Done
_(checked items stay above until the file is rolled)_
