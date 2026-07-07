Begin work on a captured task: pull it from the backlog, run the design gate (brainstorm for feature-with-open-design, else straight to plan), create the linked plan in the task's own project, push the refined summary back, and flip the task to `started`. This is the `/start` half of the task-provider ↔ brainstorming integration.

Argument: `$ARGUMENTS` — a task `<ref>` (optional).

**Binary:** `TASKCTL="$HOME/.claude-memory/scripts/taskctl"` (JSON to stdout, errors via exit code). Run with Bash.

### Step 0 — pick the task
- If `$ARGUMENTS` is empty: resolve the active project from the injected `<memory:active project="...">` breadcrumb, run `"$TASKCTL" list <active> backlog`, present the backlog (ref · title), and ask the user which `ref` to start. Stop until you have one.
- Otherwise the argument is the `<ref>`.

### Step 1 — pull the task (project-agnostic)
- Run `"$TASKCTL" get <ref>`. On non-zero exit, surface the JSON `error` and stop.
- Read `project`, `title`, `summary`, `status` from the result. **The task's `project` may differ from the active project — always use the task's own `project` from here on** (refs are globally unique in the flat store, so you can start a task from any session).
- If `status` is not `backlog`, warn the user it is already `<status>` and confirm before continuing.

### Step 2 — classify (the gate, per identity.md → Brainstorm gate)
Classify the pulled `summary` (treat it as the initial request):
- **Feature with open design questions** (new functionality / subsystem / integration / real architecture decision) → **invoke the `brainstorming` skill** with `title` + `summary` as the seed. Run its full process (clarify → 2-3 approaches → sectioned design). Its output is the approved design.
- **Quick or settled-shape** (mechanical change, known target, small fix) → skip brainstorming; draft a one-line Goal and approach directly from the summary.

### Step 3 — scaffold the plan in the TASK's project
- Slug = kebab-case of the title (or reuse `<ref>`). Target path: `~/.claude-memory/projects/<task-project>/plans/<slug>.md`. If it already exists, abort and tell the user (pick another slug or edit it).
- Write the standard plan scaffold (same shape `/new-plan` produces): frontmatter `plan`, `status: active`, `created` (today, from the identity injection — do not invent), `owner: claude (orchestrator)`, **plus** `task_provider: <MEMORY_TASK_PROVIDER or "local">` and `task_ref: <ref>`. Record `<ref>` **verbatim and in full** (the backend's complete id — for Notion the full page UUID, never an 8-char abbreviation; short ids are ambiguous and rejected by the API). Body sections: `## Goal`, `## Success criteria`, `## Design`, `## Decisions (locked)`, `## Phases`, `## Risks / open questions`.
- Fold the approved design in: `## Goal` ← the clarified one-or-two-sentence purpose; `## Success criteria` ← criteria derived with the user; `## Design` ← chosen approach + one-line note per rejected alternative; `## Risks` ← deferred items. (For settled/quick tasks: Goal from the summary, a one-line Design, best-effort Success criteria.) Leave `## Phases` for the normal decomposition step.

### Step 4 — link, push back, flip status
- Push the clarified Goal back to the backend as the refined summary: `"$TASKCTL" update <ref> --summary "<the clarified Goal text>"`.
- Flip the lifecycle: `"$TASKCTL" set-status <ref> started`.
- Add a todo item in the task's project: append `### <title> → [plan](plans/<slug>.md)` with unchecked Phase boxes to `projects/<task-project>/todo.md` (under `## Active`).

### Step 5 — report
State: the plan path, that the task is linked (`task_ref`) and now `started`, and whether brainstorming ran. If the design produced phases, offer to begin executing Phase 1 (the normal orchestrator/executor flow).

**Notes**
- `/start` owns plan placement (into the task's project) rather than calling `/new-plan`, because `/new-plan` targets the *active* project and a task can belong to a different one. A same-project `/start` and a direct `/new-plan` still yield the same plan shape.
- Nothing in the task backend is materialized into the memory tree until this command runs — `/start` is where a captured intent becomes real plan + todo.
