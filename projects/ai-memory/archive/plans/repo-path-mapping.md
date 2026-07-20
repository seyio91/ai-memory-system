---
plan: repo-path-mapping
status: done
created: 2026-06-02
completed: 2026-06-02
owner: orchestrator
---

# Bidirectional repo ↔ project mapping

## Problem

The repo→project map is one-way: a checkout names its project via `.claude/memory-project`,
but a project's `memory.md` has no record of where its codebase lives. This breaks the
cross-project relationship flow: when a sibling's `memory.md` is loaded (or delegated to),
the agent has a place to start *reading memory* but no local path to *inspect the actual code*.

## Decision (from brainstorm)

- **Identifier:** path-first, resolved per environment, with the git remote as fallback.
- **Resolution:** env-var root (`AI_MEMORY_PROJECTS_ROOT`) + relative `repo_path`.
  `resolved = $AI_MEMORY_PROJECTS_ROOT/$repo_path`, else locate a checkout of `$repo`.
- **Population:** capture at pin time via a `memory-pin` helper (writes both directions),
  validated by `lint-memory.sh` drift checks.
- Relationship consumers read the path from the **sibling's own frontmatter** (DRY);
  the `## Related Projects` table is unchanged.

## Frontmatter schema (project memory.md)

Three new **optional** fields (validated only when present):

```yaml
---
topic: client-b-terraform
scope: project
summary: Landing-zone Terraform — Okta, EKS, Client-C onboarding   # serves as "description"
tags: [terraform, aws, okta, eks]                                 # new
repo: git@github.com:org/client-b-terraform.git                        # new — portable fallback
repo_path: client-b-terraform                                          # new — relative to AI_MEMORY_PROJECTS_ROOT
---
```

`summary` is kept as the description (the index is built from it); no separate `description` field.

## Components

1. **`scripts/_lib.sh`**
   - `projects_root()` → echoes `${AI_MEMORY_PROJECTS_ROOT:-$HOME/Projects}`.
   - `resolve_repo_path <project>`:
     1. read `repo_path` from `projects/<project>/memory.md`; if `$root/$repo_path` is a dir, print it, return 0.
     2. fallback: scan immediate children of `$root` for a checkout whose `git remote get-url origin` == `repo`; print first match, return 0.
     3. else print nothing, return 1 (caller surfaces the `repo` URL).
   - `extract_fm_field` already handles scalars; `repo`/`repo_path` are scalars. `tags` is a list — not resolved here.

2. **`scripts/memory-pin.sh`** (new) + `~/.claude/commands/pin.md`
   - Usage: `memory-pin <project>` run from inside a git repo.
   - Requires `projects/<project>/` to exist (else error, suggest new-project.sh).
   - Writes `.claude/memory-project` ← `<project>` at the repo root (`git rev-parse --show-toplevel`).
   - Computes `repo` ← `git remote get-url origin` (empty ok), `repo_path` ← toplevel relative to `projects_root()`
     (if toplevel is not under root, store the absolute path and warn).
   - Upserts `repo`/`repo_path` into the project memory.md frontmatter (insert if absent, replace if present),
     touching only the frontmatter block.

3. **`scripts/lint-memory.sh`**
   - For each project memory.md with a `repo_path`: warn if `$root/$repo_path` missing,
     or if that dir's `.claude/memory-project` != project name.
   - `repo`/`repo_path`/`tags` remain optional (no error when absent).

4. **`scripts/regenerate-index.sh`**
   - Surface `tags` in the catalog (replace the empty project "triggers" cell with tags) to aid recall.

5. **`projects/_template/memory.md`**
   - Add the three optional fields (commented or empty) so new projects show the shape.

6. **`README.md`**
   - Document the fields, `AI_MEMORY_PROJECTS_ROOT` (host=`$HOME/Projects`, sandbox=`/workspace`),
     the `/pin` command, and update the "Cross-project relationships" / delegation contract to state
     that a delegate resolves the sibling's checkout via `resolve_repo_path`.

7. **`scripts/tests/`**
   - `test_lib.sh`: extend for `projects_root` + `resolve_repo_path` (primary hit, remote fallback, miss).
   - `test_memory_pin.sh` (new): pin writes both directions; frontmatter upsert idempotent.
   - `test_lint_memory.sh`: extend for drift warn (missing dir, mismatched pin) and clean-when-present.

## Out of scope

- Hook is untouched (resolution is on-demand, not injected).
- No whole-disk repo search; no auto-clone.

## Test plan

Pure bash 3.2, isolated `MEMORY_DIR`/`AI_MEMORY_PROJECTS_ROOT` via `mktemp -d`, real `git init`
repos for pin/resolve tests. Run: `for t in scripts/tests/test_*.sh; do bash "$t"; done`.
