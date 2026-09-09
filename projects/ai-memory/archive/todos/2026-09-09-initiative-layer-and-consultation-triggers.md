# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Initiative layer, phase 1 → [plan](archive/plans/initiatives-layer-phase-1.md)
- [x] Phase A — schema + tree wiring: template frontmatter contract, lint rules (mutation-tested), catalog decision (excluded from index), tests wired into the runner — validated 7/7
- [x] Phase B — `/new-initiative` (live-exercised; caught + fixed template/lint clash), `initiative-status.sh` derivation, doctrine edits, docs + changelog fragment — validated 8/8
- [x] Phase C (setup) — breadcrumb rows in both fiter project memories; falsification protocol recorded as a live open thread (criterion deliberately not pre-seeded into the sibling plan)
- [x] Phase C (conclusion) — falsification run CONCLUDED 2026-08-15: criterion fired, verdict = trigger failure (see `initiative-not-consulted-under-work-pressure` investigation); archive of the four `cross-project-sdlc-*` investigations moves to the triggers plan's close-out

### Initiative consultation triggers → [plan](archive/plans/initiative-consultation-triggers.md)
- [x] Phase A — snapshot + staleness + `--ack` in `initiative-status.sh`, seeded-defect tests (38/38 under bash 3.2) — validated 8/8
- [x] Phase B — session-start hook alert in `session_start_memory.sh` (NOT `inject.sh`; subprocess call to `initiative-status.sh`, guarded, alert inserted before `working` so the tail is preserved), 14 new assertions in `test_session_start_memory.sh` — suite 51/51 files green under `/bin/bash` 3.2; mutation-tested in both directions (neutered emission → stale assertions fail; alert appended after `working` → tail assertion fails); real-tree probe emits no alert (no `ai-memory` Target) with payload intact
- [x] Phase C — `/checkpoint` Step 3a (live-exercised on its default path), phase-completion + stream-first doctrine byte-identical in template + local mirror, `docs/initiatives.md`, changelog fragment (needs: PA)
- [x] Checkpoint — pre-PR gate: suite 51/51 reconciled (no partial-run banner), lint at its 18-warning baseline, `/checkpoint` + `/new-initiative` live-exercised, guard exercised on the real tree, new control mutation-tested both directions; human review satisfied by the merge of PR #102 (`b3283da`)
- [x] Phase D — fiter rows rewritten to mechanism wording (both gitignored, local-only); seed investigation already carried `task_ref` (archives with the plan at close-out); four `cross-project-sdlc-*` investigations concluded + archived; composition falsification test armed in `working.md` → `## Open threads` (needs: PB, PC)

## Done
_(checked items stay above until the file is rolled)_
