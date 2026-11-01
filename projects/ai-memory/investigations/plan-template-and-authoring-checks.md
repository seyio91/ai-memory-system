---
kind: investigation
task_ref: 402f6850-c619-816e-88b1-f0649303e7d5
slug: plan-template-and-authoring-checks
status: scoped; awaiting /start brainstorm gate
created: 2026-11-01
---

# Plan template and authoring checks

Merged scope of three sources (2026-11-01):
- gaps 3+4 and the plan-vs-PRD review in wiki `sdlc-playbook-comparison`;
- task `3dbf6850-c619-815d-a0b3-c6d2e6a1a7ec` (Plan authoring checks) — merged whole, archived;
- half 1 of task `3dbf6850-c619-8117-8cb5-d8989a06f58c` (Plan position and deviation) — that task keeps
  half 2 (fail-closed position derivation for a lost session).

## Template sections (`/new-plan` scaffold)

- Per-phase `files_touched` (files that change) + plan-level Proof.
- Requirement ids (R1…Rn) in `## Success criteria`; phase `**Verify:**` lines and validator Part A cite them.
- `## Non-goals`.
- Before/after behavior block under `## Goal`.
- `## Security`, required at `risk: high`.
- `## Design` prompt for what the plan builds on — references, no `depends_on` field (initiatives cover ordering).
- Per-phase risk tag.

## Checks

- **Pre-delegation feasibility pass** (read-only, on a drafted plan): named files/symbols exist, Verify
  commands runnable, parallel phases have disjoint `files_touched`, every R-id covered by a phase.
  Verdict READY / CAUTION / REVISE, one revision cycle.
- **Diff drift:** merged diff stays within the plan's `files_touched`.
- **Phase-completion divergence question:** did the work diverge from the plan? If yes, update the plan
  in the same commit.

- **Goal check in validator Part A** (idea 1, 2026-11-01): the validator reads `## Goal` and its
  before/after block, not only criteria + Verify, and judges whether the evidence together shows the
  after-state. Goal missed with all criteria passing → BLOCKED and escalate to the user (user decision).
  Today `agents/validator.md` reads only Verify + Success criteria and checks "nothing beyond them".

## Authoring prose

- Rationalization table in `/new-plan`.
- Cap on brainstorm rounds.
- Scripted YAGNI pushback with a bad example.

Already shipped (excluded): validator round cap; 2-3 approaches in `design-brainstorm`.

## Rejected

Activity-type phases (code / tests / docs); ✅ status marks in criteria; `depends_on:` on plans.
