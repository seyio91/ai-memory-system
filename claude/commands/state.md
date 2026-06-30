Show the derived cross-project "In Flight" snapshot — what's active across all projects ("what's on my plate?").

This is an **on-demand** view (a projection like the index, never auto-injected into the session). Every column is derived from existing sources, so it cannot drift from them.

Step 1 — regenerate and print the freshly-derived table:
```
bash ~/.claude-memory/scripts/regenerate-state.sh --stdout
```
`--stdout` prints without writing the file. Drop it to also refresh `~/.claude-memory/state.md` on disk (a gitignored personal artifact).

Step 2 — present the table to the user as-is. It is already compact: one row per project — `project | last touched | current goal | open todos`, newest first. `_template` is excluded; a project with no `## Current Goal` shows `—`; open-todo count is the unchecked-box count from each `todo.md`.

Step 3 — if the user asked a focusing question ("what's blocked?", "what did I touch this week?", "where are the open todos?"), highlight the relevant rows rather than restating the whole table. Otherwise just show it and stop.

Do NOT load any sibling project's `memory.md` to answer — this view exists precisely so you can see *that* work is in flight without pulling it into context (delegate-don't-load). If the user wants to act on a row, switch to that project (`/pin` from its repo) or delegate.
