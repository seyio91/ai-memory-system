---
kind: investigation
slug: cross-project-sdlc-synthesis
status: active ideation
created: 2026-08-14
task_ref: 3bcf6850-c619-8111-b3b5-ed0e6497569d
---

# Cross-project SDLC and coordination — synthesis

## Goal

Identify a system that supports interactive operations work, structured software-development
work, and cross-project coordination without turning project memory into a monolithic agent
context or prematurely building a software-factory control plane.

Inputs: the imported Branch A and Branch B artifacts, current non-archived `fiter-ec2`
evidence, the sibling provisioning-service seam, current backlog tasks, and existing
ai-memory workflow primitives.

## Common ground

The branches agree on more than they disagree:

- project memory remains repository-local;
- sibling `working.md` files are not a messaging bus;
- cross-project context is bounded and selectively projected;
- software ADW execution is explicit and target-scoped, not the default for operations;
- agent queues, worktrees, CI, retries, and implementation logs do not belong in memory;
- ephemeral agents should not be the durable coordination authority.

The unresolved distinction is the primary shared object:

- Branch A: architectural knowledge and provenance (`Initiative`);
- Branch B: mutable work and dependency state (`Work/Target/Update`).

## `fiter-ec2` evidence

Observed from current, non-archived sources:

1. ADR 0024 divided one objective between `fiter-ec2` workflows/policy and the
   provisioning service's queue, allocation, and adapter.
2. `docs/dispatch-contract.md` became the normative cross-repository seam: operation
   vocabulary, input names, correlation token, artifact keys, and JSON schemas.
3. A real apply exposed Terraform taint wedging. `fiter-ec2` introduced `REPAIR`; the
   provisioning service then needed failure classification and a bounded retry/escalation
   policy.
4. The service sent an explicit note back: add optional `FailureKind` and correct the
   artifact-parsing invariant. `fiter-ec2` amended the contract in `e81d5e4`.
5. Service-side repair policy is complete; the GitHub Actions adapter remains the next
   target. This status required inspecting the sibling checkout rather than reading one
   shared work record.
6. Human gates were first-class in practice: approved architecture decisions, hand-applied
   bootstrap, release-tag credentials, and a required reviewer for destroy.

This was simultaneously:

- a specification revision with durable provenance, supporting Branch A;
- a target/dependency/status transition, supporting Branch B;
- project-local SDLC execution through plans, tests, mutation evidence, releases, and
  human gates, supporting the existing workflow.

## Existing-system coverage

| Need | Existing coverage | Gap |
|---|---|---|
| Locate a sibling boundary | `Related Projects` signpost | Relationship is static; no work instance |
| Execute project-local software work | task -> brainstorm -> plan -> executor -> validator -> PR/human gate | Execution mode is doctrine, not shared target state |
| Preserve local progress | project plan, `todo.md`, `working.md`, task ref | No shared completion rule across projects |
| Coordinate ordered plans | documented plan-set execution | Order is prose and reconstructed by orchestrator |
| Share a contract revision | normative repo document plus manual note/checkpoint | No authoritative shared decision/provenance stream |
| See who is blocked or next | inspect sibling task/plan/git state | No bounded cross-project projection |

## Backlog overlap

### Directly useful but partial

- `3a0f6850-c619-8181-8476-d7b8e8c45dd7` — **Agent-specialized & parallel executors**:
  supplies multi-target fan-out and possibly per-target personas. It is execution substrate,
  not the Work/Initiative model, dependency state, or shared contract record.
- `38ff6850-c619-810e-93c9-e58480054bf2` — **On-demand project load / switch**:
  improves deliberate navigation and context selection. It does not coordinate projects and
  should not become the cross-project model.

### Adjacent evidence, not platform solutions

- The `fiter-ec2` and provisioning-service backlogs hold valid local Targets, including the
  GitHub Actions adapter and later destroy scheduling, but no object joins them to ADR 0024.
- The current platform-assistant backlog is operationally focused and does not cover this
  design.
- Branch protection, test-suite speed, and Antigravity environment trust are unrelated.

## Provisional synthesis: a third branch

Treat Branch A and Branch B as orthogonal layers rather than mutually exclusive systems:

```text
Initiative
  shared objective + specification + decision/provenance stream
      |
      +-- Target: fiter-ec2
      |     local task/plan; execution mode and status
      |
      +-- Target: fiter-provisioning-service
            local task/plan; dependency and human/CI gates
```

The **Initiative** is the semantic envelope. **Targets** are a small coordination projection.
Existing project tasks, plans, todos, executors, validators, and repository artifacts remain
the execution records and sources of implementation detail.

This avoids both failure modes:

- initiative-only: provenance exists but readiness and dependencies remain manual;
- control-plane-only: state is visible but shared semantics decay into short Updates.

The important design question is not whether both concepts exist. The `fiter-ec2` evidence
says they did exist informally. The question is how little new machinery is required to make
their boundary explicit and reliable.

## Confirmed recommendation: provenance and derived visibility first

Confirmed by the user on 2026-08-14 after review of the provisional Target Lifecycle.
The cross-project and SDLC concerns integrate, but they are not one initial feature.

The first capability is an **Initiative record with derived Target visibility**:

```text
Initiative
  shared objective
  normative contract pointer
  append/supersede decision stream
      |
      +-- Target
            project ref
            task/plan pointers
            dependency edges
            next actor
            execution mode
```

The Initiative owns cross-project provenance that no project-local artifact owns. Decisions
are appended and superseded, never silently rewritten. The normative specification remains
in its owning repository; the Initiative points to it and records why and when shared meaning
changed.

Targets author only genuinely new coordination facts: project and task/plan references,
dependencies, next actor, and execution mode. Stage and status are **derived on demand** from
existing task-provider state, plan frontmatter, and `todo.md`, following `/state`'s projection
pattern. Git/CI joins are added only where the dogfood run proves they are needed. This avoids
creating a fourth status representation alongside tasks, plans, and todos.

No lifecycle template or transition guard is part of the first capability. A Target may declare
its expected stages inline if useful, but one software lifecycle is not enough evidence for a
template abstraction. The existing project-local task -> brainstorm -> plan -> executor ->
validator -> human/CI gate workflow remains the software-development path.

### Evidence gates for later capabilities

- **Transition enforcement** is added only after an observed invalid or unsupported transition.
  It must address that failure class, consume existing Validator evidence rather than duplicate
  validation, and accept machine-checkable evidence rather than checkbox assertions.
- **Lifecycle templates** are extracted only when a second materially different lifecycle shows
  real duplication in per-Target declarations.
- **Autonomous progression** remains deferred. Queues, leases, retries, worktree management, and
  external-state monitoring require separate evidence for an execution control plane.

### Falsification run

Dogfood the model on the live `fiter-ec2` and `fiter-provisioning-service` initiative without
adding coordination code. Observe whether the decision stream stays current, whether the derived
view answers "what is next and who is blocked" without loading sibling context into the main
thread, and whether any unsupported lifecycle transition actually occurs.

The markdown-first model is falsified if the Initiative is skipped under real work pressure or
if readiness cannot be derived without reconstructing sibling state manually. An observed bad
transition becomes the input to enforcement design; no observed drift means the guard remains
unbuilt.

Alternatives retained:

- Initiative knowledge without Target visibility preserves provenance but leaves readiness and
  dependencies manual.
- Authored Target stage/status makes visibility easy but duplicates existing state and can drift.
- Building visibility, enforcement, and templates together overweights hypothetical process
  failures and underweights the observed provenance gap.
- Full autonomous progression introduces an execution control plane before evidence requires one.

## Constraints for the eventual proposal

- No sibling project may write another sibling's local working memory.
- One cross-project fact has one authoritative representation and project-specific projections.
- Shared decisions are append/supersede, not silently rewritten.
- Mutable status is not injected as durable architectural memory.
- A Target may choose interactive operations, software ADW, runbook, or automation.
- Existing task-provider and plan files remain project-local; do not duplicate their bodies.
- Deterministic code handles dependency/status transitions; agents interpret discoveries.
- Begin as markdown-first, hand-editable state unless evidence requires a service.
- A completed initiative remains historical while projects continue independently.

## Open design questions

1. Where does the Initiative artifact live: a top-level `initiatives/` tree or inside one
   anchor project?
2. Is Target identity a task-provider ref or its own stable identifier?
3. What explicit event creates an Initiative, and what closes it when Targets may be added late?
4. Which Initiative context, if any, is injected automatically versus loaded on demand?
