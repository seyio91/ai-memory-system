Scaffold a new plan file in the active project's `plans/` directory.

Argument: `$ARGUMENTS` — the plan name (kebab-case slug, no `.md` extension).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — guard against overwrite. If `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md` already exists, abort and tell the user the path exists — they should pick a different slug or edit the existing file.

Step 3 — write the file with this scaffold (today's date is in the `<memory:identity>` injection context — use it; do not invent):

```markdown
---
plan: $ARGUMENTS
status: draft
created: YYYY-MM-DD
owner: claude (orchestrator)
# task_provider / task_ref: written by the /start task-linking step when this plan
# is backed by a captured task (see README → Task-provider layer). Omit otherwise.
---

# Plan — <human-readable title>

## Goal
<one paragraph: what problem this plan solves>

## Success criteria
<the checkable conditions that define "done" for the WHOLE plan — each one a Validator could verify by reading output, running a command, or inspecting state. Required for plan-tier work (see orchestrator.md → Task Contract). If the user did not state criteria, draft best-effort ones from session context; never leave this blank. Per-phase criteria go on each phase's `**Verify:**` line, not here.>
- <criterion>

## Design
<for feature-tier plans this is populated by the brainstorming skill: the chosen approach (unit boundaries/interfaces, data flow, error handling) plus a one-line note per rejected alternative and why it lost — a lightweight decision record. For settled-shape plans (mechanical refactors, renames, migrations) that skipped brainstorming, a one-line statement of the known approach suffices.>
- <chosen approach>
- <alternative considered → why rejected>

## Decisions (locked)
- <bullet>

## Phases
### Phase 1 — <name>
- <step>

**Depends:** <the phases that must land before this one can start, e.g. `Phase 1` — or `none` when it is independent and safe to run in parallel. Mirror this onto the `todo.md` checkbox as `(needs: Pn)`.>
**Verify:** <the checkable condition for THIS phase alone — same bar as Success criteria: readable output, a runnable command, or inspectable state. If you cannot write one, the phase is too vague to delegate or is really two phases; redraw it (see orchestrator.md → Task Contract).>

## Risks / open questions
- <bullet>
```

Step 3.5 — decompose into phases. The scaffold gives you the section; this is how to fill it. A phase is **one executor delegation** — the unit you would hand to a single fresh agent with no memory of the others.

**Sizing.** Split a phase when any of these is true:
- it spans two independent subsystems (e.g. the hook layer and the task provider);
- its title needs an "and";
- its `**Verify:**` needs more than ~3 conditions to express;
- you cannot name the files it touches.

Merge a phase into its neighbour when it has no `**Verify:**` of its own — setup, scaffolding, and doc touch-ups belong to the phase whose deliverable needs them, not to phases of their own.

**Ordering.** Foundations first: a phase that changes a shape others build on (a scaffold, a schema, a contract) precedes its dependents. Put high-risk and high-unknown phases early — a plan that is going to fail should fail before five phases of work sit on top of it. Independent phases carry no `**Depends:**` and are explicitly parallelizable; say so in `## Decisions (locked)` so the orchestrator can fan them out.

**Checkpoints.** Insert a `### Checkpoint` before any phase the project cannot walk back:
- before a PR is opened or merged, and before any `terraform`/`kubectl` apply — the human/CI gates executors are forbidden to cross;
- before a phase that deletes or renames something other phases reference;
- after the last phase, as the pre-ship gate.

A checkpoint is a checklist, not a delegation — full test run, lint, a live exercise of anything prose-driven (no executable test covers a slash command), and human review. Mirror each phase into `todo.md` with its `(needs: Pn)` edge as you go.

Step 4 — ask the user one line: "Plan scaffolded at `<path>`. Want me to draft the Goal, Success criteria, and Phases from session context, or will you fill it in yourself?" Then act on the answer. If the user opts to fill it in, do not invent content — except **Success criteria**, where if the user proceeds to execution without stating them, draft best-effort criteria from context and surface them for confirmation (per orchestrator.md → Task Contract).

Step 5 — remind the user to add a checkbox item in `projects/<active>/todo.md` linking to the new plan (use the existing `### <topic> → [plan](plans/<name>.md)` pattern).
