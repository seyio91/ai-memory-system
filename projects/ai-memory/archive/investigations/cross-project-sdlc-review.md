---
kind: investigation
slug: cross-project-sdlc-review
status: concluded — design shipped as the initiative layer; trigger follow-on in plans/initiative-consultation-triggers.md
created: 2026-08-14
task_ref: 3bcf6850-c619-8111-b3b5-ed0e6497569d
---

# Cross-project SDLC synthesis — review and revised recommendation

Review of `cross-project-sdlc-synthesis.md` against both imported branches, the
`fiter-ec2` evidence it cites, and this system's recorded doctrine. Verdict: the
direction — bounded lifecycle contract, no autonomous dispatch, no workflow DSL — is
sound, but the recommendation over-bundles three capabilities and its evidence
weighting is inverted. The evidence supports provenance and visibility; the
recommendation builds enforcement and templates.

## Findings

### 1. Enforcement is not evidence-backed; visibility is

Of the six `fiter-ec2` evidence points, only #5 (sibling status required inspecting
the sibling checkout) demonstrates a gap — and it is a **visibility** gap. No
evidence point shows a transition that occurred when it should have been refused.
The Transition Guard is justified only by hypothetical drift ("the recorded stage
becomes an unsupported assertion").

Recorded doctrine cuts against building it now:

- match each proposed control empirically to the bug class it claims to catch;
- a control is not trusted until it has been watched to fail.

A guard cannot be mutation-tested against drift that has never been observed. The
synthesis's rejected alternative — visibility + templates without enforcement — is
the evidence-supported first step, not the cheap compromise.

### 2. The recommendation builds the Branch-B half and skips the evidence-heavy Branch-A half

Evidence points 1–4 (ADR 0024 splitting one objective, `dispatch-contract.md` as the
normative seam, the FailureKind note-back, the `e81d5e4` contract amendment) are all
**provenance / contract-revision** events — coverage-table row 5, "no authoritative
shared decision/provenance stream." The composed Target Lifecycle addresses rows
2, 3, 4, and 6 and leaves row 5 untouched.

The capability with four evidence points is deferred; the capability with one is
built first. That is drift toward the **control-plane-only** failure mode the
synthesis itself names: state visible, shared semantics decaying into short updates.

### 3. Templates at n=1 contradict the recommendation's own deferral principle

The recommendation defers a workflow DSL "until a second materially different
lifecycle proves it necessary" — then introduces a first-class template mechanism
carrying exactly one real template (`interactive` is effectively the absence of
one). The same principle applies one level down: n=1 does not generalize; with one
instance, per-target declared configuration beats an abstraction inferred from that
instance. Inline the stage list in the lifecycle instance; extract a template object
when the second materially different lifecycle appears.

### 4. The lifecycle instance risks becoming a fourth status representation

"Current stage + status" would sit alongside plan `status:` frontmatter, `todo.md`
checkboxes, and task-provider status — violating the synthesis's own constraint
that one cross-project fact has one authoritative representation. The system
already holds the precedent: `/state` is a **derived** projection, never authored.

The instance should be mostly derived from existing sources (plan frontmatter,
todo, task provider, git/CI), with only the genuinely new facts authored:
dependency edges, next actor, execution mode. A derived instance also dissolves
most of the drift argument motivating the guard — derived state cannot rot
independently of its sources.

### 5. Guard vs Validator overlap is unanswered, and the cheap guard fails open

"Success criteria validated" is already the Validator role's contract. The
recommendation does not say whether the guard consumes validator output or is a
second validation surface — Branch B's carried question ("which parts duplicate the
current task provider, plans, todos, and plan-set execution?") applies directly and
is unanswered. Exit conditions like "human decision recorded" are only as strong as
recording discipline: a checkbox-shaped guard degenerates into self-assertion with
false authority, which is worse than no guard. That is the fail-open control shape
the preventing-drift doctrine exists to catch.

### 6. Minor defects

- "Build toward 1 + 2 + 3, defer option 4" references an enumeration that appears
  in none of the three investigation files. Inferable from open question #1, but
  investigations archive with their task — make the artifact self-contained.
- Open question #8 (what experiment falsifies markdown-first) already has an
  available answer; see the falsification run below.

## Revised recommendation

Invert the sequence: provenance and derived visibility first, enforcement second
and scoped to observed failure, templates extracted only at n=2.

### Phase 1 — Initiative record + derived Target visibility (build now)

- **Initiative**: a markdown artifact carrying the shared objective, the pointer to
  the normative contract in-repo, and an append/supersede decision stream. This
  closes coverage row 5, the row the evidence weights heaviest. Decisions are
  appended and superseded, never rewritten — Branch A's supersession requirement.
- **Target entries** inside the initiative: project ref, task/plan pointers,
  dependency edges, next actor, execution mode. Authored fields only where no
  existing source holds the fact; stage/status **derived** on demand from plan
  frontmatter, todo, task provider, and git/CI state — the `/state` pattern, scoped
  to one initiative. Closes coverage rows 3, 4, and 6 without a fourth status store.
- Stage list, where a Target wants one, is declared inline per Target. No template
  object, no guard code.

### Phase 2 — Transition guard (build after observed drift)

Deferred until phase 1 exhibits a real drift or bad-transition instance. When
built, it is scoped to that observed failure class, consumes Validator output
rather than re-validating, and every exit condition it accepts must be
machine-checkable evidence, not a recorded assertion. If phase 1 never exhibits
drift, the guard is never built — that outcome is success, not an unfinished plan.

### Extracted later, on evidence

- **Template object**: at the second materially different lifecycle.
- **Autonomous progression** (option 4): unchanged — deferred, as in the synthesis.

### Falsification run (answers open question #8)

Dogfood phase 1 on the live initiative: the fiter-ec2 ↔ fiter-provisioning-service
pair, whose next Target (the GitHub Actions adapter) is already known. Hand-author
one Initiative file with its Target entries, zero code, and run the adapter work
through it. Observe:

- whether the decision stream actually gets appended to when the contract next
  changes, or rots;
- whether derived status answered "who is blocked / what is next" without opening
  the sibling checkout;
- where, if anywhere, an unsupported stage assertion appears — that instance is the
  guard's design input.

The markdown-first model is falsified if hand-authoring is skipped under real work
pressure or if derivation cannot answer readiness without loading sibling context.

## Constraints check

The revised shape satisfies every constraint the synthesis lists: no sibling writes
another's working memory (initiative is its own artifact); one authoritative
representation (derived status, in-repo contracts stay normative); append/supersede
decisions; mutable status not injected as durable memory (derived on demand);
execution modes preserved; task/plan bodies not duplicated (pointers only);
deterministic derivation with agent judgment on top; markdown-first, hand-editable;
completed initiatives remain historical.

## Design detail

### System impact (phase 1)

Additive: a tree, a projection, and doctrine prose. The injection contract does not
change — no new hook, no payload growth; initiatives load on demand like domain
files, with at most a breadcrumb row in an affected project's `Related Projects`
table (the static signpost generalizes to point at an active initiative).

- **New top-level scope — DECIDED (2026-08-14): root level.** An initiative is
  the first artifact that is neither `projects/<name>/` (long-lived, repo-local)
  nor `domain/` (timeless): it is cross-project *and it ends*.
  `initiatives/<slug>.md` at the tree root — a peer of `projects/` and `domain/`,
  which is what lets projects bootstrap as peers rather than children (Branch A's
  requirement) — with active → closed → archived lifecycle and the never-read-
  archive rule applying.
- **Wiring obligations, each with a recorded gotcha attached:** `lint-memory.sh`
  globs only `domain/*.md` and `projects/*/…`, so the new tree is silently
  unlinted until wired (part of phase 1, not a follow-up); `regenerate-index.sh`
  needs a third catalog section or deliberate exclusion; the tree is gitignored
  (instances carry client content) with a tracked `_template.md`, keeping it out
  of the commit-route question.
- **`/state` grows a scoped sibling.** Derived Target visibility is `/state`
  scoped to one initiative. Sources already exist: plan frontmatter, `todo.md`,
  task provider, git/PR/CI; `repo_path` locates sibling checkouts, so a
  deterministic script reads sibling state without loading sibling memory into
  context — script reads are not context loads, consistent with delegate-don't-
  load.
- **Orchestrator doctrine, two edits.** Plan-set ordering-as-prose is superseded
  by dependency edges; cross-project rules gain "when a task matches an active
  initiative Target, consult the initiative before delegating."
- **Deferred costs made explicit.** Phase 2's guard makes the Validator an
  interface: its output must become durable and machine-readable (persisted to
  plan or task ref) once a second consumer exists. If task refs become Target
  identities, full-UUID discipline becomes a correctness requirement and the task
  provider's read side enters the coordination path for the first time.
- **Untouched:** schema layer, `working.md` + promotion flow, domain files,
  chunked injection, harness manifests, executor resolution, deny-list.

### ADW execution model — the dispatch initiative as worked example

An ADW is not new machinery: it is the existing Tier-3 pipeline (task → brainstorm
→ plan → executor → validator → PR → human gate) *named as an inline stage list on
one Target*, observed by derivation, depended on across projects. Replaying the
real history as `initiatives/fineract-provisioning-dispatch.md`:

- **Decision stream** holds D1 (ADR 0024 split), D2 (dispatch-contract v1), D3
  (REPAIR added — supersedes D2's operation set, live taint-wedging evidence
  attached), D4 (`e81d5e4`: FailureKind + parsing-invariant fix — supersedes D2's
  schema, service note-back as evidence). The normative contract stays a pointer
  to `fiter-ec2:docs/dispatch-contract.md`; the initiative holds the *why* and
  supersession order, the repo holds the *what*.
- **The FailureKind note-back becomes a decision-stream event, not a hand-carried
  message.** The service session appends D4-proposed with rationale; fiter-ec2's
  derived view shows an unresolved supersession touching its contract; its next
  session picks it up, runs its own plan/implement/validate, lands the amendment,
  and D4 is confirmed with the commit as evidence. Neither project writes the
  other's `working.md`.
- **The evidence-point-5 query** ("where does the adapter stand?") becomes a
  derivation over both projects' plan/todo/task/git state — stage per Target,
  dependency satisfaction, next actor — with no sibling checkout inspection and
  no sibling memory loaded. Nobody authored the status lines, so they cannot
  drift from their sources.
- **The live adapter Target** declares `execution_mode: software_adw`,
  `stages: discover -> design -> plan -> implement -> validate -> review`,
  `depends_on: fiter-ec2/contract (stage: release, at D4)`. Its run is the
  falsification run: `/start` → breadcrumb → load initiative on demand → derived
  dependency check → brainstorm gate → `/new-plan` (one success criterion sourced
  from the initiative: conforms to the contract as of D4) → executor → validator
  → human merge. A discovered contract revision becomes D5-proposed — the
  FailureKind loop, now with a defined path.
- **Phase 1 deliberately does not:** notify the sibling session when a proposed
  decision appears, or refuse a transition. Orchestrators notice unresolved
  supersessions when they derive; honesty comes from derivation. A hand-asserted
  stage the sources don't support, or a decision skipped under work pressure, is
  the phase-2 guard's design input — observed, not argued.

### Execution-mode split: `interactive` vs `software_adw`

Root distinction: **an ADW converges on a known deliverable through a declarable
trajectory; operations work discovers its shape as it goes.** The adapter can
declare its stages before starting; the taint-wedged apply could not — "diagnose
taint wedging" wasn't a stage until the operator was in it. Ops is response-shaped
and done when the system is healthy, not when criteria tick. Hence `interactive`
is the default mode and stages are opt-in — ceremony is claimed, never escaped.

| | `software_adw` | `interactive` |
|---|---|---|
| Driven by | plan + Task Contract | the conversation itself |
| Artifacts | plan, todo ticks, PR, validator verdict | at most a checkpoint / runbook learning |
| Status | **derived** from plan/todo/git/CI | **asserted** — coarse (open/blocked/done + next actor) |
| "Done" means | success criteria validated | operator observed resolution |
| Human gate | a declared stage | meaningless — human in the loop throughout |
| Guard (phase 2) | applicable | structurally inapplicable — no evidence stream |

The status row carries the design weight. Evidence point 6's hand-applied
bootstrap and release-tag credentials are `interactive` Targets whose completion
is a human assertion — and that is *correct*: for ops, human assertion is ground
truth; for an ADW, human assertion replacing derived evidence is exactly the
drift the guard would catch. An interactive Target still carries `depends_on` and
satisfies edges (the adapter depended on the bootstrap) — coordination requires
the Target existing with a status, not ceremony.

The modes meet at two seams, both present in the real history:

1. **Ops escalates into an ADW.** Triage ends where change begins: interactive
   work that discovers a needed code change spawns a task — a `software_adw`
   Target if initiative-relevant, a plain project task otherwise (the
   alert-triage skill's draft-and-delegate boundary).
2. **Ops feeds the decision stream.** D3 originated in an operations event — a
   live apply wedging — not in any ADW stage. Decision appends are
   mode-independent; provenance does not care which mode produced the evidence.

The mode field is how the initiative layer inherits "don't wrap small work in
ceremony" (task tiers 1–2 get no plan, no todo) instead of eroding it: without
it, lifecycle machinery would pressure every Target toward stages that triage,
incidents, and hand-applied bootstraps cannot honor.

## Decisions (confirmed 2026-08-14)

All of the synthesis's open questions are now resolved — Q1 by the phase
sequencing (visibility + provenance first), Q8 by the falsification run, and the
rest decided explicitly:

1. **Location: tree root.** `initiatives/<slug>.md`, a peer of `projects/` and
   `domain/` — projects bootstrap as peers, not children. (Synthesis Q2's
   artifact shape follows: a durable decision log with the normative contract
   held by pointer, per the worked example.)
2. **Target identity: own slug id** (synthesis Q4). Target id =
   `<project>/<slug>`, declared in the initiative file; the task-provider ref is
   an optional `task:` pointer field. Rationale: survives backend swaps
   (task refs are backend-specific), allows Targets with no captured task — the
   real bootstrap/credentials Target had none — and keeps dependency edges
   human-readable and hand-editable (Two-Path). Uniqueness is scoped per
   initiative and lintable.
3. **Creation and closure: explicit both ways** (synthesis Q5/Q6). Creation is a
   deliberate user action (a `/new-initiative` scaffold, matching `/new-project`
   and `/new-plan`); a cross-project discovery in `working.md` may prompt an
   offer, never auto-create. Closure is user declaration only — the derived view
   may report "all Targets complete, candidate for closure" but never closes,
   because auto-close races late-added Targets (the adapter and
   destroy-scheduling Targets were added after the contract work was "done").
   Closed initiatives move to `initiatives/archive/`. Consistent with "the
   system records, never dispatches."
4. **Injection surface: breadcrumb only** (synthesis Q7). No auto-injection. One
   row in an affected project's `Related Projects` table points at the
   initiative; the orchestrator loads it on demand when a task matches. Keeps
   the payload flat (Claude's ~10KB chunk cap is live), honors "mutable status
   is not injected as durable memory," and keeps derivation the honesty
   mechanism. Re-validate in the falsification run: if the breadcrumb is
   repeatedly missed, revisit toward a derived summary — accepting that puts a
   script on the injection path.

Remaining open items are mechanical and belong to the phase-1 plan, not this
document: frontmatter schema, lint rules for the new tree, archive path
convention, and the `/new-initiative` + derivation command shapes.
