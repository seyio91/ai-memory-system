---
plan: github-core-migration
status: done
created: 2026-06-29
completed: 2026-06-29
owner: claude (orchestrator)
---

# Plan — Reconcile local memory system onto the canonical GitHub core

## Goal
The live memory system at `~/Projects/ai-memory` was hand-built and had diverged
(unrelated git history) from the far-more-complete framework on
`github.com/seyio91/ai-memory-system`. Make GitHub the single source of truth
("everything" scope: skills, agents, taskprovider, codex-mem), re-attach the
working dir to that remote, wire it in via the symlink `install.sh`, and keep
all live project/domain data local and uncommitted — so the same core is
reusable across machines.

## Success criteria
- [x] `~/Projects/ai-memory` tracks `origin = seyio91/ai-memory-system`; `git status` clean (data ignored).
- [x] All 12 projects + 4 domain files byte-identical to pre-migration (sha256 proof).
- [x] `~/.claude-memory` + `~/.claude/{hooks,commands,skills,agents}` symlink into the repo.
- [x] `settings.json` merges canonical hooks + keeps RTK Bash hook + statusLine.
- [x] Shell test suite green; taskprovider imports; lint clean (bar 1 env-specific warning).
- [x] **Validation B:** fresh session injects `<memory:*>` on first prompt (live this session); compaction reload proven via hook I/O sim — sentinel on `source=compact` → next prompt re-injects full 21.7 KB payload + clears → later prompts revert to 492 B breadcrumb.

## Design / decisions (locked)
- **Mechanism:** clone-and-swap (clone fresh → rsync gitignored data in → swap dirs), not
  in-place `rm -rf .git && reset --hard`, to avoid untracked-file-collision errors.
  Reaches the same end-state (old `.git` gone, attached to remote).
- **`identity.md` = GitHub's** (same user; canonical wins). Local one discarded.
- **`CLAUDE.md`:** `~/.claude/CLAUDE.md` now imports `@RTK.md` + `@~/.claude-memory/claude/CLAUDE.md`
  (zero-drift). Backed up to `~/.claude/CLAUDE.md.premigration.bak`.
  ⚠ Behavioral change: canonical doc makes **Codex (`codex-mem.sh --executor`) the primary
  executor**, Agent subagent the fallback (was Agent-only). Revisit if undesired.
- **`block_task_tools.sh` is live** — harness `TaskCreate`/`TaskUpdate` are blocked by design;
  `todo.md` is the single source of truth.
- **statusline.sh** committed into the core (`claude/statusline.sh`) and pushed (commit `5ea313d`)
  so it ships across machines via `install.sh`.

## Phases
### Phase 1 — Migration (DONE 2026-06-29)
- [x] GATE 0 baseline sha256 manifest (101 files) + inventories
- [x] GATE 1 backup tarball + settings.json backup
- [x] GATE 2 clone canonical core
- [x] GATE 3 rsync data + data-integrity proof (94/94 real files intact)
- [x] GATE 4 swap dirs; remove empty vestigial `.active_project`
- [x] GATE 5 `install.sh` symlink wiring
- [x] GATE 6 `settings.json` merge (SessionStart + UserPromptSubmit + RTK Bash + block_task_tools + statusLine)
- [x] Validation A (origin, data ignored, DATA INTACT, 11/11 shell tests, taskprovider, lint, index)
- [x] CLAUDE.md import wiring + statusline portability tweak

### Phase 2 — Follow-ups (DONE 2026-06-29)
- [x] (a) domain `## Knowledge` headings on kyverno / landing-zone / terraform (lint clean)
- [x] (b) ship `statusline.sh` into core: file + install.sh step + settings.hooks.json + README; pushed `5ea313d`

### Phase 3 — Verify & clean up (IN PROGRESS — see todo.md)
- [x] Validation B (first-prompt + compaction reload) proven; CLAUDE.md imports live this session
- [x] Validation C — `/pin` forward marker + reverse frontmatter (backfilled `repo:`); `taskctl list` valid JSON
- [x] Remove stale local `~/.claude/commands/plan.md` (→ `plan.md.bak-20260629-144555`)
- [x] Decided + executed: 3 install.sh-untouched files were content-identical → now repo symlinks (done in selectable-executor plan Task 9)
- [x] Fix `modules-myccv-s3` repo_path warning — stray `../` corrected; lint fully clean
- [ ] Cleanup backups & `-old` tree after confidence period

## Key locations
- **Rollback handle:** `~/Projects/ai-memory-old` (original tree, untouched)
- **Backups:** `~/backups/ai-memory-premigration-*.tar.gz`, `premig-data-manifest.txt`, `settings.json.premigration.bak`, `CLAUDE.md.premigration.bak`
- **Detailed gated runbook (transient):** `~/.claude/plans/delightful-tickling-cerf.md`
- **Lint:** fully clean (the former `modules-myccv-s3` `repo_path` warning was a stray `../`, now fixed)

## Risks / open questions
- Codex-primary executor model is now active — confirm it's wanted, or revert CLAUDE.md.
- Validation B unproven until a fresh session is started.
