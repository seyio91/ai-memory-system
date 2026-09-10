# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Scope `task_ref: none` to plans; drop rule 10 dead guard → [plan](plans/task-ref-none-scope.md)
- [x] P1 — rule 9 rejects `none`, rule 10 inner guard removed, both pinned by individual mutation tests
- [ ] Checkpoint — full suite + lint 18 + human review (needs: P1)

## Done
_(checked items stay above until the file is rolled)_
