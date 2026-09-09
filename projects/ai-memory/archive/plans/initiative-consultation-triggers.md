---
plan: initiative-consultation-triggers
status: done
completed: 2026-09-09
created: 2026-08-15
owner: claude (orchestrator)
task_ref: 3bcf6850-c619-8157-a3d4-e0942a39c3a8
---

# Plan — Initiative consultation triggers (B + C + D composition)

## Goal
Close the trigger failure recorded in the
`initiative-not-consulted-under-work-pressure` investigation: cross-repo
decisions were made mid-work and never reached the initiative decision stream,
and nothing detected the omission. Ship the approved composition — mechanism-
named breadcrumb rows (B), a decision-time question at `/checkpoint` and phase
completion (C), snapshot-based staleness detection surfaced as an exception-only
session-start alert (D), plus the stream-first capture rule in doctrine. No
guard, no permission-gating: detection and timing only, each piece
independently falsifiable on the next initiative-relevant ADW.

## Success criteria
- **Snapshot + staleness:** `initiative-status.sh` maintains
  `initiatives/.state/<slug>.snapshot` (plain hand-readable text; format
  documented for hand-editing per Two-Path). A `software_adw` Target whose
  recomputed derived stage differs from the snapshot while the stream entry
  count is unchanged is reported stale; the warning persists across runs until
  a stream entry is appended or `initiative-status.sh --ack <slug>` is run.
  Each behavior shown by a seeded-defect test: stale fires; ack silences;
  stream append silences; unchanged stage produces no warning.
- **Hook alert:** on the session-start full-payload path, a project with a
  Target in an active initiative gets one `<memory:initiative-alert>` line iff
  a Target is stale; nothing is emitted when fresh; injection completes intact
  when `initiatives/` is missing, empty, or malformed (guard observed working
  in a test that breaks the tree). Local reads only, bash-3.2 clean, no
  measurable payload growth when not firing.
- **C edits:** `commands/checkpoint.md` carries the decision-time question
  ("did this session settle anything that binds another repo? → append
  `<id>-proposed` now, not at handover"); orchestrator doctrine (template +
  local mirror, byte-identical section) carries the same question at phase
  completion.
- **Stream-first rule:** orchestrator doctrine and `docs/initiatives.md` state
  that a cross-repo decision is recorded in the stream at decision time as
  `-proposed`, with plan/runbook/memory entries as projections pointing at the
  stream id.
- **B rows:** both fiter memories' initiative rows name the exact mechanism
  (append `D<n>-proposed` at decision time; never hand-carry; readiness via
  `initiative-status.sh <slug>`), and `docs/initiatives.md` shows the row
  template with that wording.
- **Suite:** full run green, count reconciled, no partial-run banner; new
  shell code verified under `/bin/bash` 3.2; check-docs gate green.
- **Routing:** system changes ride `feat/initiatives-layer` (one coherent PR
  with the layer); breadcrumb-row rewrites are housekeeping on `main`; a
  `changelog.d` fragment covers the trigger mechanisms (extend or accompany
  the existing initiatives-layer fragment).

## Design
Approved via brainstorming 2026-08-15 (seed: the
`initiative-not-consulted-under-work-pressure` investigation; verdict: trigger
failure, not refutation).

- Chosen: cheap composition B + C + D with the stream-first capture rule
  adopted alongside — C gives the rule its trigger moments, D detects when it
  is skipped, B removes the vague-precondition-loses-to-concrete-procedure
  failure (cause 2). Evidence discounted visibility, so no ambient status
  injection; D's alert is exception-only.
- Snapshot anchor: tooling-maintained state file — the instance is gitignored,
  so git history cannot anchor staleness; hand-maintained per-Target fields
  were rejected (they rot; cause 4 would recur inside the mechanism meant to
  catch it).
- Warning persistence: no self-silencing on next session (would recreate the
  invisible-omission shape); explicit ack or a stream append are the only
  exits. Legit no-decision advances cost one `--ack`.
- Delivery: session-start hook, the only surface that runs unconditionally —
  `initiative-status.sh`/lint-only delivery was rejected as circular (the
  observed failure is that nobody runs the command). The hook guard is itself
  fail-open; mitigated by testing the checker separately and documenting the
  limitation as a mechanism.
- Stream-first alone was rejected (a rule with no enforcement point — the
  shape that just failed); rescoped guard was rejected (evidence supports
  detection, not permission-gating; over-building on n=1).

## Decisions (locked)
- Snapshot lives at `initiatives/.state/<slug>.snapshot`, inside the
  gitignored tree; plain text; hand-editable; format documented.
- Staleness = derived stage moved AND stream entry count unchanged, per
  Target, `software_adw` only.
- Alert is one line, exception-only, session-start full-payload path only —
  never per-prompt, never a status table.
- `--ack` is the acknowledgment path; a stream append acknowledges implicitly.
- Stacks on `feat/initiatives-layer`; one PR for layer + triggers.
- **Code reuse is by subprocess, not by an extracted function (settled
  2026-09-09).** Phase A left the staleness check inside
  `initiative-status.sh` with no function boundary extracted; Phase B's text
  had said "shared function, not a fork", which read as a contradiction. The
  requirement is *one implementation*, and a subprocess call satisfies it
  without the hook sourcing the script and inheriting its side effects — the
  wrong coupling for a path that must fail open. Phase B invokes the script.
- **Phases carry their own `**Verify:**` lines (v1.5.0 Task Contract).** Added
  retrospectively 2026-09-09 when the branch was reconciled against
  `origin/main`; Phase C is independent of Phase B and the two fan out in
  parallel.

## Phases
### Phase A — snapshot + staleness in initiative-status.sh (branch) — DONE
- [x] Snapshot write/read/ack (`--ack <slug>`), staleness computation, output
      line(s) in the readiness table or a trailing warning block; script
      header documents format + hand-edit path.
- [x] Seeded-defect tests in `test_initiative_status.sh`: fire / ack-silence /
      append-silence / no-false-positive; bash-3.2 run.

**Depends:** none
**Verify:** all four seeded-defect behaviours demonstrated in
`test_initiative_status.sh` (stale fires, `--ack` silences, stream append
silences, unchanged stage stays quiet) ✅ 38/38 under `/bin/bash` 3.2.

### Phase B — hook alert (branch)
- [ ] `inject.sh` session-start path: active-project Target scan, staleness
      check by invoking `initiative-status.sh` as a subprocess (one
      implementation, no reimplemented logic), emit
      `<memory:initiative-alert>` iff stale; guard so failure never blocks
      injection.
- [ ] Tests in the inject/session-start test files: alert on stale sandbox,
      silent when fresh, injection intact with broken `initiatives/`.
- [ ] Verify payload tail still intact after the alert (the chunking gotcha:
      check the payload's end, not just presence).

**Depends:** Phase A
**Verify:** on a sandbox with a stale Target the session-start full payload
carries exactly one `<memory:initiative-alert>` line, and none when fresh;
the payload's **tail** (`working` renders last) is intact in both cases and
with `initiatives/` missing, empty, and malformed; `grep` proves the hook
shells out to `initiative-status.sh` rather than carrying its own staleness
logic; new tests green under `/bin/bash` 3.2.

### Phase C — prose + doctrine + docs (branch)
- [ ] `commands/checkpoint.md`: decision-time question step. Live-exercise the
      command's default path afterwards (prose-command gotcha).
- [ ] Orchestrator template + local mirror: phase-completion question +
      stream-first capture rule.
- [ ] `docs/initiatives.md`: stream-first rule, snapshot/staleness section,
      breadcrumb row template with mechanism wording; changelog fragment.

**Depends:** Phase A (independent of Phase B — the two can run in parallel)
**Verify:** `commands/checkpoint.md` carries the decision-time question and its
default path was run live once; the stream-first section is byte-identical in
`templates/orchestrator.template.md` and the live `orchestrator.md`;
`docs/initiatives.md` contains the stream-first rule, the snapshot/staleness
section, and the breadcrumb row template; a `changelog.d` fragment exists and
the check-docs gate is green.

### Checkpoint — pre-PR gate (branch)
Not a delegation. Full suite run with the printed file count reconciled against
the `tests: N passed` total and no partial-run banner; `lint-memory.sh` clean
for every file this plan touched; live exercise of `/new-initiative` and
`/checkpoint` (no executable test covers a prose command); human review of the
branch before `git-cli ship`.

**Depends:** Phase B, Phase C

### Phase D — housekeeping (main) + close-out
- [ ] Rewrite both fiter memories' initiative rows to the mechanism wording.
- [ ] Stamp `task_ref` into the seed investigation; on completion, archive it
      with this task via `/plan-archive`.
- [ ] Archive the four `cross-project-sdlc-*` investigations.
- [ ] Record the composition's falsification test in the ai-memory working
      open thread: next initiative-relevant ADW; falsified if a cross-repo
      decision again misses the stream at decision time.

**Depends:** Phase B, Phase C
**Verify:** both fiter memories' initiative rows contain the `D<n>-proposed`
wording and `initiative-status.sh <slug>`; the seed investigation carries
`task_ref: 3bcf6850-c619-8157-a3d4-e0942a39c3a8` and sits under
`archive/investigations/` alongside the four `cross-project-sdlc-*` files; the
falsification test is recorded in `working.md` → `## Open threads`.

## Risks / open questions
- The hook guard is fail-open by necessity; a crashed checker is silent. Named
  limitation, tested checker — accepted until observed failing.
- Snapshot desync (hand-edits, concurrent sessions last-write-wins) degrades
  to a spurious warning or a missed one; the persist-until-ack rule bounds the
  missed-warning window to one stream append.
- `--ack` friction on legitimately decision-free advances is the design's
  chosen cost; if it proves noisy in practice, that observation—not
  argument—drives the next revision.
- Deferred: entries for single-repo decisions (the D5 case that "looked
  single-repo until it wasn't") — revisit only if the falsification test
  fires again with that shape.
