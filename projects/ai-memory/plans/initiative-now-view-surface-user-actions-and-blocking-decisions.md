---
plan: initiative-now-view-surface-user-actions-and-blocking-decisions
status: done
completed: 2026-11-19
created: 2026-11-18
owner: claude (orchestrator)
task_provider: local
task_ref: initiative-now-view-surface-user-actions-and-blocking-decisions
---

# Plan — Initiative Now view: surface user actions and blocking decisions

## Goal
Make an initiative's Now view lead with what the user must do: blocking decisions first, then user-only actions, then sessions to start. Make Target status lines agree with the blocking derived from `depends_on`.

**Before:** On vault-eks, Ready mixes 4 user actions with 8 sessions. The decision blocking most of the non-prod rollout (`eks/vault-staging-first-consumer`, D84/D79) is row 7 of Blocked. Open proposals is a bare list of 13 ids. Blocked cells say "(at open)". Status lines say `open … blocked_by: none` on Targets that Now lists as Blocked. The decision stream sits between Now and Targets.
**After:** Re-rendered vault-eks Now reads, in order: Decisions needed (D84, D79 → the Targets they hold up), Waiting on you, Sessions to start, Blocked (sorted by how many Targets each holds up), Open proposals (blocking ids first and marked). Dependency suffixes read "(not done)" or "(blocked)". Lint flags open Targets with unfinished dependencies. vault-eks follows the template section order.

## Non-goals
- No new Target field and no format migration. `actor:` was rejected; `next:` already carries the actor.
- No deploy-only qualifier on `depends_on` edges (investigation #6).
- No split of the decision stream into a separate file.
- No change to `initiative-status.sh --tsv` columns or wording (machine contract).
- No lint check on the wording of `next:`.

## Success criteria
- R1 [acceptance] `initiative-render.sh` Now emits, in order: `**Decisions needed**`, `**Waiting on you**`, `**Sessions to start**`, `**Blocked**`, `**Open proposals:**`. An empty section renders `**<name>:** none`. Covered by `test_initiative_render.sh` fixtures.
- R2 [acceptance] Ready rows whose `next:` starts with `user —` (chained `; then …` included) land in Waiting on you. All other Ready rows, including those with no `next:`, land in Sessions to start. Fixture-tested.
- R3 [acceptance] Decisions needed lists each `proposed` D-id cited (as a whole decision-id token, `D<digits>` with an optional lowercase letter such as `D6b`, the stream grammar) in any non-terminal Target's `blocked_by:`, with the Targets it blocks directly and transitively (through `depends_on`). Hold-up does not pass through a done or closed Target, and an edge reported `(not found)` holds nothing up. Open proposals lists those ids first, each suffixed `(blocking)`, then the rest in stream order. A D-id that is not `proposed` is not listed. Fixture-tested.
- R4 [acceptance] Blocked rows are sorted by how many non-terminal Targets each holds up (directly or transitively), most first. Ties keep file order. Fixture-tested.
- R5 [acceptance] Blocked cells render a dependency as `<id> (blocked)` when its derived state is blocked, `<id> (needs <stage>)` for a stage-qualified edge, `<id> (closed)` when the dependency is closed (abandoned, so the edge can never be satisfied and must be rewritten), `<id> (not found)` when unresolved, `<id> (stage unknown)` when the dependency's stage cannot be derived, and `<id> (not done)` otherwise. No `(at ` text remains in render output.
- R6 [acceptance] `lint-memory.sh` WARNs `<initiative>: <target>: status open but depends_on is unsatisfied (<edges>)` for each Target whose `initiative-status.sh --tsv` row has state `open` and deps-satisfied `no`. Satisfaction is the status script's verdict, so lint and Now cannot disagree: a `closed` dependency does not satisfy, a complete `software_adw` dependency does, and a met stage-qualified edge does. Blocked/done/closed Targets are not flagged. A Target whose only unsatisfied edges are `(not found)` is not flagged either: the fix there is to correct the id, and the existing unresolved-`depends_on` WARN reports it. `test_lint_memory.sh` covers a flagged Target and each of those three cases.
- R7 [acceptance] `docs/initiatives.md` and `initiatives/_template.md` state:
  - `next:` starts with `user —` whenever the user acts first;
  - `blocked_by:` holds only blockers that aren't Targets, citing a decision by its D-id;
  - a Target with unfinished `depends_on` is `status: blocked`.

  The hand-written Now fence in `_template.md` equals the renderer's new empty output, and the scaffold check in `test_lint_memory.sh` still passes. `bash scripts/check-docs.sh` passes.
- R8 [acceptance] On the live `initiatives/vault-eks.md` after the hand pass:
  - `initiative-render.sh vault-eks --check` passes;
  - `lint-memory.sh` shows 0 ERRORs and none of the R6 WARNs;
  - the 3 "confirm/decide with the user" rows start `user —`;
  - section order matches `_template.md` (Targets before Current rules and Decision stream);
  - Decisions needed shows D84 and D79 → `eks/vault-staging-first-consumer` plus the non-prod Targets it holds up.
- R9 [parity] On the untouched live vault-eks (before the Phase 3 hand pass), the matrix and Current rules fences are byte-identical between the renderer at `a71071e` and the new renderer — vs `a71071e`, modulo the Now fence. The hand pass itself is expected to change matrix cells (open → blocked).
- R10 [acceptance] Full gate `bash scripts/run-tests.sh` is green with commit and tag signing disabled (`GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false`). Touched suites pass under `PATH="/usr/bin:/bin:$PATH" /bin/bash`. `changelog.d/<id>.feature.md` is present and tells users to run `initiative-render.sh <slug> --write` on each initiative after upgrading, because lint reports the Now fence as stale until they do.

## Design
- **Who acts:** the first actor of `next:` (the text before the first ` — `) decides the grouping: `user` → Waiting on you, else Sessions to start. A doc rule makes authors put `user —` first when the user acts first. Grouping is pure presentation in `render_now`.
- **Decisions needed:** `render_now` already has the proposed ids (`rules_awk prop`) and each Target's authored `blocked_by`. Extract `D[0-9]+` tokens from `blocked_by`, intersect with the proposed ids, then expand blocked Targets transitively over the reverse graph. The graph comes from the `--tsv` `unsatisfied` column, since the renderer never sees raw `depends_on`; the dependency id is extracted from each entry as described under Dependency wording (entries look like `id (at x)` or `id (stage: s) (at x, needs s)`). Satisfied edges hold nothing up, so they are rightly absent. The same reverse-graph count drives the Blocked sort (R4).
- **Dependency wording:** rewrite the `--tsv` `unsatisfied` cell in the renderer, mapping `(at blocked)` → `(blocked)`, `(at closed)` → `(closed)`, `(at X, needs Y)` → `(needs Y)` and `(at X)` → `(not done)`. The dependency id is extracted the way the status script does it: drop the final ` (reason)`, then strip a trailing `(stage: …)` and the whitespace before it. Taking the text before the first `(` was tried and rejected: it resolves edges the status script reports as not found and truncates ids that contain `(`. `initiative-status.sh` is untouched.
- **Lint (R6):** a WARN beside rule 11c, read from `initiative-status.sh --tsv` (state `open`, deps-satisfied `no`). Lint already shells out to `initiative-render.sh --check`, which runs the status script, so this adds no new dependency and keeps one definition of "satisfied".
- Lint from authored states in `scripts/lib/initiative-targets.awk` → rejected: it disagrees with the status script on closed dependencies, complete `software_adw` Targets and stage-qualified edges, so it would warn falsely.
- **Layout:** the template already puts `## Targets` before Rules and the stream; only vault-eks diverges. That makes this a hand reorder of vault-eks with no code change. All stream readers stop at the next `## ` heading.
- `actor:` field → rejected: it is a format change plus a migration, and `next:` already names the actor.
- Text heuristic ("with the user") → rejected: fragile.
- Lint at ERROR → rejected: it would block on authoring lag.
- Deploy-only edge qualifier (#6) → deferred: one case (D83).

**Builds on:** investigation `initiative-now-view-readability`; plan `initiative-now-view-per-env-targets` (#155): `render_now`, `rules_awk`, `scripts/lib/initiative-targets.awk`, lint rule 11b.

## Decisions (locked)
- base: `a71071eeb424ec84c1435354f8ec82abd1854ede` (origin/main at plan time).
- Ships as a `feature` changelog fragment; no migration. Existing initiatives show a stale-fence lint WARN until `initiative-render.sh <slug> --write` is run; the fragment says so.
- Hand edits to the live vault-eks are a phase of this plan, done by the orchestrator with the user's approval. vault-eks is gitignored personal memory.

## Phases
### Phase 1 — Renderer: Now sections, decisions, sort, wording
- Split Ready into Waiting on you / Sessions to start on the first actor of `next:`.
- Add Decisions needed: D-ids from `blocked_by` ∩ proposed, with blocked Targets (direct and transitive).
- Sort Blocked by transitive hold-up count, stable on file order.
- Mark blocking ids in Open proposals and list them first.
- Rewrite the dependency suffixes in the renderer.
- Update `test_initiative_render.sh`: the existing `(at open)` assertion, plus new fixtures for R1–R5.
- Update the Now-format assertion in `test_migration_3_0_0.sh` (it greps the old `**Ready**` heading, so it can no longer fail).

**Files touched:** `scripts/initiative-render.sh`, `scripts/tests/test_initiative_render.sh`, `scripts/tests/test_migration_3_0_0.sh`
**Risk:** medium
**Depends:** none
**Verify:** R1, R2, R3, R4, R5, R9 — `bash scripts/tests/test_initiative_render.sh` passes under both bash 5 and `/bin/bash` 3.2, `grep -c '(at '` on a fixture render is 0, and on the untouched live vault-eks the matrix and rules fences diff empty between the new script and base's renderer, run in print mode from a temp extract of base's `scripts/` (`git archive a71071e scripts | tar -x -C <tmp>`) with `MEMORY_DIR` set to the live tree.

### Phase 2 — Lint WARN and docs
- Add the R6 WARN beside lint rule 11c, read from `initiative-status.sh --tsv`. Extend the comment block's WARN list.
- Add tests: a flagged open Target; unflagged cases for a done dependency, a Closed row, a complete `software_adw` dependency, a met stage-qualified edge and a blocked Target; a flagged case for a `closed` dependency.
- Update the hand-written Now fence in `_template.md` to the renderer's new empty output.
- Add a test that compares the template's Now fence with the renderer's output for a fixture whose Targets are all done (every section `none`), and confirm it fails against the old fence. The existing scaffold check does not compare the fence (it passed with the stale template), and the renderer refuses a file with no Targets, so the all-done fixture is the way to produce the empty output.
- Document the `user —`, `blocked_by:` and `status: blocked` rules in `docs/initiatives.md` (status-line section and Now section) and in the `_template.md` guidance comments. Describe the new Now sections and wording.
- Add `changelog.d/initiative-now-view-actions.feature.md`, including the re-render command for existing initiatives.

**Files touched:** `scripts/lint-memory.sh`, `scripts/tests/test_lint_memory.sh`, `docs/initiatives.md`, `initiatives/_template.md`, `changelog.d/initiative-now-view-actions.feature.md` (new)
**Risk:** low
**Depends:** Phase 1
**Verify:** R6, R7, R10 — `test_lint_memory.sh` passes under `/bin/bash` 3.2, `check-docs.sh` passes, the full gate is green.

### Phase 3 — vault-eks hand pass
- Rewrite the 3 orchestrator rows (`inception/vault-audit-pipeline`, `vault-module/access-policy-framework`, `vault-module/dynamic-aws-credentials`) to start `user —`.
- Set `status: blocked` on every Target the R6 WARN flags. Keep plan-ahead work in the `next:` text.
- Move `## Current rules` and `## Decision stream` after `## Targets`.
- Re-render with `--write` and run `--check` and lint.
- Draft in `/tmp`, user approves, apply after a live-hash check, keep a pre-edit copy.

**Files touched:** `initiatives/vault-eks.md`
**Risk:** low
**Depends:** Phase 1, Phase 2
**Verify:** R8 — `initiative-render.sh vault-eks --check` passes, lint shows 0 ERRORs and no R6 WARN for vault-eks, and the Now fence shows D84/D79 under Decisions needed. Matrix cells for the re-statused Targets read `blocked`.

## Risks / open questions
- Free-text `blocked_by:` that names a decision without a D-id ("pilot apps not chosen") is invisible to Decisions needed by design. R7's doc rule asks authors to cite the D-id.
- After the hand pass most dependency suffixes on vault-eks read `(blocked)`, because 8 of the 20 open Targets will be blocked. Correct, but it makes the suffix less informative there.
- Rewriting the suffix depends on the `--tsv` wording `at <stage>[, needs <stage>]`. Keep a render test that pins it so a status.sh change can't silently break the mapping.
- Feasibility (CAUTION, base `a71071e`): `initiatives/vault-eks.md` is gitignored and absent at base; Phase 3 relies on the working-tree copy.
- Feasibility: the R9 parity run needs base's whole `scripts/` directory in a temp dir, because the renderer finds `initiative-status.sh` and `lib/` relative to itself. It is read-only.
- Phase 1 validated READY at round 4 (`ff26657`). Residual risks accepted: a stage name containing an unbalanced ` (` leaves `(at ` in the cell and drops that edge (reason is split at the last ` (`); authored text containing `(at ` in `depends_on`, `next:` or `blocked_by:` is echoed as written.
- This machine has only `/bin/bash` 3.2.57, so the bash 5 leg of each Verify comes from CI on the PR, not from a local run.
- The live vault-eks changed during Phase 1 (another session): D79 is no longer proposed, so R8's Decisions needed shows D84 only. Re-read the live file before the Phase 3 hand pass.
- Phase 2 validated READY at round 2 (`d18a07d`); the user's signing-off full gate on `d18a07d` (2026-11-18, run from the worktree) passed 70 of 71 suites, with python, lint, skills, doc-vs-code and shellcheck clean. The one failure, `test_opencode_hooks.sh` "malformed stdin -> no injection", depends on the working directory: it fails when run inside a checkout whose parent carries `.agents/memory-project` and passes 19/19 from `/tmp`. The branch touches no opencode file. Residual risks accepted: the not-found skip looks for `(at ` anywhere in the `unsatisfied` cell, so a malformed edge such as `good/x (at least plan)` is still flagged; no test covers a done or closed Target that has unmet dependencies (the code is correct, the guard is unpinned); the WARN shows the raw `--tsv` wording `(at open)` while Now says `(not done)`.
- Final pass (Opus, `decorrelated: no`) on `d18a07d`: all criteria and the scoped goal check pass; it blocked on one docs line (the hand-render rule said `<id> (<wording>)` where the renderer keeps the edge as written). Fixed in `8ab38e1` together with the "unsatisfied `depends_on` edges" wording; that two-phrase docs commit was checked by `check-docs.sh` only, not by a further validator round. R5's `<id> (needs <stage>)` is shorthand: a stage-qualified edge renders `id (stage: s) (needs s)`.
- Accepted from the final pass: hold-up computation is roughly cubic (about 2.4 s for a 60-Target reverse chain, fine at vault-eks size); the new WARN fires for active initiatives without format ERRORs only, like the stale-fence WARN, and the docs do not say so.
- Phase 3 order: the live tree runs the main checkout's scripts, so the hand pass can only be rendered and checked with the new renderer after the PR merges and main is updated.
- Phase 3 applied 2026-11-19 on main at `d2b7b71`: 3 `next:` lines now start `user —`, 7 Targets set to `status: blocked`, Current rules and Decision stream moved after Targets; live `--check` passes, 0 lint ERRORs, no unmet-deps WARN. Decisions needed shows D84 only (D79 was confirmed by another session). `## Normative contract` was left after Now and the matrix, not in strict template order. Before the draft, a preview `--write` reached the live file through a symlinked `config.local.sh` and re-rendered its Now fence; nothing outside the fence changed. Pre-apply copies: `/tmp/p3/vault-eks.pre-p3.md`, `/tmp/p3/vault-eks.pre-apply.md`.
- Deferred: a deploy-only edge qualifier (#6), revisited if a second gate like D83 appears. Splitting the stream into its own file.
