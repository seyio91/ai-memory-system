# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Versioned release channel (git tags) → [plan](plans/versioned-release-channel.md)
- [x] Phase 1 — Channel + `--to` in `sync-system.sh` (PR #40)
- [x] Phase 2 — Migration runner + `.applied-version` (PR #41)
- [x] Phase 3 — `release.sh` (PR #42)
- [x] Phase 4 — Docs (CHANGELOG, UPGRADING, docs/, README) (PR #43)
- [x] Phase 5 — Cut `v1.0.0` (tagged + pushed; retagged after the `--cleanup` fix, PR #44)
- [ ] Phase 5b — Flip a real consumer instance to the release channel (needs a 2nd machine/harness root)

## Done
_(checked items stay above until the file is rolled)_
