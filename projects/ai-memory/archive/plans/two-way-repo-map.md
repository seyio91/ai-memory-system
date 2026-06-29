---
plan: two-way-repo-map
status: done
created: 2026-06-03
completed: 2026-06-03
owner: orchestrator
---

# Two-way repo ↔ project map

Add the reverse map (project → checkout) to complement the existing forward map
(`.claude/memory-project` in a checkout → project). Path-first, resolved per-environment
via `AI_MEMORY_PROJECTS_ROOT` (default `$HOME/Projects`), git remote as fallback identity.

## Repo-convention adaptations (spec written generically)
- Use the `MEMORY_DIR` **variable** (no `memory_dir()` fn exists here) — matches existing scripts.
- Projects index table has no triggers column → add a **Tags** column (mirrors Domain's Triggers).
- Default `AI_MEMORY_PROJECTS_ROOT=$HOME/Projects` per spec (env-overridden per environment).

## Frontmatter schema (project memory.md)
Three optional fields, validated only when present: `repo` (git remote), `repo_path`
(checkout path relative to `AI_MEMORY_PROJECTS_ROOT`, may be absolute), `tags`. `topic`/`scope`/`summary` stay required.

## Components (strict TDD — test first, watch fail, implement, green)
1. **`_lib.sh`** — `projects_root()` (`${AI_MEMORY_PROJECTS_ROOT:-$HOME/Projects}`); `resolve_repo_path <project>` (repo_path abs/rel → dir check; else git-remote fallback over root children; else exit 1).
2. **`memory-pin.sh`** (new, +x) — run inside a checkout: forward-write `.claude/memory-project`; compute `repo` (origin url) + root-relative `repo_path` (canonicalize root via `cd && pwd -P`); awk upsert into frontmatter (body byte-intact, `-v` for literal values); confirmation print. Missing arg → exit 2; unknown project → exit 1; not-in-git → exit 1.
3. **`lint-memory.sh`** — when `repo_path` present: warn if resolved dir missing / no `.claude/memory-project` / back-pin names a different project. repo/repo_path/tags stay optional.
4. **`regenerate-index.sh`** — Projects table gains a Tags column from `tags` (strip `[ ]`); idempotent.
5. **`_template/memory.md`** — commented examples of the three fields after `summary`.
6. **`commands/pin.md`** — slash command running `memory-pin.sh "$ARGUMENTS"`.
7. **`README.md`** — reverse-map concept, `/pin` workflow, env var + per-env table, new fields, helper/script reference rows, cross-project delegation note (delegate resolves sibling checkout via `resolve_repo_path`).

## Tests
- `test_lib.sh` (extend): projects_root default+override; resolve primary hit; remote fallback; miss→empty+exit 1.
- `test_memory_pin.sh` (new): forward write; frontmatter repo + root-relative repo_path; body preserved; idempotent (`grep -c` == 1); resolves after pin; unknown→1; missing arg→2.
- `test_lint_memory.sh` (extend): valid+matching→0; missing dir→1; wrong back-pin→1.
- `test_regenerate_index.sh` (extend): tags rendered into index.

## Acceptance
- Touched suites green; rest unchanged. Real-tree lint exit 0. Real-tree regen idempotent (empty diff; no project has tags yet). Sandbox end-to-end smoke: pin real git checkout → frontmatter stamped → resolve returns it → lint clean.
