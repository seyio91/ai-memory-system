---
topic: AI-native SDLC playbook comparison
scope: project
summary: The harness compared against Anthropic Academy's AI-native SDLC Playbook (14 lessons) — gaps, where we are ahead, deliberate mismatches, and the task each gap became
reviewed: 2026-10-23
---

# AI-native SDLC playbook vs this harness

Source: `academy.claude.com/courses/ai-native-sdlc-playbook` — six stages (Plan, Design, Build, Test,
Deploy, Maintain), each a practice + governance + leading/lagging metric. Artifact chain:
`intent.md` → `spec.md` → `plan.md` → `CLAUDE.md`/skills/hooks → evals → `REVIEW.md` → hook gates →
MCP deploy tools → control bands writing a new `intent.md`.

## Gaps

| # | Gap | Course lesson | Our nearest thing |
|---|-----|---------------|-------------------|
| 1 | **No eval suite for the harness itself.** Doctrine, commands, skills, hooks are the product; changes are tested by the shell suite + manual live-exercise only. Course: `evals/*.json` (`from` commit, `prompt`, `may_change`, `checks`), runs on change to `CLAUDE.md`/`.claude/`/`evals/` + nightly; every incident becomes a permanent eval. Only 2/8 skills carry `evals/` despite `skill-audit` rule 11. | 9 | Prose falsification tests in `working.md`; ad-hoc three-way validator comparison |
| 2 | **Guard config is executor-writable.** `guard.sh` reads `scripts/deny-list*.txt`; an executor can `Edit` them — the Bash guard never sees it, `memory_write_guard.sh` only reports after the write. Course: a gate holds only if the agent cannot write the records it reads. | 11 | None |
| 3 | **Plan has no "Files that change" or "Proof".** No mechanical parallel split, no plan-vs-diff drift check; course updates `plan.md` in the same commit when implementation diverges, optionally hook-enforced. | 4 | `**Verify:**` per phase; disjoint file sets drawn by hand |
| 4 | **No requirement traceability.** Course numbers R1…Rn and cites them from work order and proof. Our criteria are numbered but phases' `**Verify:**` don't cite them. | 3, 4 | Numbered `## Success criteria` |
| 5 | **Test-file protection is prose.** Course blocks agent edits to test files during fix tasks with a hook. | 8 | Validator defect class |
| 6 | **Guard decisions not logged.** Course writes every allow/ask/deny with timestamp (OTel). No gate-wait, fire-rate or bypass-attempt data here. | 11, 13 | None |
| 7 | **No process metrics.** Every lesson pairs a leading + lagging indicator. Validator rounds/plan, first-round PR-READY, plan→merge time, recurring defect classes are all derivable from plan frontmatter + git + checkpoints, but live only as narrative. | all | `/activity`, gate wall-clock |
| 8 | Small: deny reasons lack the route to approval; no fast `PostToolUse` shellcheck on the edited `.sh`; no read-only `claude -p` triage of failed CI runs; no nit cap / "Important" definition (`REVIEW.md`). | 6, 10, 11, 12 | `agents/validator.md` covers most of `REVIEW.md` |

## Where we are ahead

- **Validation** — cross-model decorrelation, cold pass before hypotheses, round cap with escalation,
  risk tiers, mutation testing. The course has one verifier subagent and no notion of correlated failure.
- **Context hygiene** — "implementable by someone who never saw the conversation" is structural here:
  every executor is a fresh, self-contained delegation over on-disk artifacts.
- **Memory** — working → memory → domain lifecycle, content contract, size budgets, lint, write guard,
  `project-scan`, vs a one-page `CLAUDE.md` updated "when Claude repeats an error twice".
- **Phase-level contract** — per-phase `**Verify:**` and declared `**Depends:**`; course has one Proof per plan.
- **Cross-repo coordination** — initiatives, decision stream, staleness alerts. Course offers only "a
  dedicated intent repo".
- **Prose-rot gates** — `check-docs.sh`, partial drift gate, hardcoded carrier counts.
- **Legacy linkage** — course's minimum is record↔commit links; we run a push-dominant task projection
  with full-UUID `task_ref`.
- **Separation of duties** — tool-guaranteed (`git-cli` cannot merge), not convention.
- **Harness-agnostic** — same doctrine on claude, codex, copilot, antigravity.
- **Changelog off the model path** — course drafts changelogs with `claude -p` in CI; we write fragments
  per PR while the why is live (deliberate).

## Deliberate mismatches

- **Audit trail lives outside consumer repos.** The course uses product-repo git as the approval record;
  our plans and memory are invisible to client repos. Fine single-owner; with collaborators, commit
  intent/plan artifacts into the consumer repo.
- **`intent.md` + `spec.md` split** fits a product-owner → engineer handoff. Single owner, so
  `design-brainstorm` → plan is the right compression; borrow R-ids and an "areas of concern" list only.
- **Managed settings / Claude-side OS sandbox** — enterprise controls; codex sandboxing suffices apart from gap 2.
- **MCP-per-environment deploy tools, rehearsed rollback, control bands** — not applicable to this repo;
  relevant to fiter provisioning and `alert-triage` (deterministic detection before any model call).

## Plan vs PRD (reviewed 2026-10-31)

Sample: `docs/prd/devcontainer-identity-support.md` — closer to a design spec/RFC than a
classic PRD (no personas or business metrics). A PRD says what the feature is and why, and stays in the
product repo, updated as it changes. A plan says how we deliver and how each step is proven, lives in
the memory tree, and archives on completion.

| PRD section | Our equivalent | Verdict |
|-------------|----------------|---------|
| Executive Summary + Key Design Decision | `## Goal` + `## Design` chosen approach | parity |
| Problem Statement / User Impact (before/after shell sessions) | one-paragraph Goal | **borrow** before/after block |
| Design Goals (constraints every choice respects) | `## Decisions (locked)` (choices, not constraints) | partial |
| Prerequisites (builds on another PRD) | nothing explicit | **borrow** as a Design prompt (reference, not a gate) |
| Technical Specification | `## Design` bullets | thinner by design — executors read code |
| Security Considerations | generic `## Risks` | **borrow**, required at `risk: high` |
| Future Enhancements | `## Risks / open questions` | **borrow** as `## Non-goals` |
| Testing Strategy | per-phase `**Verify:**`, validator, mutation testing | ahead |
| Implementation Checklist (phases by activity: code / tests / docs) | `## Phases` + Depends + Verify | ahead — activity phases fail our sizing rules |
| Success Criteria (✅ list) | `## Success criteria` | ahead — theirs mixes status into spec, some items uncheckable |

Rejected:
- **`depends_on:` on plans** — initiative Targets already carry stage-qualified `depends_on` with derived
  readiness, and Target ids allow same-project Targets. Only uncovered case (same-repo plan ordering, no
  shared decisions) is rare.
- **Durable spec in consumer repos** (copy Goal/Design/invariants to `docs/design/` at close) — the
  plan's intent archives with it, but not pursued while single-owner. Same root as the audit-trail
  mismatch above. Small for this repo: `docs/` and command/skill prose are the spec.
- Activity-type phases; ✅ marks in criteria.

Borrowings folded into the gaps 3+4 task.

## Suggested order

Gap 2 (small, real blast radius) → gap 1 (needs a design pass: CI API cost, scoring prose behaviour) →
gaps 3+4 → gaps 6+7 → gaps 5, 8.

## Tasks

| Gap | Task |
|-----|------|
| 2 | `402f6850-c619-8118-a392-e5815438ab0a` — protect guard config from executor edits |
| 1 | `402f6850-c619-81bd-b67b-f3c49da741bc` — eval suite for harness behaviour |
| 3, 4, PRD | `402f6850-c619-816e-88b1-f0649303e7d5` — plan template: files, R-ids, diff drift, PRD borrowings |
| 6, 7 | `402f6850-c619-8123-b237-ec04f47b7fb0` — guard decision log + process metrics |
| 5 | `402f6850-c619-8102-a44b-e46f36f47f99` — hook-enforced test-file protection |
| 8 | `402f6850-c619-8135-b83d-d3e22469177d` — small adoptions |
