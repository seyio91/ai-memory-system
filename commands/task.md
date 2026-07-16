Capture and manage tasks in the task-provider backlog from inside Claude. Thin wrapper over `scripts/taskctl` (the local task-provider CLI). Tasks are the thin intent record — capturing one does NOT create a plan, todo, or index row; that happens later at `/start`.

Argument: `$ARGUMENTS` — `[verb] [@project] [rest...]`.

**Binary:** `TASKCTL="$HOME/.claude-memory/scripts/taskctl"`. It prints JSON to stdout and signals errors via exit code. Run it with the Bash tool; parse the JSON; report a short human line (don't dump raw JSON unless the user asks).

**Resolve the project (do this first):**
- Default = the active project from the injected `<memory:active project="...">` breadcrumb (present every prompt).
- Override = a leading `@<project>` token anywhere in `$ARGUMENTS` (strip it from the rest).
- If a project-needing verb has neither an active project nor `@project` → abort and tell the user to pin the repo (`/pin <project>`) or pass `@<project>`.

**Parse the verb** (first token). If the first token is not one of `add|list|done|archive|show`, treat the whole argument string as an **`add`** (so `/task Rotate tokens — reseal secret` works). Then:

- **`add <title> — <summary>`** — split title/summary on the first ` — ` (em dash), ` - ` (spaced hyphen), or ` | `. If no separator, the whole string is the title and the summary is empty. Run:
  `"$TASKCTL" capture <project> "<title>" "<summary>"` → report `captured <ref> (project: <project>)`.
  **`summary` is capped at 500 chars** (enforced by the provider contract — an over-cap capture fails). It is a thin record of *intent*, not a design. If the task needs a long design, write it to `projects/<project>/investigations/<slug>.md` and make the summary a one-or-two-sentence goal that names the investigation — `` design: `<slug>` `` — **by name, not by path**. Paths move when work is archived; the task already carries its `project`, so the slug is unambiguous.
- **`list [<status>]`** — default shows the project's open work: run `"$TASKCTL" list <project> backlog` and `"$TASKCTL" list <project> started`, then present a compact table (ref · status · title). If a `<status>` arg is given (`backlog|started|done|archived`), list just that one.
- **`show <ref>`** — `"$TASKCTL" get <ref>` → print project, status, title, summary, created.
- **`done <ref>`** — `"$TASKCTL" set-status <ref> done` → confirm.
- **`archive <ref>`** — `"$TASKCTL" set-status <ref> archived` → confirm (file moves to `archive/tasks/`).

**Notes**
- `ref`s are globally unique slugs in the flat store, so `show/done/archive` work regardless of the active project.
- To begin actual work on a captured task (plan + brainstorm), use `/start <ref>` — `/task` never creates a plan.
- On any non-zero exit, surface the JSON `error` message to the user verbatim and stop.
