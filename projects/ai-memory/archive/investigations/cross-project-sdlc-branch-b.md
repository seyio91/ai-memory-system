---
kind: investigation
slug: cross-project-sdlc-branch-b
status: concluded — ideation branch folded into the shipped initiative layer
created: 2026-08-14
task_ref: 3bcf6850-c619-8111-b3b5-ed0e6497569d
---

# Cross-project SDLC ideation — Branch B

Imported from the user-provided artifact **Branch B — Result and Conclusion for Review Agent**.
This record preserves the branch as an independent hypothesis; it is not an approved design.

## Hypothesis

Keep project memory unchanged and add a small coordination layer holding durable shared
work state.

```text
Work         cross-project objective
Target       one project's responsibility within the Work
Update       typed information emitted by a Target
Dependency   ordering between Targets
```

The boundary is **share state, not context**. Project conversations, `working.md`, plans,
test output, and agent traces do not enter the coordination layer.

## Proposed state

A Target may carry status, dependencies, `next_actor`, and an `execution_mode` such as
`interactive`, `software_adw`, `runbook`, or `automated`. A Software ADW attaches to a
Target, never to the whole Work item. Human approval is normal workflow state rather than
an interruption.

Updates may be typed as decision, handoff, question, blocker, information, completion, or
contract change. Dependencies differ from handoffs: a handoff says another project needs
new information; a dependency says another Target cannot proceed yet.

## Strength

Makes cross-project readiness, blocking, ownership, and human gates inspectable without
loading sibling project memories. Deterministic software can evaluate dependencies and
state transitions while agents remain responsible for judgment.

## Risk

The model can become a second task manager or workflow engine. Treating an architectural
revision as only a typed Update can also lose the richer specification, rationale, and
supersession history needed by future project agents.

## Review questions carried forward

- Is `Work -> Target -> Update` sufficient, or are Decision and Contract first-class?
- Can a Target depend on a human decision as well as another Target?
- Is `next_actor` enough, or is an explicit gate required?
- Who may create Targets and declare a Work item complete?
- How does a project query only its relevant unresolved state?
- What is the smallest validation model before introducing a service or workflow engine?
- Which parts duplicate the current task provider, plans, todos, and plan-set execution?

