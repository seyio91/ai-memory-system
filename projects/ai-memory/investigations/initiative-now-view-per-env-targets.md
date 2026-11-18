---
task_ref: initiative-format-now-view-per-env-targets-one-line-status-current-rules-index-progress-log
---

# Initiative format: Now view, per-environment Targets, one-line status, current-rules index, progress log

Origin: review of `initiatives/vault-eks.md` with the user, 2026-11-17 (eks session).
Mock-up: `projects/eks/drafts/vault-eks-initiative-format-proposal.md` (real content as of 2026-11-17; user-requested for review).
Builds on: investigation `initiative-structure` (2026-09-23, applied to `k8s-platform-agent.md` only; its task ref no longer resolves). Reuse its `## State` table, AUTOGEN fence, `binds:` and `SUPERSEDED BY` conventions rather than inventing parallel ones.

## Problem (measured on vault-eks.md, 2026-11-17)

- 396 lines, 126 KB, 83 decisions, 29 Targets (11 done). Several `status:` lines run 1,200–2,000 chars.
- "What's next" was not answerable from the file. It needed `initiative-status.sh`, several greps and the orchestrator's own synthesis.
- `status:` mixes three things: the current state, a progress log (`Progress: P1 … P5 …`) and the original scope (`Was: …`). The next step is buried.
- Multi-environment Targets (`eks/vault-estate`, `k8s-addons/vault-addon`, `inception/vault-workspaces`, `k8s-addons/vault-estate-rollout`) stay `open` after staging is done. `initiative-status.sh` then reports dependants as `unsatisfied (unknown)` when they only need staging.
- 25 of 29 Targets have `next_actor: orchestrator (project session)`, which names the actor but never the action.
- Amendment chains (D45→D75→D77→D78, D63→D77d) are only walkable forwards from the new entry. The older entries don't point to their replacements.
- Target-level edges are too coarse for ordering. Gating the non-prod rollout on a staging consumer (D83) needed a new Target to avoid a cycle with the all-environment onboarding Targets.
- `vault-eks.md` never adopted the `initiative-structure` shape, so the earlier fix did not spread.

## Proposed shape (see the mock-up)

1. `## Now`: an AUTOGEN block from `initiative-status.sh <slug> --now`, listing ready Targets with their next action, blocked Targets with their blockers, open proposals and closeable Jira. Never hand-edited.
2. `## Environment matrix`: an AUTOGEN work × env table, from `envs:` in the frontmatter and `@env` Targets.
3. `@env` Targets (`<repo>/<name>@<env>`) for work that repeats per environment. Edges may name a single environment. A later environment's Targets are opened just in time; until then they are matrix rows only.
4. `status:` is one line: `<state> · next: <session — action> · blocked_by: <edges/decisions|none>`. This replaces `next_actor:`.
5. `## Current rules`: an AUTOGEN topic → live decision IDs index, from a new `topic:` line on each decision. Superseded entries drop out, and amended entries show `(as amended by Dn)`.
6. A forward pointer on the status line of amended or superseded entries (`→ D77`), editing only the status line, which matches the `/plan-done` 5b rule.
7. Progress history moves to a sibling `initiatives/<slug>.log.md`: append-only, live and readable, not archived. Closed Targets collapse to one row in a `### Closed` table.
8. Decisions are never archived: they bind every session, and the archive is read only on request. Only Target history leaves the main file.

## Open questions for the design gate

- Are `@env` Targets better than an `envs:` sub-matrix inside a single Target? Consider edge semantics, file size and Jira mapping, where one deploy ticket spans several repos.
- Where does `topic:` vocabulary live: per initiative (frontmatter enum) or free text?
- Migration: a one-off script per initiative (vault-eks, k8s-platform-agent, others) with a reviewable diff. Does `legacy_through:` interplay?
- Is `## State` (initiative-structure) replaced by `## Now`, or does `## Now` absorb it?
- Lint: `lint-memory` checks for one-line status, forward-pointer completeness and an `@env` edge resolving.
- Two-Path principle: every generated block must have a documented hand-edit equivalent.

## Touch points

`scripts/initiative-status.sh` (`--now`, `@env` edge resolution, matrix, topic index), `docs/initiatives.md`, `docs/file-formats.md`, `/plan-done` 5b (forward pointer), `lint-memory`, the migration script, and the `/threads` and `/state` consumers of initiative status.
