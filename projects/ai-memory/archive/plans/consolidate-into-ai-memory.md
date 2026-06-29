---
plan: consolidate-into-ai-memory
status: done
created: 2026-06-29
completed: 2026-06-29
owner: claude (orchestrator)
---

# Plan — Consolidate `claude-memory-system` into `ai-memory` + relative repo_path

## Goal
The remote pushed a tracked meta-project `projects/ai-memory` that is the same
project this machine tracked locally as `projects/claude-memory-system`. Adopt
`ai-memory` as the single name here: merge the richer local `memory.md` into the
tracked one (union-then-trim), move the local archive/working under `ai-memory`,
flip the repo pin, drop `claude-memory-system`. Separately, convert the absolute
`repo_path` values in every project `memory.md` to paths relative to
`AI_MEMORY_PROJECTS_ROOT` so resolution is environment-portable (host vs sandbox).

## Success criteria
- [x] Remote pulled & validated (fast-forward, clean).
- [x] `projects/ai-memory/memory.md` is the union of both files, trimmed to high-level decisions (no changelog/date noise), correct frontmatter (`repo_path: ai-memory`, `repo: …ai-memory-system.git`).
- [x] `claude-memory-system` archive (14 plans, 12 todos, 2 working) + working.md checkpoint moved under `projects/ai-memory/`.
- [x] Repo pin `.claude/memory-project` = `ai-memory`; `projects/claude-memory-system/` removed.
- [x] All 12 absolute `repo_path` values rewritten relative to `AI_MEMORY_PROJECTS_ROOT`; `ai-memory` left as-is (already relative).
- [x] `lint-memory.sh` clean (or only env-specific warnings explained); index regenerated.

## Design / decisions
- **Union-then-trim** memory.md merge (user-chosen): ai-memory's lean structure + every distinct decision/gotcha from claude-memory-system, compressed.
- **Tracked vs ignored:** for `ai-memory`, only `memory.md`/`plans/`/`todo.md` are tracked; `working.md` + `archive/` are gitignored (carve-out already in `.gitignore`). Moving the archive in creates no tracked changes.
- **repo_path = relative**, never absolute and never the literal `$VAR` — `resolve_repo_path` prepends `projects_root()` for non-`/` values. Strip the `/Users/seyi/Downloads/personal/` prefix.
- **Caveat (not fixed):** `ai-memory`'s `repo_path: ai-memory` is the shared/committed value; this machine's checkout is physically at `~/Downloads/personal/claude/memory`, so it won't resolve here. Pre-existing cross-machine tension, out of scope.

## Steps
- [x] Write consolidated `projects/ai-memory/memory.md`
- [x] Move archive (14 plans / 12 todos / 2 working) + `working.md` under `ai-memory`
- [x] Flip pin marker; remove `claude-memory-system`
- [x] Rewrite 12 absolute `repo_path` → relative
- [x] `$MEMORY_DIR` sentinel for ai-memory in `resolve_repo_path` + `lint-memory.sh` (+ tests)
- [x] Reindex + lint validate (lint exit 0; `test_lib` 19/19, `test_lint_memory` 14/14)
