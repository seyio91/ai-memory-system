# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Doc-vs-code consistency test → [plan](plans/doc-vs-code-consistency-test.md)
- [x] Phase 1 — clean to floor: expand the shorthand row; `MEMORY_SESSIONS_DIR` → `MEMORY_STATE_DIR`; fix 4 stale `memory_sessions` call-sites + `memory.md:29`; correct the `--dry-run` prose; drop the counts from `system-overview.md`. **Forward axis now clean; strict axis blocked on the indirection question (see plan Risks).**
- [ ] Phase 2 — `scripts/check-docs.sh` + `.docscheck-exempt` (bash 3.2; `find`/`grep`, never `ls`)
- [ ] Phase 3 — `scripts/tests/test_check_docs.sh`: three fixture defects, each must fail the checker (red before green)
- [ ] Phase 4 — `== doc-vs-code ==` stage in `run-tests.sh`; prove it gates by breaking a row
- [ ] Phase 5 — docs: `docs/scripts.md` gate section + CHANGELOG `### Added`

## Done
_(checked items stay above until the file is rolled)_
