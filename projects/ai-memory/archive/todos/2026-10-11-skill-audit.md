# Archived todo — ai-memory — 2026-10-11

# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Build in-engine skill-audit skill with lint script → [plan](archive/plans/skill-audit.md)
- [x] P1 — `scripts/lint_skill.py` + unittest
- [x] P2 — `references/rules.md`
- [x] P3 — `SKILL.md` + `evals/` + self-rating partial (needs: P1, P2)
- [x] P4 — Docs, live run, ship (needs: P3) — PR #130

## Done
_(checked items stay above until the file is rolled)_
