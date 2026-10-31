# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Require python3 >= 3.11 and fail the guard closed → [plan](plans/require-python3-and-fail-guard-closed.md)
- [ ] P1 — shared preflight in install.sh and sync-system.sh
- [ ] P2 — guard no-parser path denies everywhere
- [ ] P3 — docs, changelog, full gate (needs: P1, P2)

## Done
_(checked items stay above until the file is rolled)_
