# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

- [ ] **Per-worktree `working.md` overlay** — [plan](plans/worktree-working-overlay.md) (task `385f6850`) · design approved, not yet started
  - [x] Phase 1 — shared resolver (`_lib.sh`) + unit tests (6 assertions, mutation-verified; caught+fixed a codex worktree-key bug)
  - [x] Phase 2 — read path via `content-core.sh` (resolver relocated there, `_lib` sources it guarded); AI_MEMORY_CWD wired in Claude+Codex; cross-harness overlay proof in all 3 inject tests, wiring mutation-verified; fixed a minimal-sandbox regression (release/migration/sync)
  - [x] Phase 3 — write path: Codex `codex-mem-checkpoint.sh` → resolver (+seeds fresh overlay, refuses missing base); breadcrumb always advertises the write target; Claude `/checkpoint` targets it; new `test_working_overlay_write.sh` (9) + two-worktree isolation, mutation-verified
  - [x] Phase 4 — `.gitignore` (`working*.md`), lint scans `working.*.md` (+stale-overlay test), docs (file-formats overlay + `.agents/memory-session`); full suite green

## Done
_(checked items stay above until the file is rolled)_
