# Todo snapshot — ai-memory — rolled 2026-06-29

> Archived snapshot of `todo.md` at roll time. Covers the github-core migration
> close-out and the user-selectable executor. All items complete.

## GitHub-core migration → [plan](../plans/github-core-migration.md) — ✅ CLOSED 2026-06-29
Migration, follow-ups, validation, and cleanup all done. Plan `status: done`.

- [x] **Restart Claude Code** and accept the one-time external-import approval for `~/.claude/CLAUDE.md` — CLAUDE.md imports (`@RTK.md` + canonical) live in a fresh session
- [x] **Validation B** — first-prompt injection confirmed live; compaction reload proven end-to-end via hook I/O simulation (sentinel write on `source=compact` → next prompt re-injects full 21.7 KB payload incl. `<memory:identity>` + clears sentinel → subsequent prompts revert to 492 B breadcrumb)
- [x] **Validation C spot-check** — `/pin ai-memory` wrote forward marker `.claude/memory-project` + reverse frontmatter (backfilled missing `repo:` URL); `taskctl list <proj> <status>` returns valid JSON across backlog/started/done
- [x] 3 `install.sh`-untouched files (`excalidraw-diagram` skill, `kubernetes-specialist` + `terraform-engineer` agents) were content-identical → switched to repo symlinks (selectable-executor plan Task 9)
- [x] Removed stale `~/.claude/commands/plan.md` (superseded by `/new-plan`)
- [x] Resolved `modules-myccv-s3` `repo_path` lint warning — corrected stray `../`; lint fully clean
- [x] Cleanup done: removed `~/Projects/ai-memory-old` (840K rollback tree) + all 14 `~/.claude/**/*.bak-*` files

### Migration execution gates
- [x] GATE 0 baseline sha256 manifest (101 files) + inventories
- [x] GATE 1 backup tarball + settings.json backup
- [x] GATE 2 clone canonical core (`58abc31`)
- [x] GATE 3 rsync data + integrity proof — 94/94 real files intact
- [x] GATE 4 swap dirs; clean `git status`; removed vestigial `.active_project`
- [x] GATE 5 `install.sh` symlink wiring
- [x] GATE 6 `settings.json` merge (SessionStart + UserPromptSubmit + RTK Bash + block_task_tools + statusLine)
- [x] Validation A — origin, data ignored, DATA INTACT, 11/11 shell tests, taskprovider, lint, index
- [x] `~/.claude/CLAUDE.md` → import `@RTK.md` + canonical; statusline MEMORY_DIR fallback
- [x] domain `## Knowledge` headings on kyverno / landing-zone / terraform — lint clean
- [x] ship `statusline.sh` into core; pushed `5ea313d`

## Selectable executor → [plan](../plans/selectable-executor.md) — ✅ DONE
- [x] Executed: `scripts/executor.sh` (`--which`/`--run`/`--show`) + 23-assertion test; `config.local.sh` keys; identity.md/CLAUDE.md/README reconciled; item-4 files now repo symlinks. 12/12 test files green, lint clean, two-stage + final review passed. **Merged via PR #1.**

_Related completed plans (other machine): `consolidate-into-ai-memory`, `repo-path-mapping`._
