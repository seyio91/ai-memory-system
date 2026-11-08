Begin work on a captured task: pull it from the backlog, run the design gate (brainstorm for feature-with-open-design, else straight to plan), create the linked plan in the task's own project, push the refined summary back, and flip the task to `started`. This is the `/start` half of the task-provider ↔ design-brainstorm integration.

Argument: `$ARGUMENTS` — a task `<ref>` (optional), plus an optional `--worktree` / `--no-worktree` flag. Parse a `--worktree` or `--no-worktree` token out of `$ARGUMENTS`; the remaining token is the `<ref>`. The flag governs Step 4.5 (feature-isolation worktree); absent, Step 4.5 asks.

**Binary:** `TASKCTL="$HOME/.claude-memory/scripts/taskctl"` (JSON to stdout, errors via exit code). Run with Bash.

### Step 0 — pick the task
- If `$ARGUMENTS` is empty: resolve the active project from the injected `<memory:active project="...">` breadcrumb, run `"$TASKCTL" list <active> backlog`, present the backlog (ref · title), and ask the user which `ref` to start. Stop until you have one.
- Otherwise the argument is the `<ref>`.

### Step 1 — pull the task (project-agnostic)
- Run `"$TASKCTL" get <ref>`. On non-zero exit, surface the JSON `error` and stop.
- Read `project`, `title`, `summary`, `status` from the result. **The task's `project` may differ from the active project — always use the task's own `project` from here on** (refs are globally unique in the flat store, so you can start a task from any session).
- If `status` is not `backlog`, warn the user it is already `<status>` and confirm before continuing.

### Step 1.5 — is this task part of an initiative?
- After Step 1 resolved the ref, run `grep -l -- '- task: <ref>' ~/.claude-memory/initiatives/*.md`, substituting the exact full ref — never a prefix. A short Notion UUID silently fails to match.
- No hit: say nothing; most tasks are not initiative-backed, and a message every time is noise. Continue to Step 2.
- One hit: read the initiative file. Report its slug, the Target id (the `### <project>/<slug>` heading containing the task), its `execution_mode`, and its `depends_on` line. Then run `bash ~/.claude-memory/scripts/initiative-status.sh <slug>` and quote that Target's row: derived stage and whether its dependencies are satisfied. Select the row by **anchoring on the id column** — `grep '^| <target-id> |'` — never by searching for the id anywhere in the output: Targets cite each other in their evidence and `next_actor` prose, so a bare match returns several rows and the first one belongs to a different Target (measured: 5 matches vs 1 anchored). If a dependency is unsatisfied, stop and ask the user before planning work that cannot land.
- Read the initiative's `## Decision stream` before Step 2's design gate: a recorded cross-repo decision can constrain the design. Any new cross-repo decision settled while planning belongs there as the next `D<n> proposed <today>` entry (with an `unconfirmed:` line) at decision time, not at handover.
- This step is **read-only**: never edit the initiative file. The Target names the task; the plan is found by matching `task_ref`, so nothing on the Target changes when work starts.
- More than one matching initiative must not happen (lint rule 15a forbids it). Report every match and stop.

### Step 2 — classify (the gate, per doctrine/orchestrator.md → Brainstorm gate)
Classify the pulled `summary` (treat it as the initial request):
- **Feature with open design questions** (new functionality / subsystem / integration / real architecture decision) → **invoke the `design-brainstorm` skill** with `title` + `summary` as the seed. Run its full process (clarify → 2-3 approaches → sectioned design). Its output is the approved design.
- **Quick or settled-shape** (mechanical change, known target, small fix) → skip brainstorming; draft a one-line Goal and approach directly from the summary.

### Step 3 — scaffold the plan in the TASK's project
- Slug = kebab-case of the title (or reuse `<ref>`). Target path: `~/.claude-memory/projects/<task-project>/plans/<slug>.md`. If it already exists, abort and tell the user (pick another slug or edit it).
- Write the plan from the **Plan scaffold** section below (the one scaffold `/new-plan` also uses) at that path, with `plan: <slug>`, `status: in_progress` (**not** `active` — `lint-memory.sh` only accepts `draft`, `in_progress`, `done`, and every plan scaffolded with `active` is born lint-dirty), `created` (today, from the identity injection — do not invent), `owner: claude (orchestrator)`, **plus** `task_provider: <MEMORY_TASK_PROVIDER or "local">` and `task_ref: <ref>`. Record `<ref>` **verbatim and in full** (the backend's complete id — for Notion the full page UUID, never an 8-char abbreviation; short ids are ambiguous and rejected by the API).
- Fold the approved design in: `## Goal` ← the clarified one-or-two-sentence purpose; `## Success criteria` ← criteria derived with the user; `## Design` ← chosen approach + one-line note per rejected alternative; `## Risks` ← deferred items. (For settled/quick tasks: Goal from the summary, a one-line Design, best-effort Success criteria.) Leave `## Phases` for the normal decomposition step.

### Step 4 — link, push back, flip status
Run the **Task linking** section below, in full, against the task's own project. You already hold the `<ref>` from Step 1, so its Step L1 resolves immediately and Step L2 finds the frontmatter Step 3 already stamped — both are written to be idempotent. Steps L3-L5 do the real work here: push the clarified Goal back as the refined summary, flip the task to `started`, and write the `todo.md` entry.

### Step 4.5 — enter a feature-isolation worktree (optional, Claude-only)
Applies **only when Step 2 classified the task as a Tier-3 feature** (brainstorm ran). Skip entirely for quick/settled tasks — they don't warrant an isolated checkout.

- **Decide whether to enter a worktree:** `--worktree` → yes; `--no-worktree` → skip; neither → ask the user once ("Start this feature in a fresh git worktree so it doesn't collide with other in-progress work? [y/N]"). Default no.
- **Guards — check before entering, and skip (do not error) if any holds:**
  - Already in a worktree session this session → skip and say so ("already in a worktree — not nesting; the current one isolates this work").
  - Not in a git repository and no `WorktreeCreate` hook configured → skip and note the flow needs one.
- **Enter:** call the `EnterWorktree` tool with `name=<slug>` (the plan slug from Step 3, truncated to 64 chars — it is already kebab-case, inside the allowed charset). This switches the session's working directory into `.claude/worktrees/<slug>` on a fresh branch.
- **Why last:** Steps 0-4 wrote the plan/todo into the memory tree (`~/.claude-memory`, an absolute path unaffected by the code-repo cwd) and did the backend bookkeeping from the main checkout. Entering now means only the *execution* runs in the worktree. The per-session scratchpad then auto-resolves to `working.<slug>.md` (the overlay resolver keys off the worktree — no extra wiring; see `docs/file-formats.md` → Per-worktree overlays). `worktree.baseRef` defaults to `fresh` (branches from `origin/<default>`), so the worktree does **not** carry uncommitted local work — mention this when you report.

### Step 5 — report
State: the plan path, that the task is linked (`task_ref`) and now `started`, and whether brainstorming ran. **If Step 4.5 entered a worktree,** name it and note the scratchpad is now `working.<slug>.md` (and that the branch was cut fresh from the default). If the design produced phases, run the **Plan feasibility** section below first, then offer to begin executing Phase 1 (the normal orchestrator/executor flow).

**Notes**
- `/start` owns plan placement (into the task's project) rather than calling `/new-plan`, because `/new-plan` targets the *active* project and a task can belong to a different one. A same-project `/start` and a direct `/new-plan` still yield the same plan shape.
- Nothing in the task backend is materialized into the memory tree until this command runs — `/start` is where a captured intent becomes real plan + todo.

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
