# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Task-provider layer → [plan](plans/task-provider-layer.md) — built, awaiting user verification

### /task + /start command wiring → [plan](plans/task-command-wiring.md)
- [x] Phase 1 — `scripts/taskctl` wrapper + test (fixed PYTHONPATH/MEMORY_DIR conflation)
- [x] Phase 2 — `/task` command (multi-verb, active-project default)
- [x] Phase 3 — `/start` command (by-ref, project-agnostic, brainstorm flow)
- [x] Phase 4 — Docs (README slash table, tree, flip /start to implemented)
- [x] Phase 5 — Verify harness/lint ✅ + live demo on fiter-argo-apps task (deploy-apache-superset → started) ✅
- [x] Phase 1 — Contract + CLI boundary (`scripts/taskprovider/`)
- [x] Phase 2 — Local provider (`FileTaskProvider`)
- [x] Phase 3 — Test local provider (lifecycle green, offline) ⟵ gate before Notion ✅ PASSED
- [x] Phase 4 — Notion provider (`NotionProvider`)
- [x] Phase 5 — Test Notion provider (offline units + gated live smoke skipped)
- [x] Phase 6 — Docs + design checks (README coherent w/ brainstorming, Jira/dropped/`/start`)

## Done
_(checked items stay above until the file is rolled)_
