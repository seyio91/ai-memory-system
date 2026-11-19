---
doc: initiative-now-view-readability
kind: investigation
status: open
created: 2026-11-18
owner: claude (orchestrator)
task_ref: initiative-now-view-surface-user-actions-and-blocking-decisions
---

# Investigation — initiative Now view: next actions and blockers still hard to read

Follow-up to `initiative-now-view-per-env-targets` (shipped in #155). Reviewed against the live `initiatives/vault-eks.md` on 2026-11-18. The Now view, Ready/Blocked split, environment matrix and Closed table are a clear improvement. These gaps remain; they are mostly in `scripts/initiative-render.sh` and the Target status-line format (`docs/initiatives.md`, `initiatives/_template.md`).

## Findings

1. **Ready mixes user actions with sessions to start.** In vault-eks, 4 of 12 Ready rows are quick user-only actions (merge a PR, paste command output), and the other 8 are sessions to start. Proposal: split Ready by the actor prefix of `next:` (`user —` vs `<project> session —` / `orchestrator session —`) into "Waiting on you" and "Sessions to start", with user actions first.

2. **Decisions that block work are buried.** `eks/vault-staging-first-consumer` blocks most of the non-prod rollout (4 of 8 Blocked rows) and waits only on user decisions (D84 pilot apps, D79). It shows as row 7 of the Blocked table. Proposal: a "Decisions needed" section at the top of Now, built from Targets whose `blocked_by:` names a D-id or "not chosen" text, plus proposals referenced from `blocked_by:`.

3. **Open proposals are a bare ID list.** `Open proposals: D79 … D94` (13 ids) with no way to tell which block work. Proposal: mark the ids referenced by any Target's `blocked_by:` (e.g. `D79 (blocks eks/vault-staging-first-consumer)`) and list them first.

4. **The Target status line contradicts Now.** Hand-written `blocked_by: none` sits beside a `depends_on` on an unfinished Target, so the status line says "next: /new-plan" while Now lists it as Blocked (e.g. `k8s-addons/vault-addon@non-prod`). Proposal: let the renderer work out blocking from `depends_on`, keep only non-Target blockers (decisions, external) in `blocked_by:`, and have lint flag a Target whose `blocked_by: none` contradicts the `depends_on` it derived.

5. **"(at open)" / "(at blocked)" are jargon.** These suffixes give the dependency's status. Proposal: render "(not done)", or "(blocked)" only when the dependency is itself blocked.

6. **Blocked to plan and blocked to deploy are treated the same.** The D83 gate only stops the non-prod *deploy*, yet the non-prod eks/k8s-addons Targets show as fully Blocked, which hides plan-writing that could run in parallel. Option: an edge qualifier in `depends_on` (e.g. `eks/vault-staging-first-consumer [deploy]`) so Now can show "can plan, deploy gated".

7. **Layout.** In vault-eks the decision stream takes about 320 of 583 lines and sits between Now/rules and Targets. Option: move `## Decision stream` after `## Targets`, or split it into `initiatives/<slug>.decisions.md`. Check what reads the stream (renderer, `/plan-done`, initiative close, lint) before moving it.

## Open questions

- Which of 1–7 to do; 1–3 and 5 are renderer-only, 4 and 6 change the Target format (migration needed), 7 changes file layout.
- Is the actor prefix of `next:` reliable enough to group on, or should Targets get an explicit `actor:` field?

## Success criteria (draft)

- Re-rendering `vault-eks.md` shows user-only actions and blocking decisions above the session work.
- Every id in Open proposals that blocks a Target is marked as blocking.
- No Target has `blocked_by: none` while one of its `depends_on` is not done (lint check passes on vault-eks).
