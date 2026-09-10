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

### Step 2 — classify (the gate, per orchestrator.md → Brainstorm gate)
Classify the pulled `summary` (treat it as the initial request):
- **Feature with open design questions** (new functionality / subsystem / integration / real architecture decision) → **invoke the `design-brainstorm` skill** with `title` + `summary` as the seed. Run its full process (clarify → 2-3 approaches → sectioned design). Its output is the approved design.
- **Quick or settled-shape** (mechanical change, known target, small fix) → skip brainstorming; draft a one-line Goal and approach directly from the summary.

### Step 3 — scaffold the plan in the TASK's project
- Slug = kebab-case of the title (or reuse `<ref>`). Target path: `~/.claude-memory/projects/<task-project>/plans/<slug>.md`. If it already exists, abort and tell the user (pick another slug or edit it).
- Write the standard plan scaffold (same shape `/new-plan` produces): frontmatter `plan`, `status: in_progress` (**not** `active` — `lint-memory.sh` only accepts `draft`, `in_progress`, `done`, and every plan scaffolded with `active` is born lint-dirty), `created` (today, from the identity injection — do not invent), `owner: claude (orchestrator)`, **plus** `task_provider: <MEMORY_TASK_PROVIDER or "local">` and `task_ref: <ref>`. Record `<ref>` **verbatim and in full** (the backend's complete id — for Notion the full page UUID, never an 8-char abbreviation; short ids are ambiguous and rejected by the API). Body sections: `## Goal`, `## Success criteria`, `## Design`, `## Decisions (locked)`, `## Phases`, `## Risks / open questions`.
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
State: the plan path, that the task is linked (`task_ref`) and now `started`, and whether brainstorming ran. **If Step 4.5 entered a worktree,** name it and note the scratchpad is now `working.<slug>.md` (and that the branch was cut fresh from the default). If the design produced phases, offer to begin executing Phase 1 (the normal orchestrator/executor flow).

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
