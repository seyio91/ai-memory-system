# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### consolidate agents to memory system → [plan](plans/consolidate-agents-to-memory.md)
- [x] Phase 1 — create `<memory>/agents/` store + migrate the 4 real agents (drop empty stub)
- [x] Phase 2 — write `scripts/link-agents.sh` (flat-file entries, frontmatter gate, --list/--dry-run, AGENTS_SRC)
- [x] Phase 3 — cut over `~/.claude/agents/` to symlinks; verify agents resolve
- [x] Phase 4 — verify idempotency + safety (repair, no-clobber, stub-skip)
- [x] Phase 5 — document in `domain/agent-tooling.md` (consolidation + translation extension point)

## Done
_(checked items stay above until the file is rolled)_
