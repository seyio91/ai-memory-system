# Archived todo — ai-memory — 2026-10-08

# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Deduplicate the always-injected base (identity, orchestrator, harness CLAUDE.md) → [plan](archive/plans/dedupe-always-injected-base.md)
- [x] P1 — Author the core
- [x] P2 — Injection wiring + legacy fallback (needs: P1)
- [x] P3 — Claude stub + sbp spike (needs: P1)
- [x] P4 — Migration, install, release notes, docs (needs: P2)
- [x] P5 — Instance cutover + full validation (needs: P3, P4)

## Done
_(checked items stay above until the file is rolled)_
