# Todo — claude-memory-system

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Two-way repo ↔ project map → [plan](plans/two-way-repo-map.md)

- [x] **1.** `test_lib.sh` extend → `projects_root` + `resolve_repo_path` in `_lib.sh` (16/16)
- [x] **2.** `test_memory_pin.sh` new → `memory-pin.sh` (13/13)
- [x] **3.** `test_lint_memory.sh` extend → repo_path drift checks in `lint-memory.sh` (12/12)
- [x] **4.** `test_regenerate_index.sh` extend → Tags column in `regenerate-index.sh` (12/12)
- [x] **5.** `_template/memory.md` commented fields
- [x] **6.** `commands/pin.md` slash command
- [x] **7.** README — reverse map section, env var + per-env table, frontmatter fields, reference rows, delegation note, rebuild-spec sync
- [x] **V.** Suite 96/96 (8 files); real lint 0; real regen idempotent (one-time Tags column, then empty diff); e2e smoke passed

### Port v2 improvements → [plan](plans/port-v2-improvements.md)

- [x] **A.** Rewrite `inject_memory.sh` — per-session markers + `additionalContext` contract
- [x] **B1.** `identity.md` — delegate-don't-load + plan-set execution rule
- [x] **B2.** `_template/memory.md` — commented `## Related Projects` block
- [x] **B3.** `~/.claude/CLAUDE.md` — cross-project pointer
- [x] **B4.** README — `## Cross-project relationships` section
- [x] **C.** `scripts/tests/` — `_assert.sh` + 7 test files (66 assertions, all pass). Prereq fixes: `new-project.sh` + `inject_memory.sh` now honor `MEMORY_DIR` (+ `MEMORY_SESSIONS_DIR`) env for sandboxed tests
- [x] **D1.** `new-project.sh` — scaffold-only (no `.active_project` write); README pin-first note (CLAUDE.md had no ref)
- [x] **D2.** README — domain-vs-skill, marker/additionalContext, tests, Related Projects, troubleshooting, design rationale
- [x] **V.** Validate — suite 66/66 pass, lint exit 0, scaffold-only confirmed, inject hook double-pipe verified

### Enforce todo.md over harness TaskCreate

- [x] Write `~/.claude/hooks/block_task_tools.sh` — PreToolUse hook, exit 2 + stderr redirect to todo.md
- [x] Register the hook in `~/.claude/settings.json` under `PreToolUse` (matcher `TaskCreate|TaskUpdate`)
- [x] Hoist a blunt workflow-rules block to the top of `~/.claude/CLAUDE.md`
- [x] Test the hook script directly (pipe TaskCreate JSON, confirm exit 2 + message)

## Done
_(checked items stay above until the file is rolled)_
