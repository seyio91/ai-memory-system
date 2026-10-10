# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Add a re-runnable per-claim memory audit (/lint-memory --audit) → [plan](plans/re-runnable-memory-audit.md)
- [x] P1 — Auditor brief + spike on one real project
- [x] P2 — `/lint-memory --audit <project>` dispatcher (needs: P1)
- [x] P3 — Precise lint rules
- [x] P4 — Docs, changelog, ship (needs: P2, P3)

## Done
_(checked items stay above until the file is rolled)_
