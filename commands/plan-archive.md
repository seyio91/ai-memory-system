Move a completed plan from `plans/` to `archive/plans/` in the active project, and its linked
investigation (if any) from `investigations/` to `archive/investigations/` in the same step.

Argument: `$ARGUMENTS` — the plan slug (filename without `.md` extension).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — verify the plan exists at `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md`. If not, abort with the path and a hint to check `ls plans/`.

Step 3 — sanity check the plan's status. Read the file's frontmatter — note its `task_ref` value too (empty if absent); it is needed for Step 5. If `status:` is not `done`, `complete`, or `closed`, ask the user explicitly: "Plan status is `<current>`, not `done`. Archive anyway?" Don't proceed without a yes.

Step 4 — sanity check the todo. Grep `~/.claude-memory/projects/<active>/todo.md` for references to the plan (`plans/$ARGUMENTS.md`). If any unchecked checkboxes are in the same section, surface them to the user and ask: "Plan has N open todos referencing it. Archive anyway?" Don't proceed without a yes.

Step 5 — resolve the linked investigation, if any. There is no index to consult — check candidates directly:
- If `~/.claude-memory/projects/<active>/investigations/` doesn't exist, or is empty, there is nothing to
  resolve — skip Step 6 and continue at Step 7 (the plan is still archived), reporting "no investigation
  linked" in Step 8.
- **`task_ref` match first.** If the plan's frontmatter carried a non-empty `task_ref` (from Step 3), read
  the frontmatter of every file in `~/.claude-memory/projects/<active>/investigations/*.md` and look for
  one whose own `task_ref` field equals the plan's. At most one should match; if you find one, that file
  is the resolved investigation — go to Step 6.
- **Same-slug fallback.** If the plan had no `task_ref`, or no investigation's `task_ref` matched it, check
  whether `~/.claude-memory/projects/<active>/investigations/$ARGUMENTS.md` exists (same filename as the
  plan). If it does, that file is the resolved investigation — go to Step 6.
- If neither step resolves a file, there is no linked investigation — skip Step 6 and continue at Step 7
  (the plan is still archived), reporting "no investigation linked" in Step 8 (no error, no noise beyond
  that one line).

Step 6 — move the resolved investigation, handling a destination collision:
- Let `<inv-file>` be the resolved file's name (e.g. `$ARGUMENTS.md`, or a different name if resolved by
  `task_ref`).
- If `~/.claude-memory/projects/<active>/archive/investigations/<inv-file>` **already exists**, do NOT
  move the investigation and do NOT overwrite anything. Remember this as a collision to report in Step 8.
  This never blocks the plan's own archival — continue to Step 7 regardless.
- Otherwise, create the destination directory if needed and move the file:
  ```
  mkdir -p ~/.claude-memory/projects/<active>/archive/investigations
  mv ~/.claude-memory/projects/<active>/investigations/<inv-file> \
     ~/.claude-memory/projects/<active>/archive/investigations/<inv-file>
  ```
  Remember source and destination to report in Step 8.

Step 7 — move the plan file:
```
mv ~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md \
   ~/.claude-memory/projects/<active>/archive/plans/$ARGUMENTS.md
```

Step 8 — report back:
- The plan's source → destination paths.
- The investigation outcome, exactly one of:
  - source → destination paths, if one was moved;
  - which file was found and why it was left in place, if a destination collision blocked the move
    (name the existing `archive/investigations/<inv-file>`);
  - "no investigation linked," if Step 5 resolved nothing.
- A reminder that the archive is not read on future sessions unless the user explicitly asks.
