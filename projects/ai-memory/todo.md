# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Decision status lifecycle → [plan](plans/decision-status-lifecycle.md)
- [x] P1 — shape + lint rules
- [x] P2 — write guard on initiatives (needs: P1)
- [x] P3 — derived count (needs: P1)
- [x] P4 — close-out (plan-done Step 5b), doctrine, docs, changelog
- [x] P5 — migration (needs: P1)
- [x] P6 — migrate local initiatives (needs: P5)
- [x] Pre-PR checkpoint — suite, lint diff, final validator pass, PR (needs: P1, P2, P3, P4, P5, P6) — PR #136

## Done
_(checked items stay above until the file is rolled)_
