---
kind: investigation
slug: cross-project-sdlc-branch-a
status: imported ideation branch
created: 2026-08-14
task_ref: 3bcf6850-c619-8111-b3b5-ed0e6497569d
---

# Cross-project SDLC ideation — Branch A

Imported from the user-provided artifact **Branch A — Result and Conclusion for Review**.
This record preserves the branch as an independent hypothesis; it is not an approved design.

## Hypothesis

Keep the memory system project-centric, but add a bounded cross-project **initiative**
scope for knowledge that changes what several projects are building or why.

```text
project memory      repository-local implementation context
initiative memory   shared goal, specification, decisions, discoveries, provenance
ADW                 optional execution workflow for one project-local change
```

Projects and initiatives are many-to-many. Projects are long-lived; initiatives end.
The initiative does not own project implementation state or execution machinery.

## Motivating failure

Implementation in one repository can invalidate a shared specification. The concrete
example was a direct `delete` lifecycle becoming `active -> retire -> delete` after
Terraform teardown proved to require layers. Writing the discovery directly into a
sibling project's `working.md` gives the source project ownership of the sibling's
scratch state and loses a single authoritative account of why the contract changed.

## Proposed responsibility

Initiative memory carries only cross-project truth:

- goal and initial specification;
- affected projects and their responsibilities;
- implementation discoveries that revise the specification;
- shared constraints and architectural decisions;
- supersession history and rationale.

Project memory continues to carry local implementation, debugging, tests, and current
state. An ADW remains independent and is invoked only for work that benefits from a
structured software-development workflow.

## Strength

Preserves semantic provenance. A future agent sees not merely "add REPAIR/retire" but
the live evidence that made the prior lifecycle unsafe, reducing the chance that the
distinction is later removed as accidental complexity.

## Risk

An initiative can explain shared change without answering who is waiting, what target
is ready, which human must act, or whether all project responsibilities are complete.
If mutable work state is added casually, initiative memory can become an implicit
project-management system without a clear contract.

## Review questions carried forward

- Is initiative genuinely a new scope, or a composition of existing artifacts?
- Is it created explicitly or promoted from a project discovery?
- How are shared decisions superseded without rewriting history?
- How is only relevant initiative context projected into each project?
- How is a new project bootstrapped as a peer rather than as a child of the source project?
- What coordination need remains unsolved when initiative knowledge exists?

