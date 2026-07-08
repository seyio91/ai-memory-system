---
plan: skill-data-root
status: done
created: 2026-07-08
owner: seyi
---

# Generalized skill-data root — decouple stateful-skill state from the skill dir

## Problem
`renovate-manager` stores accumulated review memory in `<skill_dir>/renovate-reviews/`
(inside its own folder, gitignored). This was safe under the symlink/copy skill model
where the skill dir is stable. Under the **remote-reference** model the skill is
materialized into the ephemeral `.skill-cache/<name>/`, and `resolve-skills.sh:142`
does `rm -rf "$dest"` on every resolve/`--update` — so a remote-referenced
`renovate-manager` would lose all review memory on each re-resolve.

Root cause: the skill welds two contents with opposite lifecycles — reusable **code**
(→ shareable/remote) and instance-specific **state** (→ local/persistent). The
scope×source model has no cell for a skill that is remote-source but locally stateful.

## Goal
Introduce a generalized, per-instance **skill-data root** — `.skill-data/` (gitignored,
`AI_MEMORY_SKILL_DATA`, default `$MEMORY_DIR/.skill-data`) — where any stateful skill
persists local data *outside* its (possibly ephemeral) skill dir. Migrate
`renovate-manager`'s store into it, leaving the skill dir pure stateless code so it
can later move to the agent-skills remote without data loss.

## Non-goals
- Declaring `renovate-manager` as a remote skill / removing it from tracked `skills/`
  and adding it to agent-skills — this plan only *enables* that; the move is a
  follow-on.
- Migrating any other skill (renovate-manager is the only stateful one today).

## Design
- **Resolution helper (single source):** `_lib.sh` gains `skill_data_root()` →
  `${AI_MEMORY_SKILL_DATA:-$MEMORY_DIR/.skill-data}` and `skill_data_dir <name>` →
  `<root>/<name>` (mkdir -p + print), mirroring `skill_cache_dir`.
- **Two-Path CLI:** `scripts/skill-data-dir.sh <name>` sources `_lib.sh` and
  prints/creates the dir — the entry point skill prose invokes. Hand path documented:
  `$MEMORY_DIR/.skill-data/<name>/`.
- **Store path:** renovate review memory moves from `<skill_dir>/renovate-reviews/`
  to `$AI_MEMORY_SKILL_DATA/renovate-manager/renovate-reviews/` (same internal tree).
- **Gitignore:** `.skill-data/` ignored wholesale (like `.skill-cache/`), `.gitkeep`
  tracked. renovate-manager's own `.gitignore` is deleted (no longer needed).
- **Boundary check:** `.skill-data/` is gitignored so writes there are invisible to
  the git-diff check anyway; add `.skill-data/<skill>/` to the allowlist defensively.

## Steps
1. `_lib.sh` — add `skill_data_root()` + `skill_data_dir <name>` helpers.
2. `scripts/skill-data-dir.sh` — thin CLI wrapper (Two-Path).
3. `.gitignore` — add `/.skill-data/` block + `!/.skill-data/.gitkeep`; create `.gitkeep`.
4. `config.local.sh.example` — document `AI_MEMORY_SKILL_DATA`.
5. renovate-manager decouple:
   - `references/memory.md` — rewrite "Resolve the store root" to the skill-data path;
     update the "travels with the skill" rationale.
   - `SKILL.md:295` — update the "Review memory lives inside this skill's directory" para.
   - delete `skills/renovate-manager/.gitignore`.
6. Migrate live data: move `skills/renovate-manager/renovate-reviews/` →
   `.skill-data/renovate-manager/renovate-reviews/` (preserve tree, lose nothing).
7. `scripts/skill-boundary-check.sh` — add `.skill-data/<skill>/` to the allowlist.
8. Docs — `docs/harnesses/claude.md`: fix the write-zone #2 example path + note the
   skill-data root as the persistence home for stateful skills.
9. Decision record — extend the "Skill scope & source" decision in
   `projects/ai-memory/memory.md` (stateful skills persist in `.skill-data/<name>/`,
   decoupled from the ephemeral skill dir) + update the renovate-manager Related-Skills line.
10. Test — `scripts/tests/test_skill_data_root.sh`: default resolution, env override,
    CLI creates+prints.

## Success criteria
- `skill-data-dir.sh renovate-manager` prints `<root>/renovate-manager`, dir exists,
  and honors an `AI_MEMORY_SKILL_DATA` override.
- `git check-ignore .skill-data/` passes; no `renovate-reviews` content is git-tracked.
- Existing review data relocated to `.skill-data/renovate-manager/renovate-reviews/`
  with identical file tree (nothing lost).
- `skills/renovate-manager/` has no `renovate-reviews/` and no `.gitignore`; SKILL.md
  + references/memory.md resolve the store via the skill-data root.
- Boundary check does not flag a renovate-manager write to the new store.
- New test passes and the full `scripts/tests` suite stays green.
- Decision record + `docs/harnesses/claude.md` updated.
