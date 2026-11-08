Scaffold a new plan file in the active project's `plans/` directory.

Argument: `$ARGUMENTS` — the plan name (kebab-case slug, no `.md` extension), plus an optional `--task <ref>` or `--no-task` token. Parse those out of `$ARGUMENTS`; the remaining token is the slug. The two flags are mutually exclusive — both given is a usage error, abort. They govern the Task linking section at the end; absent, that section asks.

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — guard against overwrite. If `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md` already exists, abort and tell the user the path exists — they should pick a different slug or edit the existing file.

Step 3 — write the file at `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md` using the scaffold in the **Plan scaffold** section below, with `plan: $ARGUMENTS`, `status: draft`, and today's date for `created` (it is in the `<memory:identity>` injection context — use it; do not invent).

Step 3.5 — decompose into phases. The scaffold gives you the section; this is how to fill it. A phase is **one executor delegation** — the unit you would hand to a single fresh agent with no memory of the others.

**Sizing.** Split a phase when any of these is true:
- it spans two independent subsystems (e.g. the hook layer and the task provider);
- its title needs an "and";
- its `**Verify:**` needs more than ~3 conditions to express;
- you cannot name the files it touches.

Merge a phase into its neighbour when it has no `**Verify:**` of its own — setup, scaffolding, and doc touch-ups belong to the phase whose deliverable needs them, not to phases of their own.

**Ordering.** Foundations first: a phase that changes a shape others build on (a scaffold, a schema, a contract) precedes its dependents. Put high-risk and high-unknown phases early — a plan that is going to fail should fail before five phases of work sit on top of it. Independent phases carry `**Depends:** none` and are explicitly parallelizable; say so in `## Decisions (locked)` so the orchestrator can fan them out.

**Checkpoints.** Insert a `### Checkpoint` before any phase the project cannot walk back:
- before a PR is opened or merged, and before any `terraform`/`kubectl` apply — the human/CI gates executors are forbidden to cross;
- before a phase that deletes or renames something other phases reference;
- after the last phase, as the pre-ship gate.

A checkpoint is a checklist, not a delegation — full test run, lint, a live exercise of anything prose-driven (no executable test covers a slash command), and human review. Mirror each phase into `todo.md` with its `(needs: Pn)` edge as you go.

**Pushback.** A plan names what it must prove and nothing more. When you catch yourself reaching for extra scope, check it against these before writing it in:

| Rationalization | Reality |
|---|---|
| "It's cheap to add while I'm in there" | Every phase is a delegation, a validation round and a review. Cheap to write is not cheap to ship; it goes under `## Non-goals` or a follow-up task. |
| "We'll need it eventually" | Eventually has no criterion. If nothing in `## Success criteria` fails without it, cut it. |
| "A generic version covers future cases" | Build for the stated cases; a second caller is the signal to generalize. |
| "The criterion is obvious, no need to write it" | An unwritten criterion cannot be verified, only asserted. Write it as an `R<n>` line or drop the work. |
| "Verify can just say it works" | `Verify` names the R-ids it proves and a command or state a validator can read. |

**YAGNI pushback.** When the user's ask, or your own draft, grows a phase no `R<n>` needs, say so and offer the cut instead of silently accepting it. Bad example: Goal "stop the nightly sync from double-posting", then a Phase 3 "add a pluggable retry-strategy interface" with no criterion behind it. The pushback: "R1 is the only criterion and Phase 1 already satisfies it; Phase 3 proves nothing. Move it to `## Non-goals`, or tell me which `R<n>` it serves."

Step 4 — ask the user one line: "Plan scaffolded at `<path>`. Want me to draft the Goal, Success criteria, and Phases from session context, or will you fill it in yourself?" Then act on the answer. Once the Phases are drafted, run the **Plan feasibility** section below before Step 5. If the user opts to fill it in, do not invent content — except **Success criteria**, where if the user proceeds to execution without stating them, draft best-effort criteria from context and surface them for confirmation (per doctrine/orchestrator.md → Task Contract).

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

<!-- partial:plan-scaffold START (managed by scripts/apply-partial.sh — edit scripts/partials/plan-scaffold.md) -->
## Plan scaffold

The plan body, written once here and carried by `/new-plan` and `/start`. Fill the placeholders; the angle-bracket prose is guidance, not content. `/new-plan` writes `status: draft`, `/start` writes `status: in_progress`. Lint rule 20 reads this shape for plans created on or after 2026-11-08 — see `docs/file-formats.md` → Plan body.

```markdown
---
plan: <slug>
status: draft
created: YYYY-MM-DD
owner: claude (orchestrator)
# task_provider / task_ref: written by the Task linking step (Step 5 in /new-plan, Step 4 in /start).
# Never leave task_ref absent — a linked plan carries the full ref, a deliberately
# plan-only one carries `task_ref: none`. An absent field is what lint rule 12 flags.
---

# Plan — <human-readable title>

## Goal
<one paragraph: what problem this plan solves>

**Before:** <the observable state today — what is broken or missing>
**After:** <the observable state when the plan is done; the final validator pass reads this line>

## Non-goals
- <what this plan deliberately does not do>

## Success criteria
<the checkable conditions that define "done" for the WHOLE plan — each one a Validator could verify by reading output, running a command, or inspecting state. Required for plan-tier work (see doctrine/orchestrator.md → Task Contract). If the user did not state criteria, draft best-effort ones from session context; never leave this blank. One line per criterion, `R<n>` ids in order, each tagged. Per-phase checks go on each phase's `**Verify:**` line, which cites the R-ids it proves.>
- R1 [acceptance] <a condition proven by running a command or inspecting state>
- R2 [parity] <behaviour that must not change> — vs `<git-ref>` <tolerance, e.g. modulo `updated:`>
- R3 [parity] <output that must stay identical> — baseline `plans/<slug>.baseline/<path>` <tolerance>

<`[parity]` criteria name a re-runnable reference: ``vs `<git-ref>` `` (re-run the check at that ref and compare) or ``baseline `plans/<slug>.baseline/<path>` `` (a snapshot kept on disk beside the plan; it requires a `### Phase N — Baseline` that captures it). Delete the parity lines when nothing must stay unchanged.>

## Design
<for feature-tier plans this is populated by the `design-brainstorm` skill: the chosen approach (unit boundaries/interfaces, data flow, error handling) plus a one-line note per rejected alternative and why it lost — a lightweight decision record. For settled-shape plans (mechanical refactors, renames, migrations) that skipped brainstorming, a one-line statement of the known approach suffices.>
- <chosen approach>
- <alternative considered → why rejected>

**Builds on:** <existing code, commands, issues or plans this reuses — references only, never a dependency declaration>

## Security
<required when any phase is `Risk: high`: the threat the change introduces or exposes and how the plan contains it. Otherwise delete this section.>

## Decisions (locked)
- <bullet>

## Phases
### Phase 1 — <name>
- <step>

**Files touched:** `<repo-relative/path>`, `<dir/glob/*>`, `<path/the/phase/creates>` (new)
**Risk:** low | medium | high
**Depends:** none | Phase N[, Phase N…]
**Verify:** R1[, R2…] — <the checkable condition for THIS phase alone: readable output, a runnable command, or inspectable state; a phase that introduces a cache, lock, pool, background worker, deduplicated or in-flight work, or external process must also state concurrency, cancellation, timeout and failure-caching behaviour (see docs/workflow.md → Task Contract → "Shared state needs behaviour criteria").>

## Risks / open questions
- <bullet>
```

Field rules, one field per line: `Files touched` is comma-separated backticked paths or globs, repo-relative, with a file the phase creates suffixed ` (new)` after its closing backtick. `Depends` takes phase numbers only, never names — mirror it onto the `todo.md` checkbox as `(needs: Pn)`. `Verify` is a single line whose R-ids come before the em dash. Only `### Phase N — ` headings are phases; a `### Checkpoint` is not.
<!-- partial:plan-scaffold END -->

<!-- partial:plan-feasibility START (managed by scripts/apply-partial.sh — edit scripts/partials/plan-feasibility.md) -->
## Plan feasibility

A pre-delegation gate: run it once the plan's Phases are drafted, before offering or delegating Phase 1. It checks the plan against the repo **at a base commit**, never the working tree. Not for plans still carrying scaffold placeholders — the brief answers `REVISE: not drafted` for those.

1. Take `base`: the main SHA recorded in the plan's `## Decisions` (record it there before Phase 1 if absent), else `git merge-base origin/<default> HEAD` in the plan's repo. Pass the same `base:` on every later run.
2. Run the brief, in the plan's repo, with the plan path, repo path and `base:` in the prompt: `bash scripts/executor.sh --role validate --run --brief plan-feasibility "<plan path, repo path, base: <sha>>"`, or the Agent tool with subagent type `plan-feasibility`. Exit 3 with `EXECUTOR_USE_SUBAGENT` means use the Agent tool.
3. Act on the verdict (first line of the report):
   - `READY` — proceed.
   - `CAUTION` — proceed, and copy each finding into the plan's `## Risks / open questions`.
   - `REVISE` — fix the plan for each finding and re-run **once**. A second `REVISE` goes to the user; do not delegate Phase 1.
<!-- partial:plan-feasibility END -->
