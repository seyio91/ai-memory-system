# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

- [x] **Root skill manifest + template** — moved skills.toml to root, split into tracked `skills.toml.example` catalog + per-instance gitignored `skills.toml` seeded on install (codex-executed, independently validated PASS; PR opened) → [plans/skill-manifest-root-template.md](plans/skill-manifest-root-template.md)
  - [x] Phase 1 — `_lib.sh` + resolve-skills/list-skills/install-skill path updates
  - [x] Phase 2 — `install.sh` seed step
  - [x] Phase 3 — `.gitignore` + migrate content + `git rm skills/skills.toml`
  - [x] Phase 4 — tests + suite green
  - [x] Phase 5 — docs + decision record

## Done
_(checked items stay above until the file is rolled)_
