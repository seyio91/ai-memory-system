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
- [ ] Phase 1b — **live-confirm the ~10,000 hook cap** (static analysis only so far); blocks Phase 2
- [ ] Phase 2 — guard in `lib.sh` (close the `1/1` fast path, prepend `<memory:warning>`) — budget TBD from 1b
- [ ] Phase 3 — tests (over-budget, under-budget byte-identical, boundary)
- [x] Phase 4 — compress `## Architecture Decisions` (34.2KB → 7.5KB, 37 entries intact, validated + repaired)
- [x] Phase 5a — trim gotchas (15.5KB → 4.4KB, 24 entries intact); memory.md 55.3KB → 17.8KB
- [ ] Phase 5b — `/checkpoint-archive` on `working.md` (11.3KB `## Checkpoints`)
- [ ] **Real fix** — apply `session_chunks = 12` to the Claude manifest (needs `install.sh --harness claude`)
- [ ] Phase 6 — verify end to end (real hook run, real session start)
- [ ] Phase 7 — docs (`AI_MEMORY_INJECT_WARN_BYTES`) + changelog
