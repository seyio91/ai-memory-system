# Todo snapshot — ai-memory — 2026-07-08 (skill-data-root)

> Rolled snapshot of completed work. See archive/plans/skill-data-root.md.

- [x] **Skill-data root** — generalized `.skill-data/` for stateful skills; migrated renovate-manager's review store out of the skill dir → [archive/plans/skill-data-root.md](../plans/skill-data-root.md) (executed via codex, independently validated; PR #34 merged)
  - [x] `_lib.sh` helpers (`skill_data_root` / `skill_data_dir`)
  - [x] `scripts/skill-data-dir.sh` CLI (Two-Path)
  - [x] `.gitignore` + `.gitkeep`; `config.local.sh.example` doc
  - [x] renovate-manager: rewrite store resolution (SKILL.md + references/memory.md), delete its `.gitignore`
  - [x] migrate live `renovate-reviews/` tree
  - [x] boundary-check allowlist
  - [x] docs/harnesses/claude.md + decision record + Related Skills line
  - [x] `scripts/tests/test_skill_data_root.sh` + full suite green
