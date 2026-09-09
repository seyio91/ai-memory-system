---
kind: investigation
slug: initiative-not-consulted-under-work-pressure
status: mechanism chosen — B+C+D composition, see plans/initiative-consultation-triggers.md
created: 2026-08-15
owner: claude (orchestrator, fiter-provisioning-service session)
task_ref: 3bcf6850-c619-8157-a3d4-e0942a39c3a8
---

# Investigation — the initiative layer is not consulted under real work pressure

The `fineract-provisioning-dispatch` initiative's own falsification criterion was
met: *"the markdown-first model fails if the decision stream is skipped under real
work pressure."* It was skipped, under exactly that. This file records the
evidence and the candidate causes. **No mechanism is chosen and nothing here is a
work item** — filed for investigation at the user's explicit request.

Originally filed without a `task_ref` (deliberately — the lint WARN was the
signal that no mechanism had been chosen). Attached 2026-08-15 to the
consultation-triggers task once the user ruled trigger-failure and the B+C+D
composition was approved.

## What happened

`fiter-provisioning-service`'s `githubactions` adapter ran eight phases across
2026-08-13 → 2026-08-15 as Target `fiter-provisioning-service/gha-adapter` of an
active initiative. Across all eight phases the initiative file was opened **once**
(2026-08-14, incidentally, while writing D5), and the decision stream was never
consulted before starting any phase.

Three cross-repo decisions were made during the work and none reached the stream
at the time it was made:

- The dispatch ref floor moving `v0.1.0-rc2` → `v0.1.0-rc12`. Recorded as D5 only
  because the file happened to be open that day.
- The `422` on `listener_rule_priority` — a live-verified fact about the seam's
  input types. Recorded in the plan and the repo runbook; **not** in the stream.
- `sandbox_id`'s undocumented 28-character ceiling, found by a failed real
  dispatch (run `31847625590`). Recorded in the plan, the runbook and project
  memory; **not** in the stream.

At handover I proposed sending the last two to `fiter-ec2` by delegating an
executor with a self-contained prompt — the mechanism the Related Projects table
names. The user corrected this: *for events involving `fiter-ec2`, the initiative
approach should be responsible for handover.* They are now D6/D7/D8-proposed, and
the `fiter-ec2/contract` Target is reopened.

**The failure is not that the work went wrong.** Every decision was recorded
somewhere, and the sibling repo would have received all three either way. The
failure is that the record moved with the *work* instead of with the *decision*,
so the stream — the one artifact that makes supersession order legible across
repos — silently stopped being the source of truth while continuing to look
complete.

## Candidate causes

1. **The initiative is never in context.** `identity`, `orchestrator`, the active
   project's `memory.md` and non-empty `working.md` are auto-injected. The
   initiative is reachable only through a Related Projects table row, and
   `scripts/initiative-status.sh` was never run in the session.

2. **Two rules compete in that table, and the weaker-worded one is the right
   one.** The `fiter-ec2` row gives a concrete procedure (delegate, don't load;
   self-contained prompt; plan-only deliverable). The initiative row gives a
   precondition (*consult the initiative before delegating*). A specific
   procedure beats a vague precondition every time — I executed the procedure.

3. **The trigger is at the wrong moment.** Doctrine fires "before delegating",
   but decisions are made *during* implementation, not at delegation. Every one
   of the three above was settled mid-phase, hours before any handover was
   contemplated. A trigger that only fires at the seam cannot catch a decision
   made in the middle.

4. **Nothing derives "this Target has moved and the stream hasn't."** Status is
   derived from plan frontmatter and todo counts; the decision stream is
   append-only prose that no check reads. A stream frozen for three days looks
   exactly like a stream with nothing to say.

Causes 2–4 are the same shape as this system's recorded house failure mode: *a
rule with no enforcement point is not enforced, and its absence is invisible
because the artifact still renders.* Cf. the fail-open CI gates in
`fiter-provisioning-service` (four instances) and `domain/preventing-drift.md`.

## A second, quieter finding

Derived status lagged reality independently of any of this. After the live
dispatch, `initiative-status.sh` reported `gha-adapter` at **implement** — its
implement and validate stages were complete and only human PR review remained,
but derivation reads the plan's `status:` frontmatter and open-todo counts, both
of which are hand-maintained. So a Target's derived stage is only as fresh as
someone's last edit to a *different* file. This matters because
`destroy-scheduling` depends on `gha-adapter (stage: review)`, and its readiness
is therefore gated on bookkeeping rather than on the work.

Worth deciding whether that is a defect or the intended cost of markdown-first
derivation. It is arguably correct — review genuinely is not done until the PR
merges — but the derived stage said `implement`, which was false at the time.

## Candidate mechanisms, none chosen

Listed with what each would cost and what would falsify it.

- **A. Inject derived initiative status at session start**, the way project
  memory is injected, when the active project has a Target in an active
  initiative. Cost: one script run per session (~a table of five rows here) and
  standing context budget. Falsified if the block is present and still not acted
  on — which would show the problem is not visibility.
- **B. Give the initiative row in Related Projects a mechanism**, not a habit:
  name the file, the script, and the exact action ("record a `<id>-proposed`
  entry; do not delegate cross-repo work directly"). Costs nothing, changes no
  code. Falsified if a future session with that wording still delegates directly.
- **C. Move the trigger from delegation to decision.** Fold the question into
  `/checkpoint` and plan-phase completion: *did this phase settle anything that
  binds another repo?* Catches mid-work decisions, which A and B do not. Cost: a
  prompt on every checkpoint, most of which answer no.
- **D. Derive staleness.** Have `initiative-status.sh` flag a Target whose
  derived stage advanced while the decision stream gained no entry. Turns an
  invisible omission into a visible one, which is the shape that has historically
  worked in this system. Cost: needs a per-Target "stream last touched" anchor
  that does not exist yet; risks noise on Targets that legitimately decide
  nothing.

A and B address visibility, C addresses timing, D addresses detection. This
session's evidence points at timing and detection over visibility — the file was
one command away the whole time and the command was never run.

## Open questions

- Is one instance enough to act on? The criterion was stated as a falsification
  test, and it fired once, in the initiative's first real use. Weigh against the
  cost of every session paying for a check that fires rarely.
- Does the decision stream need entries for decisions that bind only one repo?
  All three misses were cross-repo, which is the case the stream exists for — but
  the rc12 floor (D5) looked single-repo until it wasn't.
- Should `-proposed` entries be filed *when the decision is made* rather than at
  handover? That is what would have caught all three, and it is a bigger change
  to the model than any mechanism above.
- Related: `on-demand-project-load.md` and the `cross-project-sdlc-*` files
  already cover adjacent ground on what gets loaded when. Check for overlap
  before any of A–D is designed.
