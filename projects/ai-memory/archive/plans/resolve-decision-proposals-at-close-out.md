---
plan: resolve-decision-proposals-at-close-out
status: done
completed: 2026-10-18
created: 2026-10-17
owner: claude (orchestrator)
task_provider: local
task_ref: investigate-why-decision-stream-proposed-entries-never-get-confirmed
---

# Resolve decision-stream proposals at close-out

## Goal

Give `-proposed` decision-stream entries a defined resolution step: `/plan-done` on an initiative-backed plan asks the user to confirm, reject or leave each unconfirmed proposal in that initiative, and the initiative close procedure requires the same. Confirm drops the suffix (`D<n>:`); reject marks `D<n>-rejected:`.

## Success criteria

- `commands/plan-done.md` has a step that matches the plan's `task_ref` against `- task: <ref>` in active `initiatives/*.md` (exact full ref, same as `/start` Step 1.5), lists every `^- D…-proposed` entry in the matched initiative, and asks per entry: confirm / reject / leave. Confirm rewrites `D<n>-proposed:` → `D<n>:`; reject → `D<n>-rejected:`. No match or no proposals → silent.
- `docs/initiatives.md` defines the three entry states (`-proposed`, confirmed, `-rejected`), states rejected entries stay in the stream, and the Create-and-close procedure says to resolve every `-proposed` entry before closing.
- `doctrine/orchestrator.md` stream-first rule names close-out (`/plan-done`, initiative close) as where proposals are resolved; `test_orchestrator_core_overlay.sh` still passes (≤ 14,336 B).
- `lint-memory.sh` emits no new WARN for a stream containing a `D<n>-rejected:` entry (fixture or live check).
- `changelog.d/` has a `feature` fragment; `bash scripts/run-tests.sh` (signing off) passes in full; PR opened via `git-cli ship --intent`.

## Design

Prompt at the two moments work lands — `/plan-done` for an initiative-backed plan, and initiative close — reusing `/start`'s exact-ref initiative match. Every `-proposed` entry in the initiative is offered, not only ones from that plan, since entries carry no Target link. Confirm/reject is a suffix rewrite, so status stays greppable and rejected decisions remain on record. Prose-only change: no script, hook or lint changes.

Rejected:
- Session-start alert via `initiative-status.sh` + `lib.sh` — user prefers prompts at close-out only.
- Prompt in `/checkpoint` — `/checkpoint` is documented as never asking questions.
- Due-after-N-days or due-when-Target-done — needs entry dates or Target refs (new syntax + backfill).
- Lint gate on closing with open proposals — documented rule is enough for now.
- Delete-on-reject / append "D<m>: confirms D<n>" — loses the record or doubles the stream.

## Decisions (locked)

- Surfaces: `/plan-done` (initiative-backed plans) and the initiative close procedure only.
- Every `-proposed` entry in the matched initiative is due.
- Markers: confirm `D<n>:`, reject `D<n>-rejected:`, leave = unchanged.
- Close rule documented, not linted.

## Phases

### Phase 1 — Document and wire the resolution step
Edit `commands/plan-done.md`, `docs/initiatives.md`, `doctrine/orchestrator.md`; add `changelog.d/resolve-decision-proposals.feature.md`.
**Verify:** criteria 1–4 by reading the diff and a lint run over a scratch initiative holding a `-rejected` entry; doctrine size test passes.

### Phase 2 — Ship
**Depends:** P1
Full suite with signing off; `git-cli ship --intent`.
**Verify:** criterion 5 — suite green, PR URL returned.

## Risks / open questions

- If proposals keep piling up despite close-out prompts, revisit the session-start alert (the `lib.sh` alert path already exists) or a lint gate at close.
- `/plan-done` can't see proposals from work that never produces a plan (decisions recorded during research) — they surface only at initiative close.
