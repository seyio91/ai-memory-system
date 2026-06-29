# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### project-scoped skills: co-locate + per-harness sync → [plan](plans/project-scoped-skills-sync.md)
- [x] Phase 1 — normalize `repo_path` to absolute across all projects (done this session)
- [x] Phase 2 — write `scripts/sync-project-skills.sh` (--harness claude|codex|all, --mode link|copy, --list/--dry-run)
- [x] Phase 3 — migrate `fiter-infrastructure-analyzer` (decided no-op: stays global, generic trigger; defaults recorded)
- [x] Phase 4 — verify + safety (idempotent, repair, no-clobber, skip, link/copy, harness-filter, missing-repo — all pass via fixture)
- [x] Phase 5 — document in `domain/agent-tooling.md`

## Done
_(checked items stay above until the file is rolled)_
