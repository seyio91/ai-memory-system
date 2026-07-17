# Todo — ai-memory (rolled 2026-07-17)

## Active

### Checkpoint-archive: roll working.md checkpoints independently → [plan](plans/checkpoint-archive.md)
- [x] Phase 1 — scripts/checkpoint-archive.sh (awk section split, snapshot, inline reset, no-op guard)
- [x] Phase 2 — scripts/tests/test_checkpoint_archive.sh (siblings preserved, reset, no-op, slug, worktree path)
- [x] Phase 3 — /checkpoint-archive command (wrapper + in-flight gate) + docs
- [x] Phase 4 — validate (cross-model), suite green, PR (#77 merged)
