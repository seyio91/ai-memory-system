# Archived todo — ai-memory — 2026-10-08

# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Install the memory write guard and a Claude deny-list guard via the manifest → [plan](archive/plans/install-guards.md)
- [x] P1 — Guard scope, deny/ask split, failure modes
- [x] P2 — Manifest roles, install mapping, sweep report (needs: P1)
- [x] P3 — Executor deny-list preamble
- [x] P4 — Doctrine pointer, docs, release notes (needs: P2, P3)
- [x] P5 — Instance cutover, post-merge (needs: P4)

## Done
_(checked items stay above until the file is rolled)_
