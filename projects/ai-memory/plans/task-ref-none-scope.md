---
plan: task-ref-none-scope
status: in_progress
created: 2026-09-10
owner: claude (orchestrator)
task_provider: local
task_ref: 3d7f6850-c619-81e9-b9c1-fe26d24274ff
---

# Plan — Scope `task_ref: none` to plans; drop rule 10's dead guard

## Goal
`task_ref: none` shipped in PR #104 as the plan-only marker but was never scoped, so it silences lint rule 9 on investigations — the rule whose whole job is to force task linkage. Make rule 9 reject `none`, and remove rule 10's unreachable inner guard so the surviving guard is pinned by a test.

## Success criteria
- A live investigation with `task_ref: none` produces a rule 9 WARN; one with a real ref does not; one with no field still does.
- A plan with `task_ref: none` still produces no WARN — rule 12's acceptance of the marker is unchanged.
- Rule 10's inner `plan_ref != "none"` guard is gone, and deleting the surviving outer guard **alone** fails a test (it is not currently mutation-provable; that is the point of the change).
- Rule 9's new `none` rejection is mutation-provable: reverting it alone fails a test.
- `lint-memory.sh` on the real tree still reports exactly 18 WARNs — no live investigation uses `none` today, verified before planning.
- Full suite green under `/bin/bash` 3.2, printed file count reconciled against `tests: N passed`.
- A `changelog.d/` fragment records the tightened rule.

## Design
Per-rule check, no new abstraction. Rule 9's condition becomes "empty **or** `none`" — an investigation is never legitimately plan-only, so for that rule `none` and absent are the same state. Rule 12 is untouched: plans are exactly where the marker is legitimate. Rule 10 loses its inner `plan_ref != "none"` conjunct, which cannot change the outcome because the outer `continue` already guarantees `ref != none`.

Alternatives considered:
- Central helper (`task_ref_is_linked()`) consulted by rules 9/10/12 → rejected: an abstraction over three call sites in one script, and the three rules want *different* answers about `none`, so a shared predicate would need a parameter and stop being shared.
- Document-only → rejected: leaves the fail-open live, which is the defect being fixed.
- Keep rule 10's inner guard as defence-in-depth → rejected: mutual redundancy is precisely why neither guard is individually killable by a mutation, so "defence in depth" here buys an untestable line, not safety.

## Decisions (locked)
- `none` is plans-only vocabulary. Rule 9 rejects it; rule 12 accepts it.
- Redundant guards are removed rather than commented, because the redundancy is what defeats mutation testing.
- Acceptance bar is mutation-provability per guard, not a green suite.

## Phases

### Phase 1 — scope the marker and pin both guards
- Rule 9: treat `none` as absent; update its comment to say why an investigation may not be plan-only.
- Rule 10: delete the inner `plan_ref != "none"` conjunct.
- `test_lint_memory.sh`: assert rule 9 warns on `none`, is silent on a real ref, still warns on absent; assert rule 12 still silent on a plan with `none`.
- Mutation-test each surviving guard **individually** — revert rule 9's `none` arm alone → its tests fail; delete rule 10's outer `none` arm alone → its tests fail. Restore and confirm byte-identical.
- `changelog.d/task-ref-none-scope.fix.md`.

**Depends:** none
**Verify:** the five bullets above, plus `lint-memory.sh` at 18 WARNs and the full suite green with the printed file count reconciled against `tests: N passed`.

### Checkpoint — pre-PR gate
- Full suite, no `| tail`; lint at 18; `git status` clean of probe files.
- Human review, then branch + PR (system change: `scripts/`).

## Risks / open questions
- Tightening a shipped lint rule is a behaviour change for consumers on v1.5.0+. Zero impact on this tree (no investigation uses `none`), but a consumer who adopted the marker on an investigation will newly warn — hence the changelog fragment. Not an `UPGRADING.md` migration: it warns, it does not fail or mutate.
- If a future artifact type gains `task_ref`, this per-rule decision must be revisited rather than copied blindly — the central-helper option is the fallback, recorded above.
