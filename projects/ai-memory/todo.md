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
- [ ] Phase 1 — measure the real inline cap, set the budget default
- [ ] Phase 2 — guard in `lib.sh` (close the `1/1` fast path, prepend `<memory:warning>`)
- [ ] Phase 3 — tests (over-budget, under-budget byte-identical, boundary)
- [ ] Phase 4 — compress `## Architecture Decisions` (37 entries → ≤6KB)
- [ ] Phase 5 — trim gotchas + `/checkpoint-archive` on `working.md`
- [ ] Phase 6 — verify end to end (real hook run, real session start)
- [ ] Phase 7 — docs (`AI_MEMORY_INJECT_WARN_BYTES`) + changelog
