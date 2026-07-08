---
plan: remove-metadata-tier
status: in-progress
created: 2026-07-08
owner: seyi
task_ref: 397f6850-c619-81fa-8af5-eb05f47eb2a9
---

# Remove the metadata.tier feature and the skill write-boundary apparatus

## Goal
Remove `metadata.tier` and the entire skill write-boundary check. Rely on the
existing floors instead — execpolicy (destructive class) and the Validator
(a read-only skill that mutated its target is caught against success criteria).

## Success criteria
- No `metadata.tier` in any authored SKILL.md under `skills/`; no `tier`
  references in scripts / hooks / docs / `identity.md` (outside `archive/`).
- `validate-skills.sh` no longer requires/checks tier; real-tree `validate-skills`
  passes clean (the 6 remote-skill "missing metadata.tier" errors are gone).
- `new-skill.sh` / `install-skill.sh` have no `--tier` flag or tier scaffolding.
- Boundary apparatus fully removed: `scripts/skill-boundary-check.sh`,
  `harnesses/claude/hooks/skill_boundary_check.sh`,
  `harnesses/claude/hooks/skill_boundary_marker.sh`, and the `PostToolUse` (Skill)
  + `Stop` boundary blocks in `harnesses/claude/settings.hooks.json`. No dangling
  references in `install.sh` or drivers.
- **Self-rating system untouched** (separate feature: `skill-ratings.sh`, the
  self-rating partial in new-skill/install-skill).
- Decision records updated: `identity.md` (drop the "Skill write boundary" rule),
  the "Skill subsystem" + "Skill scope & source" decisions in
  `projects/ai-memory/memory.md`, and `docs/harnesses/claude.md`.
- Boundary/tier tests removed (`test_skill_boundary_check.sh`,
  `test_skill_boundary_hooks.sh`) and tier assertions stripped from
  `test_validate_skills.sh` / `test_skill_creator.sh` / `test_skill_ratings.sh` /
  `test_resolve_skills.sh` / `test_skill_manifest.sh` / `test_command_surface.sh`;
  full suite green.

## Design
Full removal (user chose "drop the boundary check entirely"). The check had two
halves — a tier-independent memory-repo own-folder guard and a tier-gated
target-read-only guard — and the decision is to remove **both**, not just the
tier half. Rationale: tier enforcement was detective-only, overlapped execpolicy +
the Validator, and didn't fit the now-dominant remote skills (external repos can't
carry the field — the source of the `validate-skills` false errors). Self-rating is
orthogonal and stays.

**Alternatives considered:** keep the structural own-folder guard ungated
(rejected — user preferred full removal for simplicity; execpolicy + Validator
cover the floor).

## Risks / open questions
- `settings.hooks.json` edits must remove the whole `PostToolUse`(Skill) and `Stop`
  boundary blocks without disturbing the sibling `PreToolUse` (`block_task_tools`)
  or `statusLine` config — keep it valid JSON.
- Agent-skills upstream first-party skills still carry `tier` in their SKILL.md;
  harmless once validate stops checking it — an optional follow-up to strip there,
  out of scope here.
- `archive/plans/skill-subsystem.md` documents the original apparatus — leave as a
  historical record; only the LIVE decision in `memory.md` + `identity.md` change.

## Phases
- [x] Phase 1 — strip `metadata.tier` from authored SKILL.md; remove tier from `validate-skills.sh`, `new-skill.sh`, `install-skill.sh` (drop `--tier`)
- [x] Phase 2 — remove the boundary apparatus: delete `scripts/skill-boundary-check.sh` + the two `harnesses/claude/hooks/skill_boundary_*.sh`; remove the `PostToolUse`(Skill) + `Stop` blocks from `settings.hooks.json`; sweep `install.sh`/drivers for references
- [x] Phase 3 — docs + decisions: `identity.md` (drop the write-boundary rule), `memory.md` ("Skill subsystem" + "Skill scope & source"), `docs/harnesses/claude.md`
- [x] Phase 4 — tests: delete boundary tests, strip tier assertions elsewhere; full suite green + real-tree `validate-skills` clean
