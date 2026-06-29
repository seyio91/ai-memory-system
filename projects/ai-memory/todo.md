# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### GitHub-core migration → [plan](plans/github-core-migration.md)
Migration + follow-ups are done; remaining = verify in a fresh session, then clean up.

- [x] **Restart Claude Code** and accept the one-time external-import approval for `~/.claude/CLAUDE.md` — CLAUDE.md imports (`@RTK.md` + canonical) are live in this fresh session
- [x] **Validation B** — first-prompt injection confirmed live this session; compaction reload proven end-to-end via hook I/O simulation (sentinel write on `source=compact` → next prompt re-injects full 21.7 KB payload incl. `<memory:identity>` + clears sentinel → subsequent prompts revert to 492 B breadcrumb)
- [x] **Validation C spot-check** — `/pin ai-memory` wrote forward marker `.claude/memory-project` + reverse frontmatter (backfilled missing `repo:` URL); `taskctl list <proj> <status>` returns valid JSON across backlog/started/done _(block_task_tools already confirmed blocking)_
- [x] Decided: the 3 `install.sh`-untouched files (`excalidraw-diagram` skill, `kubernetes-specialist` + `terraform-engineer` agents) are content-identical to the repo (agents differ only by a trailing newline) → **switch to repo symlinks**. Execution folded into selectable-executor plan Task 9.
- [x] Remove stale `~/.claude/commands/plan.md` (superseded by `/new-plan`) — moved to `plan.md.bak-20260629-144555`; `/plan` autocomplete clears next restart
- [x] Resolve `modules-myccv-s3` `repo_path` lint warning — corrected stray `../` (was resolving to `~/ccv-terraform/...`); real path is `ccv-terraform/myccv/modules/terraform-aws-ccv-myccv-s3` under `~/Projects`. Lint now fully clean.
### Selectable executor → [plan](plans/selectable-executor.md)
Supersedes the old "confirm or revert Codex-primary" item. Codex validated as non-functional here (no binary, no deny-rules file); making the executor user-selectable (`claude-subagent` + generic CLI types) via `config.local.sh`. Spec: `docs/superpowers/specs/2026-06-29-selectable-executor-design.md`. Item 4 (3 identical files → repo symlinks) folded in as Task 9.

- [x] Execute `plans/selectable-executor.md` — DONE 2026-06-29 on branch `feat/selectable-executor`. `scripts/executor.sh` (`--which`/`--run`/`--show`) + 23-assertion test; `config.local.sh` keys; identity.md/CLAUDE.md/README reconciled; item-4 files now repo symlinks. 12/12 test files green, lint clean, two-stage + final review passed. **PR open: https://github.com/seyio91/ai-memory-system/pull/1** (awaiting merge).
- [ ] Cleanup after a few days' confidence: `rm -rf ~/Projects/ai-memory-old`; prune `~/.claude/**/*.bak-*`; keep the `~/backups/` tarball

## Done
_(checked items stay above until the file is rolled)_

### GitHub-core migration — executed 2026-06-29 → [plan](plans/github-core-migration.md)
- [x] GATE 0 baseline sha256 manifest (101 files) + inventories
- [x] GATE 1 backup tarball + settings.json backup
- [x] GATE 2 clone canonical core (`58abc31`)
- [x] GATE 3 rsync data + integrity proof — 94/94 real files intact
- [x] GATE 4 swap dirs; clean `git status`; removed vestigial `.active_project`
- [x] GATE 5 `install.sh` symlink wiring (`~/.claude-memory` + hooks/commands/10 skills/2 agents)
- [x] GATE 6 `settings.json` merge (SessionStart + UserPromptSubmit + RTK Bash + block_task_tools + statusLine)
- [x] Validation A — origin, data ignored, DATA INTACT, 11/11 shell tests, taskprovider, lint, index
- [x] `~/.claude/CLAUDE.md` → import `@RTK.md` + canonical; statusline MEMORY_DIR fallback → `~/.claude-memory`
- [x] (a) domain `## Knowledge` headings on kyverno / landing-zone / terraform — lint clean
- [x] (b) ship `statusline.sh` into core (file + install.sh + settings.hooks.json + README); pushed `5ea313d`
