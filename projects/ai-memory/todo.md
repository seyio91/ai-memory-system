# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Shellcheck static-analysis gate → [plan](plans/shellcheck-gate.md)
- [ ] Phase 1 — `.shellcheckrc` (4 disables) + inline `SC2086` justifications; zero findings at `-S info`
- [ ] Phase 2 — `run-tests.sh` `== shellcheck ==` stage; gates exit code; skips-with-notice if absent; prove it fires
- [ ] Phase 3 — docs: `docs/scripts.md` gate section + CHANGELOG `### Added`

## Done
_(checked items stay above until the file is rolled)_
