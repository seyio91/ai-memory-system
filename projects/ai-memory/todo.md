# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

- [x] **Remove metadata.tier + write-boundary** — drop tier field, validate check, --tier scaffolding, and the entire boundary apparatus (scripts + hooks + settings blocks); rely on execpolicy + Validator → [plans/remove-metadata-tier.md](plans/remove-metadata-tier.md)
  - [x] Phase 1 — strip tier from SKILL.md + validate-skills/new-skill/install-skill
  - [x] Phase 2 — remove boundary apparatus (scripts, hooks, settings.hooks.json blocks)
  - [x] Phase 3 — identity.md + memory.md decisions + docs/harnesses/claude.md
  - [x] Phase 4 — tests (delete boundary tests, strip tier assertions) + suite green

## Done
_(checked items stay above until the file is rolled)_
