# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Session-scoped project pin → [plan](plans/session-project-pin.md)
- [ ] Phase 1 — probe whether Codex supplies `session_id`; add `session_pin_file` to `hooks/lib.sh`
- [ ] Phase 2 — write the pin at SessionStart (non-compact, `hook_chunk_is_first`); prune stale `*.project`
- [ ] Phase 3 — read the pin in `inject.sh`; validate, fall back to cwd on every failure path
- [ ] Phase 4 — breadcrumb: `session:` always, `pinned:` only on divergence (both formatters)
- [ ] Phase 5 — `memory-pin.sh --session` + `commands/pin.md`; **live-exercise the default path**
- [ ] Phase 6 — docs, changelog fragment, mutation-test each control, full suite, branch + PR

## Done
_(checked items stay above until the file is rolled)_
