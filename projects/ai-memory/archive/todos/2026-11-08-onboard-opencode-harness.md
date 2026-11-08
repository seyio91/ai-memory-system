# Archived todo — ai-memory — 2026-11-08

# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Verification contract: plan template, criterion modes, evidence discipline → [plan](archive/plans/verification-contract.md)
- [x] P1 — Template and scaffold partial
- [x] P2 — Lint rule 20 (needs: P1, P3)
- [x] P3 — Drift script
- [x] P4 — Feasibility brief (needs: P1)
- [x] P5 — Baseline lifecycle
- [x] P6 — Validator and doctrine (needs: P3)
- [x] Checkpoint — pre-ship (needs: P2, P4, P5, P6)

### Onboard opencode as a harness → [plan](archive/plans/onboard-opencode-harness.md)
- [x] P1 — Spike: verify opencode v2 hook surface
- [x] P2 — Engine: manifest, registration style, detection, install (needs: P1)
- [x] P3 — Plugin and hook scripts (needs: P1)
- [x] P4 — Executor wrapper (needs: P1)
- [x] P5 — Docs, changelog, live end-to-end (needs: P2, P3, P4) — PR #152

## Done
_(checked items stay above until the file is rolled)_
