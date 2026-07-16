Move a completed plan from `plans/` to `archive/plans/` in the active project.

Argument: `$ARGUMENTS` — the plan slug (filename without `.md` extension).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — verify the plan exists at `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md`. If not, abort with the path and a hint to check `ls plans/`.

Step 3 — sanity check the plan's status. Read the file's frontmatter. If `status:` is not `done`, `complete`, or `closed`, ask the user explicitly: "Plan status is `<current>`, not `done`. Archive anyway?" Don't proceed without a yes.

Step 4 — sanity check the todo. Grep `~/.claude-memory/projects/<active>/todo.md` for references to the plan (`plans/$ARGUMENTS.md`). If any unchecked checkboxes are in the same section, surface them to the user and ask: "Plan has N open todos referencing it. Archive anyway?" Don't proceed without a yes.

Step 5 — move the file:
```
mv ~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md \
   ~/.claude-memory/projects/<active>/archive/plans/$ARGUMENTS.md
```

Step 6 — report back, two lines:
- Source → destination paths.
- A reminder that the archive is not read on future sessions unless the user explicitly asks.
