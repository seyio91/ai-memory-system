# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Widen the validator's aperture → [plan](plans/widen-validator-aperture.md)
- [x] P1 — validator prompt
- [x] P2 — same-family warning
- [x] P3 — doctrine and docs (needs: P1)
- [x] Pre-PR checkpoint — suite, lint diff, live `scope: final` run, PR (needs: P1, P2, P3)

## Done
_(checked items stay above until the file is rolled)_
