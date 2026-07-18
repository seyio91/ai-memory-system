# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.

## Active

### Archive investigation when a task is done → [plan](plans/archive-investigation-on-task-done.md)
- [ ] Phase 1 — `/plan-archive` extension (resolve linked investigation, move it)
- [ ] Phase 2 — `lint-memory` rule 10 (stale live investigation)
- [ ] Phase 3 — tests in `test_lint_memory.sh`
- [ ] Phase 4 — docs + changelog entry
- [ ] Phase 5 — archive the `executor-output-normalization` investigation

### Memory injection size guard + compress memory base → [plan](plans/memory-injection-size-guard.md)
- [x] Phase 1 — measure the inline cap ⚠️ **wrong by ~3x** — measured the Bash tool cap (30,000), not the hook cap
- [x] Phase 1a — validate Phase 1 → refuted: hook `additionalContext` cap is ~10,000 chars, budget 20000 unsafe
- [x] ~~Phase 1b — live-confirm the ~10,000 hook cap~~ — CLOSED, superseded (chunking makes the exact cap non-binding)
- [x] ~~Phase 2 — guard in `lib.sh`~~ — CLOSED, superseded: the overflow marker (`lib.sh:151`) already is the guard
- [x] ~~Phase 3 — tests for the guard~~ — CLOSED, superseded: already covered by `test_shared_hooks.sh:177-179`
- [x] Phase 4 — compress `## Architecture Decisions` (34.2KB → 7.5KB, 37 entries intact, validated + repaired)
- [x] Phase 5a — trim gotchas (15.5KB → 4.4KB, 24 entries intact); memory.md 55.3KB → 17.8KB
- [x] Phase 5b — `/checkpoint-archive` on `working.md` (14.2KB → 3.7KB; 8 entries archived, live backlog carried forward)
- [x] **Real fix** — `session_chunks = 12` applied + registered (12 entries/event; payload now 6 chunks, max 8,711 chars)
- [ ] Phase 6 — verify end to end: hook run done (6 chunks, max 8,711 chars, byte-identical reassembly); **awaiting `/clear`** to confirm per-entry budgeting
- [ ] Phase 7 — docs: `session_chunks`/`inject_chunks` + the 10,000-char per-entry cap in `docs/harnesses/claude.md` + changelog (~~`AI_MEMORY_INJECT_WARN_BYTES`~~ — never built)
