# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Antigravity hook-archetype (live injection + PreToolUse enforcement) → [plan](plans/antigravity-hook-archetype.md)
_Design approved 2026-07-06 (brainstorm). Pure-hook injection + executor-only PreToolUse guard. Phase 0 (probe tool catalog) gates the rest._
- [x] Phase 0 — probe `agy` tool catalog + `hooks.json` install location (prerequisite) — findings folded into plan; install target = global `~/.gemini/config/hooks.json`
- [x] Phase 1 — PreInvocation live injection (manifest `archetype=hook`; agy.sh exports project; hook driver registers hooks.json) — verified live: agy answered from injected memory
- [ ] Phase 2 — PreToolUse guard (executor-only, `AI_MEMORY_ROLE`-gated) + shared deny-list + Antigravity `exec_readonly`
- [ ] Phase 3 — docs

## Done
_(checked items stay above until the file is rolled)_
