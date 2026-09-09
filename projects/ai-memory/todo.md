# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Initiative layer, phase 1 → [plan](plans/initiatives-layer-phase-1.md)
- [x] Phase A — schema + tree wiring: template frontmatter contract, lint rules (mutation-tested), catalog decision (excluded from index), tests wired into the runner — validated 7/7
- [x] Phase B — `/new-initiative` (live-exercised; caught + fixed template/lint clash), `initiative-status.sh` derivation, doctrine edits, docs + changelog fragment — validated 8/8
- [x] Phase C (setup) — breadcrumb rows in both fiter project memories; falsification protocol recorded as a live open thread (criterion deliberately not pre-seeded into the sibling plan)
- [x] Phase C (conclusion) — falsification run CONCLUDED 2026-08-15: criterion fired, verdict = trigger failure (see `initiative-not-consulted-under-work-pressure` investigation); archive of the four `cross-project-sdlc-*` investigations moves to the triggers plan's close-out

### Initiative consultation triggers → [plan](plans/initiative-consultation-triggers.md)
- [x] Phase A — snapshot + staleness + `--ack` in `initiative-status.sh`, seeded-defect tests (38/38 under bash 3.2) — validated 8/8
- [ ] Phase B — session-start hook alert (subprocess reuse of the Phase A check, guarded, payload-tail verified), tests (needs: PA)
- [ ] Phase C — `/checkpoint` question (live-exercised), doctrine + stream-first rule, docs + changelog (needs: PA)
- [ ] Checkpoint — pre-PR gate: full suite, lint, live exercise of the prose commands, human review (needs: PB, PC)
- [ ] Phase D — fiter breadcrumb rows to mechanism wording (main), stamp + archive seed investigation, record falsification test (needs: PB, PC)

## Done
_(checked items stay above until the file is rolled)_
