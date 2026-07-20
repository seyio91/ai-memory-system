# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Session-scoped project pin → [plan](archive/plans/session-project-pin.md) _(archived 2026-07-20)_
- [x] Phase 1 — Codex **does** supply `session_id` (captured stdin dump, `domain/codex.md`) and registers the same shared scripts, so this is cross-harness coverage, not a no-op; `session_pin_file` + `prune_session_pins` added
- [x] Phase 2 — pin written at SessionStart (non-compact, `hook_chunk_is_first`); `*.project` swept after `AI_MEMORY_PIN_RETAIN_DAYS`
- [x] Phase 3 — `inject.sh` honours the pin, validates the project dir exists, falls back to cwd on every failure path
- [x] Phase 4 — breadcrumb: `session:` always, `pinned:` only on divergence, both formatters
- [x] Phase 5 — `memory-pin.sh --session` + `commands/pin.md`. Live-exercised the **pin flow** on the real tree (SessionStart in git-cli → prompt from the memory tree → still git-cli, note emitted). The `--session` *repin* was deliberately **not** run live: it upserts `repo_path` and would overwrite `memory.md`'s `$MEMORY_DIR` sentinel; covered by 3 unit assertions instead
- [x] Phase 6 — docs, changelog fragment, three controls mutation-tested (5/2/1 fails), suite 50/0, **PR #87**
- [x] Confirm on a **new** session that `<memory:active>` carries the `session:` line — confirmed twice through Claude's own hook plane: session `4ce3c201…` (2026-07-20) and again this session, `0c769f83-0b01-4d48-bb29-ed34efc5506e`

## Done
_(checked items stay above until the file is rolled)_
