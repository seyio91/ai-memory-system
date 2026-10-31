---
plan: local-task-done-leaves-board
status: in_progress
created: 2026-11-01
owner: claude (orchestrator)
task_provider: local
task_ref: close-the-task-lifecycle-on-plan-done-and-archive-for-the-local-provider
---

# Plan — Local provider: a done task leaves the board

## Goal
Make the local task provider treat `done` like Notion's Done column: setting a task to `done` moves it off the live board (`tasks/`) into `archive/tasks/`, so closed work stops piling up in `tasks/` without any change to the commands that close it.

## Success criteria
- `set_status(ref, "done")` on a live local task moves `tasks/<ref>.md` to `archive/tasks/<ref>.md` with `status: done` in its frontmatter; `tasks/<ref>.md` no longer exists.
- `set_status(ref, "archived")` on a task already in `archive/tasks/` (status `done`) rewrites it in place to `status: archived`; it still works from `tasks/` as before.
- `set_status(ref, "backlog"|"started")` on a task in `archive/tasks/` moves it back to `tasks/<ref>.md` with the new status.
- `list(project, "done")` and `list(project, "archived")` return tasks from `archive/tasks/`; `list(project, "backlog"|"started")` still reads `tasks/` only.
- `set_status` on a ref in neither directory raises `ValueError`; `delete` still acts on `tasks/` only (an archived or done task raises).
- `scripts/taskprovider/providers/notion/` is unchanged (`git diff --stat` shows no file there).
- `test_local.py` covers each behaviour above; the full gate `bash scripts/run-tests.sh` passes (with the signing overrides).
- Docs no longer say `done` is an in-place flip or that only `archived` moves the file: `providers/local/README.md`, `docs/task-provider.md`, `commands/task.md`.
- A `changelog.d/local-task-done-leaves-board.fix.md` fragment exists.

## Design
- **Status decides location, in the local provider only.** Open statuses (`backlog`, `started`) live in `tasks/`; closed statuses (`done`, `archived`) live in `archive/tasks/`. `set_status` finds the file in either directory, rewrites the frontmatter, and moves it if the target status belongs to the other directory. `list` reads the directory that matches the requested status. `get` and `_unique_ref` already check both directories and stay as they are. `delete` stays live-only.
- This extends the existing exception to the "status lives only in frontmatter" rule (`archived` already moved the file): status is still the single source of truth, the directory is derived from it, and the frontmatter keeps `done` vs `archived` distinct.
- No command changes: `/task done` and close-out flows already set `done`; they now get the move for free.
- No migration: only this instance uses the local provider, and its `tasks/` was already cleaned by hand on 2026-10-31.
- Rejected: `/task done` chaining `archive` (local-only branch in command prose, misses direct `taskctl` calls, collapses `archived`).
- Rejected: wiring `/plan-done` / `/plan-archive` to the task via `task_ref` (duplicates the `/task done` the workflow already runs, misses plan-less tasks).

## Decisions (locked)
- Reopening a closed task moves it back to `tasks/` (not refused).
- Notion provider untouched.
- No migration script; `fix` changelog kind.

## Phases
### Phase 1 — Local provider: done/archived live in archive/tasks
- `scripts/taskprovider/providers/local/__init__.py`: location-by-status in `set_status` and `list`; a helper that finds a ref in either directory.
- `scripts/taskprovider/tests/test_local.py`: update `test_lifecycle`; add tests for done move, done→archived in place, reopen move-back, list by status, unknown-ref raise, delete on a done task raises.
- Docs: `providers/local/README.md`, `docs/task-provider.md` (lines describing `done` as in-place), `commands/task.md` (`done` line notes the move).
- `changelog.d/local-task-done-leaves-board.fix.md`.

**Depends:** none
**Verify:** `python3 -m unittest` over `scripts/taskprovider/tests` passes; `bash scripts/run-tests.sh` passes; `grep -n "in-place\|Only \`archived\` moves\|only \`archived\` moves" scripts/taskprovider/providers/local/README.md docs/task-provider.md` returns nothing; notion dir has no diff.

### Checkpoint — pre-ship
- Validator pass (risk: low, Part A + Part B review).
- Live exercise on this instance: `taskctl set-status <ref> done` on a scratch task, confirm it lands in `archive/tasks/`, reopen it, then delete.
- `git-cli ship --intent "…"`; user merges.

## Risks / open questions
- 35 archived plans predate `task_ref`; unaffected, nothing to do.
