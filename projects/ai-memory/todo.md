# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

- [x] **Skill-data root** — generalized `.skill-data/` for stateful skills; migrated renovate-manager's review store out of the skill dir → [plans/skill-data-root.md](plans/skill-data-root.md) (executed via codex, independently validated; PR opened)
  - [x] `_lib.sh` helpers (`skill_data_root` / `skill_data_dir`)
  - [x] `scripts/skill-data-dir.sh` CLI (Two-Path)
  - [x] `.gitignore` + `.gitkeep`; `config.local.sh.example` doc
  - [x] renovate-manager: rewrite store resolution (SKILL.md + references/memory.md), delete its `.gitignore`
  - [x] migrate live `renovate-reviews/` tree
  - [x] boundary-check allowlist
  - [x] docs/harnesses/claude.md + decision record + Related Skills line
  - [x] `scripts/tests/test_skill_data_root.sh` + full suite green

## Done
_(checked items stay above until the file is rolled)_
