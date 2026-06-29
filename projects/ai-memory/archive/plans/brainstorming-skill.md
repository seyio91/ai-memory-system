---
plan: brainstorming-skill
status: done
created: 2026-06-12
completed: 2026-06-12
owner: claude (orchestrator)
---

# Plan — Integrate the gated brainstorming skill

## Goal
Install a gated **brainstorming** Claude Code skill that runs the collaborative design pass (clarify → 2-3 approaches → sectioned design) **only** for Tier-3 feature tasks with open design questions, and folds its approved design into a plan file via `/new-plan`. Wire the gate into `identity.md`, extend the plan scaffold with a `## Design` section, and document it all in the README so a from-scratch rebuild stays coherent. The `SKILL.md` is provided — install it, don't author it.

## Success criteria
- `~/.claude/skills/brainstorming/SKILL.md` exists with `name: brainstorming` and a `description` carrying both the Tier-3-feature trigger and the explicit exclusions (Tier 1, Tier 2, settled Tier-3). Body's terminal handoff is `/new-plan` and folds into `## Goal`/`## Success criteria`/`## Design`/`## Risks`.
- Nothing created under `~/.codex/`.
- `grep -i 'brainstorm' identity.md` returns a routing rule naming both branches (feature-with-open-design → brainstorm; settled → skip); identity still parses (frontmatter/sections intact).
- `/new-plan` scaffold (`~/.claude/commands/new-plan.md`) and any `_template` plan scaffold produce a `## Design` section after `## Success criteria`.
- `lint-memory.sh` exits 0; `regenerate-index.sh` output unchanged (no index row for the skill).
- `grep -i 'brainstorm' README.md` returns the `skills/` tree entry, the gate note, the Task Contract tightening, and the lifecycle note; rebuild ordering stays coherent.
- A dry-run note demonstrates: fires on feature-with-open-design; silent on Tier 1 / Tier 2 / settled Tier-3; design folds into a plan.
- Skill is seed-agnostic (invocable by a future `/start` with a pulled summary) with no `/start` wiring implemented here.

## Decisions (locked)
- Claude-only skill at `~/.claude/skills/brainstorming/SKILL.md`; no Codex twin, no `/brainstorm` slash command, no new scripts/hooks/env vars.
- Trigger is auto via tier + `identity.md`, with the skill `description` as backstop.
- Design lands in the plan body (`## Design` + existing `## Goal`/`## Success criteria`/`## Risks`); no separate committed spec.
- `_template` stays excluded from index/lint/regen; lint has no plan-section check, so `## Design` is additive-safe.

## Phases
### Phase 1 — Install the skill
- Copy provided `SKILL.md` to `~/.claude/skills/brainstorming/SKILL.md` (create `skills/` dir).
- Verify scoped `description` + `/new-plan` handoff; confirm nothing under `~/.codex/`.

### Phase 2 — Anchor the gate in `identity.md`
- Add routing rule in the Orchestration/tier section: feature-with-open-design → brainstorm before `/new-plan`; settled Tier-3 → skip. Verify identity still parses.

### Phase 3 — Extend plan scaffold with `## Design`
- Add `## Design` after `## Success criteria` in `~/.claude/commands/new-plan.md` scaffold (no `_template` plan file exists). Confirm `lint-memory.sh` exits 0.

### Phase 4 — Document in README
- Add `skills/brainstorming/SKILL.md` to the `~/.claude/` tree; note the gate near slash commands; tighten Task Contract note; note skill in knowledge-lifecycle as Claude-only/orchestrator-only.

### Phase 5 — Verify the gate behaves
- Write a dry-run checklist exercising the four classifier cases; confirm fold-into-plan path.

## Risks / open questions
- README's `~/.claude/` tree currently omits `skills/`; must add without breaking rebuild step numbering. → resolved: tree updated, rebuild step 5 now installs the skill.
- `regenerate-index.sh` must be confirmed byte-unchanged (skill is not a domain/project file). → resolved: md5 identical before/after.

## Verification (dry-run)

The gate is two agreeing surfaces: the skill `description` (Claude Code match) + the `identity.md` Orchestration routing rule. Trace each sample input through tier classification → gate decision:

| Sample request | Tier | Open design? | Routes to brainstorming? | Why |
|----------------|------|--------------|--------------------------|-----|
| "add a pluggable export layer with two backends" | 3 (feature) | yes — backend interface, registration, config shape are all unsettled | **YES** | description's trigger + identity rule's "feature with open design questions" branch both fire → brainstorm before `/new-plan` |
| "how does the inject hook resolve the active project?" | 1 (research/Q&A) | n/a | NO | answered directly; description excludes Tier 1; no plan, no executor |
| "fix the typo in `lint-memory.sh`'s usage string" | 2 (quick edit) | n/a | NO | just do it; description excludes Tier 2; no plan/todo entry |
| "rename `working.md` to `scratch.md` across the tree" | 3 (settled) | no — known files, known target | NO | identity rule's "settled shape" branch → skip brainstorming, straight to `/new-plan` |

**Fold-into-plan path (feature case).** brainstorming runs clarify → 2-3 approaches → sectioned design, then `/new-plan <name>` scaffolds the plan (now with a `## Design` section). The approved design populates `## Goal` (clarified purpose), `## Success criteria` (criteria derived *with* the user — the Task Contract tightening), `## Design` (chosen approach + one-line note per rejected alternative), `## Risks / open questions` (deferred items). `## Phases` stays `/new-plan`'s decomposition job. No separate spec file; nothing committed (memory tree is not git-managed).

**Seed-agnostic.** The dialogue is identical whether the seed is a fresh user request or a pulled task summary, so a future `/start` delegates to this skill with no change to it. No `/start` wiring implemented here.

**Mechanical checks (run 2026-06-12):** `lint-memory.sh` exit 0; `regenerate-index.sh` index md5 unchanged; nothing created under `~/.codex/`; `grep -i brainstorm` returns the rule in `identity.md`, `SKILL.md`, and `README.md` (tree + gate + Task Contract + lifecycle).
