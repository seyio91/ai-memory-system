# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Release automation (changelog fragments + computed versioning) → [plan](plans/release-automation.md) ✅ DONE
Phase A merged in PR #63 (`dc98a6f`); Phase B merged in PR #64 (`d69b431`). Pipeline verified in
production: the #64 merge auto-opened a Release v1.4.0 PR, it got CI via `RELEASE_PAT`, and publish
correctly skipped when the user closed it. Plan done + archived; Notion task closed.
- [x] Phase A0 — `.github/workflows/tests.yml` runs `run-tests.sh` (ubuntu + macos/bash-3.2, shellcheck pinned)
- [x] Phase A1 — `changelog.d/` convention + `assemble-changelog.sh` (assemble + `--bump`) + tests
- [x] Phase A2 — `release.sh` consumes fragments + `--ci` non-interactive + tests
- [x] Phase A3 — adopt per-PR fragment step + docs (`changelog.d/README`, `docs/scripts.md`, cutover)
- [x] Phase B — `--prepare`/`--publish` + `release-pr.yml` + `release-publish.yml` (PR #64)

## Done
_(checked items stay above until the file is rolled)_
