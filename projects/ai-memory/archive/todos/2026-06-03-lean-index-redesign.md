# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Lean index redesign → [plan](plans/lean-index-redesign.md)

- [x] **1.** Tests (`test_regenerate_index` lean both tables + no working section; `test_lint_memory` orphan-by-name)
- [x] **2.** `regenerate-index.sh` — Projects `| Project | Summary |`; Domain `| Topic | Triggers | Summary |`; dropped Working-memory section
- [x] **3.** `lint-memory.sh` — orphan check by identifier (name/topic); also updated index.md prose
- [x] **4.** README — lean roster + derive-path flow; metadata memory.md-only; Working-memory gone; Codex keeps path
- [x] **V.** Suite green (106); real lint 0; real regen idempotent; triggers intact (index+Codex), Codex path intact

## Done
_(checked items stay above until the file is rolled)_
