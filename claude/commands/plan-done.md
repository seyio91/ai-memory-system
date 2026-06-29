Mark a plan complete by setting its frontmatter `status:` to `done` and stamping a `completed:` date.

Argument: `$ARGUMENTS` — the plan slug (filename without `.md` extension).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.claude/memory-project`).

Step 2 — locate the plan at `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md`. If missing, abort with the path and a hint to check `ls plans/`.

Step 3 — read the frontmatter. Capture the current `status:` value. If it's already `done`, tell the user and stop — don't re-stamp `completed:`.

Step 4 — edit the frontmatter:
- Replace `status: <current>` with `status: done`.
- If there's no `completed:` line, insert one immediately after `status:` with today's date (from the `<memory:identity>` injection context — do not invent). Use the format `completed: YYYY-MM-DD`.
- If `completed:` already exists, leave it untouched (preserve the original completion date).
- Leave every other frontmatter field exactly as-is.

Step 5 — sanity check the todo. Grep `~/.claude-memory/projects/<active>/todo.md` for unchecked checkboxes in the section that references `plans/$ARGUMENTS.md`. If any are still open, mention them to the user as a heads-up — but don't block; this command only flips the status, archival is a separate step.

Step 6 — report back, three lines max:
- File path edited.
- Status transition (e.g. `in-progress → done`, `completed: 2026-05-19 stamped`).
- A one-line nudge: "Run `/plan-archive $ARGUMENTS` when you're ready to move it to `archive/plans/`."
