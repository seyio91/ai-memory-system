# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Release automation (changelog fragments + computed versioning) → [plan](plans/release-automation.md)
- [ ] Phase A0 — `.github/workflows/tests.yml` runs `run-tests.sh` (ubuntu + macos/bash-3.2, shellcheck installed)
- [ ] Phase A1 — `changelog.d/` convention + `assemble-changelog.sh` (assemble + `--bump`) + tests
- [ ] Phase A2 — `release.sh` consumes fragments + `--ci` non-interactive + tests
- [ ] Phase A3 — adopt per-PR fragment step + docs (`changelog.d/README`, `docs/scripts.md`, cutover)
- [ ] Phase B (deferred) — GitHub Actions + PAT secret (needs user repo-settings setup)

## Done
_(checked items stay above until the file is rolled)_
