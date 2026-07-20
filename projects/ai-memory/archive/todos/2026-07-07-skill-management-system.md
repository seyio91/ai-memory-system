# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Skill management system (scope: local/generic × source: authored/remote) → [plan](plans/skill-management-system.md)
_Design locked 2026-07-07 (brainstorm; rebundled from "local vs generic"). Two axes: scope = folders (skills/ vs wholesale-ignored skills-local/); source = declare-not-fork (split manifests + gitignored .skill-cache/). Centralized enumeration. Task 396f6850-c619-814c-87b3-d066cfe059f4._
- [x] Phase 1 — scope foundation: `skills-local/` folder + centralized `_lib.sh:list_skill_dirs` (link-skills + validate-skills route through it; `/skills-local/` gitignored)
- [x] Phase 2 — authored authoring + migrate: `new-skill --local`, migrate client-a, route boundary/ratings/partial through the enumerator
- [x] Phase 3 — remote source layer: split manifests + resolver → gitignored `.skill-cache/` (+ lockfile), cache as a third enumeration root
- [x] Phase 4 — remote authoring + sync: `install-skill --remote --save` write-back to the TOML manifest, `sync-system` resolve/update step, derived `list-skills` (provenance: local authored vs remote referenced)
- [x] Phase 5 — tests (local-authored/remote × generic/local) + docs

## Done
_(checked items stay above until the file is rolled)_
