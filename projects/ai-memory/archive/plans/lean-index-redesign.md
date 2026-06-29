---
plan: lean-index-redesign
status: done
created: 2026-06-03
completed: 2026-06-03
owner: orchestrator
---

# Lean index: projects become a name+summary roster

**Principle / flow:** `index.md` is a roster. Claude reads it, loads the active project's `memory.md`
via the hook injection (or derives `projects/<name>/memory.md` for another project from its name), and
gets file locations (`repo_path`, etc.) from inside that `memory.md`. So the index needs neither the
file **path** nor metadata columns for projects. **Projects only — domain is untouched.**

## Changes
1. **`regenerate-index.sh`**
   - Projects table → `| Project | Summary |` (project = dir name; drop File-path + Tags columns).
   - Domain table → `| Topic | Triggers | Summary |` (drop File-path column; **triggers kept**).
     Path is derivable as `domain/<topic>.md`.
   - **Remove the `## Working memory` section entirely** (working.md is auto-injected; list redundant).
2. **`lint-memory.sh`** — orphan check greps the index by **identifier**, not path: project `<name>`
   → row `| <name> |` in Projects; domain `<topic>` → row `| <topic> |` in Domain. Preserves the
   "forgot to reindex" guard with no path dependency.
3. **README** — document the lean roster + the load flow; note project metadata (`tags`/`repo_path`/
   `repo`) is memory.md-only and the Working-memory section is gone. Domain docs unchanged.

## Untouched (triggers fully preserved)
- Domain index in `index.md` and in `codex-mem.sh` AGENTS.md — keep triggers.
- `lint-memory.sh` still requires `topic triggers summary` on domain files.
- Domain files keep `triggers:`. Project `memory.md` keeps `tags`/`repo_path`/`repo`.

## Tests (TDD: update → fail → implement → green)
- `test_regenerate_index.sh` — projects listed by name+summary; project **paths**, **tags**, `repo`/
  `repo_path` NOT in index; **no `## Working memory` section**; domain rows still carry **triggers**.
- `test_lint_memory.sh` — clean tree still lints 0 (orphan-by-name consistent with regen).

## Acceptance
- Suite green. Real lint 0. Real regen idempotent. `index.md` Projects = `Project | Summary`, no
  Working-memory section; Domain table unchanged with triggers.
