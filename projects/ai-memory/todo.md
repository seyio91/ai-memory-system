# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.

## Active

### Checkpoint-archive: roll working.md checkpoints independently → [plan](plans/checkpoint-archive.md)
- [ ] Phase 1 — scripts/checkpoint-archive.sh (awk section split, snapshot, inline reset, no-op guard)
- [ ] Phase 2 — scripts/tests/test_checkpoint_archive.sh (siblings preserved, reset, no-op, slug, worktree path)
- [ ] Phase 3 — /checkpoint-archive command (wrapper + in-flight gate) + docs
- [ ] Phase 4 — validate (cross-model), suite green, PR
