# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

- [x] **Task-provider delete interface** — [plan](plans/task-provider-delete.md) (task `38ef6850`) · validator ALL PASS
  - [x] Contract: abstract `delete(ref)` + update inline test subclasses
  - [x] Notion: `delete` via `PATCH {archived:true}`, ref-guarded
  - [x] Local: `delete` hard-unlinks the live `tasks/<ref>.md`
  - [x] CLI: `delete` verb in `__main__.py`; refresh `taskctl` usage comment
  - [x] Tests: notion + local units, contract test, shell CLI test
  - [x] Docs: `docs/task-provider.md` delete verb; full suite green

## Done
_(checked items stay above until the file is rolled)_
