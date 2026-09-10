# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### /new-plan converges plan-first work back onto /start → [plan](archive/plans/new-plan-converges-onto-start.md)
- [x] P1 — `apply-partial.sh --file` target mode (+ test, docs row)
- [x] P2 — author `task-link` partial, inject into both commands, drift gate (needs: P1)
- [x] P3 — `/new-plan` flags + ask + guards; `/start` Step 4 replaced; changelog fragment (needs: P2)
- [x] P4 — lint rule 12, rule 10 ignores `none`, stamp 8 legacy plans
- [x] Checkpoint — full suite + lint baseline 18 + live exercise + human review (needs: P3, P4)

## Done
_(checked items stay above until the file is rolled)_
