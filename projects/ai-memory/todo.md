# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Local vs generic skills (per-instance skills that don't sync) → [plan](plans/local-vs-generic-skills.md)
_Design locked 2026-07-07 (brainstorm). Dedicated wholesale-ignored `skills-local/` folder; location is the signal (no SKILL.md flag / no per-skill gitignore); centralized enumeration; migrate fiter. Task 396f6850-c619-814c-87b3-d066cfe059f4._
- [ ] Phase 1 — `skills-local/` folder + centralized `_lib.sh:list_skill_dirs` (link-skills + validate-skills route through it; `/skills-local/` gitignored)
- [ ] Phase 2 — authoring (`new-skill --local`, `install-skill`) + migrate fiter-infrastructure-analyzer + audit boundary/ratings scripts
- [ ] Phase 3 — tests + docs

## Done
_(checked items stay above until the file is rolled)_
