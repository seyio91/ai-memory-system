Scaffold a new plan file in the active project's `plans/` directory.

Argument: `$ARGUMENTS` — the plan name (kebab-case slug, no `.md` extension), plus an optional `--task <ref>` or `--no-task` token. Parse those out of `$ARGUMENTS`; the remaining token is the slug. The two flags are mutually exclusive — both given is a usage error, abort. They govern the Task linking section at the end; absent, that section asks.

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — guard against overwrite. If `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md` already exists, abort and tell the user the path exists — they should pick a different slug or edit the existing file.

Step 3 — write the file with this scaffold (today's date is in the `<memory:identity>` injection context — use it; do not invent):

```markdown
---
plan: $ARGUMENTS
status: draft
created: YYYY-MM-DD
owner: claude (orchestrator)
# task_provider / task_ref: written by the Task linking step (Step 5 here, or /start).
# Never leave task_ref absent — a linked plan carries the full ref, a deliberately
# plan-only one carries `task_ref: none`. An absent field is what lint rule 12 flags.
---

# Plan — <human-readable title>

## Goal
<one paragraph: what problem this plan solves>

## Success criteria
<the checkable conditions that define "done" for the WHOLE plan — each one a Validator could verify by reading output, running a command, or inspecting state. Required for plan-tier work (see orchestrator.md → Task Contract). If the user did not state criteria, draft best-effort ones from session context; never leave this blank. Per-phase criteria go on each phase's `**Verify:**` line, not here.>
- <criterion>

## Design
<for feature-tier plans this is populated by the `design-brainstorm` skill: the chosen approach (unit boundaries/interfaces, data flow, error handling) plus a one-line note per rejected alternative and why it lost — a lightweight decision record. For settled-shape plans (mechanical refactors, renames, migrations) that skipped brainstorming, a one-line statement of the known approach suffices.>
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

Step 5 — run the **Task linking** section below, in full. It resolves the task (from `--task`/`--no-task`, or by asking), stamps the frontmatter, pushes the Goal back to the backend, flips the task to `started`, and writes the `todo.md` entry. It runs *after* Step 4 and not before: the summary pushed to the backend must be the drafted Goal, not the scaffold placeholder.

A note on scope, since `/new-plan` targets the **active** project: a `--task <ref>` whose task belongs to a different project is a mismatch, not a cross-project feature. Abort and name `/start <ref>`, which places the plan in the task's own project.

<!-- partial:task-link START (managed by scripts/apply-partial.sh — edit scripts/partials/task-link.md) -->
## Task linking

Bind this plan to a task in the provider backlog. `TASKCTL="$HOME/.claude-memory/scripts/taskctl"` (JSON to stdout, errors via exit code). Run it with Bash. On any non-zero exit, surface the JSON `error` verbatim and stop **before** writing frontmatter — a half-linked plan is worse than an unlinked one.

**Step L1 — resolve the ref.** Use the first of these that applies:
- The caller already holds a ref (`/start` pulled one) → use it.
- `--task <ref>` was passed → `"$TASKCTL" get <ref>` to confirm it exists. If the task's `project` differs from the plan's project, abort and name `/start <ref>` as the route — that command places the plan in the task's own project.
- `--no-task` was passed → skip to Step L2 with `none`.
- Neither flag → ask once: *"Backed by a task? paste a `<ref>` / capture one now / plan-only."* On *capture one now*, run `"$TASKCTL" capture <project> "<title>" "<Goal>"` and use the returned ref.

Record the ref **verbatim and in full** — the backend's complete id, never an abbreviated prefix. Short ids are ambiguous and the Notion backend rejects them.

**Step L2 — frontmatter.** Ensure the plan carries `task_provider: <MEMORY_TASK_PROVIDER or "local">` and `task_ref: <ref>`, and that `status:` is `in_progress`. Write `task_ref: none` for the plan-only case — an explicit marker, not an absent field, so a deliberate choice is distinguishable from an omission. This step is idempotent: when the caller already stamped these at scaffold time, leave them as they are.

**For `task_ref: none`, skip L3 and L4** — no backend calls, no status flip — and go straight to L5. Plan-only work is still plan-tier work: it gets its `todo.md` entry like any other, because `todo.md` tracks plan execution regardless of whether a task backs the plan.

**Step L3 — push the Goal back.** `"$TASKCTL" update <ref> --summary "<the plan's Goal>"`. The summary is **capped at 500 characters** and an over-cap update hard-fails. Keep the Goal to one or two sentences; if the design needs more room it belongs in the plan, and long-form pre-plan material belongs in `projects/<project>/investigations/<slug>.md`, referenced **by name, never by path** — a path rots the moment the plan is archived, and the task already carries its `project`. If the drafted Goal exceeds the cap, push a condensed one-sentence version; never truncate mid-word.

**Step L4 — flip the lifecycle.** `"$TASKCTL" set-status <ref> started`.

**Step L5 — mirror into `todo.md`.** Append to `projects/<project>/todo.md` under `## Active`:

```
### <title> → [plan](plans/<slug>.md)
- [ ] P1 — <phase name>
- [ ] P2 — <phase name> (needs: P1)
```

One checkbox per phase. **Mirror each phase's `**Depends:**` line onto its checkbox as `(needs: Pn)`** — `todo.md` is what gets read on resume and after compaction, so a dependency living only in the plan is invisible at exactly the moment it matters. Independent phases carry no annotation, which is how the orchestrator spots what can be fanned out in parallel.
<!-- partial:task-link END -->
