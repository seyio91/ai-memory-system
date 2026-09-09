---
plan: initiatives-layer-phase-1
status: done
completed: 2026-09-09
created: 2026-08-14
owner: claude (orchestrator)
task_ref: 3bcf6850-c619-8111-b3b5-ed0e6497569d
---

# Plan — Initiative layer, phase 1

## Goal
Add the root-level initiative layer decided in the `cross-project-sdlc-review`
investigation: `initiatives/<slug>.md` as a peer of `projects/` and `domain/`,
carrying an append/supersede decision stream and Targets with slug ids — the
provenance + derived-visibility half only. No transition guard, no template
object, no autonomous progression, no notifications: those are deferred until
the falsification run exhibits an observed need. Deliverable is the wired
capability (template, lint, catalog decision, doctrine text, `/new-initiative`,
derivation) plus the live dogfood instance already scaffolded on
`feat/initiatives-layer`.

## Success criteria
- `initiatives/_template.md` is tracked; `initiatives/*` instances are
  gitignored (`git check-ignore` confirms an instance, clears the template).
- `lint-memory.sh` reaches `initiatives/*.md`: a deliberately malformed
  initiative file (bad frontmatter, duplicate Target slug within one file, a
  `depends_on` edge naming a Target id that does not exist in that file)
  produces warnings; the template and the clean dogfood instance produce none.
  Each new lint rule is mutation-tested — shown to fire on a seeded defect
  before its green result is trusted.
- `regenerate-index.sh` behavior for `initiatives/` matches the recorded
  catalog decision (section or deliberate exclusion), and running it changes
  nothing outside the AUTOGEN fence.
- `/new-initiative` scaffolds a valid instance from the template: running it in
  a sandbox produces a file that passes the lint rules above, and it refuses to
  overwrite an existing slug.
- Derivation exists and answers the evidence-point-5 query: a command reports,
  for one named initiative, each Target's stage/status (derived for
  `software_adw` from plan frontmatter/todo/task/git via `repo_path`; asserted
  for `interactive`), dependency satisfaction, and next actor — verified against
  the live `fineract-provisioning-dispatch` instance without loading sibling
  memory into context. Output is plain markdown (Two-Path: hand-derivable).
- Orchestrator doctrine (`orchestrator.template.md` + this instance's
  `orchestrator.md`) carries the two edits: dependency edges supersede
  plan-set-order-as-prose; "task matches an active initiative Target → consult
  the initiative before delegating."
- A breadcrumb row for the dispatch initiative exists in the `Related Projects`
  tables of `fiter-ec2` and `fiter-provisioning-service` `memory.md` (the
  generalized signpost row — pointer only, no status).
- Full test suite green (`run-tests.sh`, count reconciled against the summary
  counter, no truncating pager); new shell code is bash-3.2 clean.
- System changes ship via this branch + PR with a `changelog.d` fragment;
  housekeeping (`projects/**` edits from this session) goes to `main`
  separately, per the commit-route rule.

## Design
Settled in the `cross-project-sdlc-review` investigation (Design detail +
Decisions sections) — this plan implements it; it does not reopen it.

- Chosen approach: markdown-first provenance (decision stream, normative
  contract by pointer) + derived Target visibility on the `/state` pattern;
  stage lists inline per Target; `interactive` default mode with asserted
  status; explicit open/close; breadcrumb-only injection.
- Guard-first (synthesis recommendation) → rejected: enforcement not
  evidence-backed; a control is built after it is watched to fail.
- Template object now → rejected: n=1 does not generalize; extract at the
  second materially different lifecycle.
- Authored status in the instance → rejected: fourth status representation;
  derivation is the honesty mechanism.
- Auto-injection of initiative state → rejected: mutable status must not enter
  durable context; ~10KB chunk cap is live.

## Decisions (locked)
- Location: tree root, `initiatives/<slug>.md`; archive at
  `initiatives/archive/`; never-read-archive rule applies.
- Target id: `<project>/<slug>`, unique per initiative; task-provider ref is an
  optional `task:` pointer (full UUID only).
- Creation/closure: explicit user action both ways; derived view may report
  "candidate for closure", never closes.
- Injection: breadcrumb row only; initiative loaded on demand.
- Instances gitignored (client data); template tracked.
- Phase 2 (guard) does not start until the falsification run yields an observed
  drift instance; its design input is that instance.

## Phases
### Phase A — schema + tree wiring (system change, this branch)
- [ ] Finalize `_template.md` frontmatter as the lint contract (fields: `kind`,
      `slug`, `status`, `created`).
- [ ] `lint-memory.sh`: add `initiatives/*.md` to the glob; rules: frontmatter
      valid, Target ids unique in-file, `depends_on` edges resolve in-file,
      `stages:` present iff `execution_mode: software_adw`. Mutation-test each.
- [ ] `regenerate-index.sh`: decide + implement catalog treatment (lean index
      says names/summaries only; likely a small `## Initiatives` section from
      frontmatter, active only). Record the decision in memory.md either way.
- [ ] Tests for both scripts' new behavior under `scripts/tests/`, wired into
      the runner's glob (the ungated-test gotcha).

### Phase B — commands + derivation (system change, this branch)
- [x] `/new-initiative` slash command: scaffold from template, overwrite guard,
      slug validation. Live-exercise its default path (the prose-command
      gotcha — no executable test can gate it).
- [x] Derivation: extend `regenerate-state.sh` or add
      `scripts/initiative-status.sh` — read one initiative file, resolve each
      ADW Target via its project's `repo_path` (plan frontmatter, todo
      checkboxes, task ref, git/PR state), print the readiness table. Bash 3.2.
- [x] Doctrine edits in `orchestrator.template.md`; mirror into this instance's
      `orchestrator.md`.
- [x] `docs/`: initiative layer page (or section) — ships in the release tag,
      so it is reviewable content; `changelog.d/<id>.feature.md` fragment.

### Phase C — dogfood + housekeeping (main, no PR)
- [ ] Breadcrumb rows in `fiter-ec2` and `fiter-provisioning-service`
      `memory.md` Related Projects tables.
- [ ] Run the falsification pass: drive the `gha-adapter` Target's ADW through
      the live instance; record decision-stream appends and any unsupported
      stage assertion in the initiative + `working.md` (guard design input).
- [ ] Archive the four `cross-project-sdlc-*` investigations with their task
      when the falsification run concludes.

## Risks / open questions
- Derivation reads sibling checkouts; a checkout missing or on an unexpected
  branch must degrade to "unknown", never guess (fail closed on absence).
- Catalog treatment is the one genuinely unrecorded mechanical decision — made
  in Phase A, recorded in memory.md.
- The falsification run can conclude *against* markdown-first (stream skipped
  under pressure, derivation can't answer readiness) — that outcome archives
  this layer as refuted, not failed; phase 2 never starts.
- Lint additions must not fire on the template itself (templates are excluded
  by convention — keep it that way).
