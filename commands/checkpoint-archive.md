Snapshot the active project's `## Checkpoints` section into `archive/working/` and reset only that section.

Argument: `$ARGUMENTS` — optional one-line slug for the snapshot filename (kebab-case).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, abort and tell the user to pin the repo. Read the **working-file path** from the `working:` line of the `<memory:active>` breadcrumb, exactly like `/checkpoint`; it may be `working.<key>.md` for a worktree overlay. If the breadcrumb has no `working:` line, fall back to `~/.claude-memory/projects/<active>/working.md`.

Step 2 — read that working file. Under the fence-depth-0 `## Checkpoints` section, count `### ` entries. Any `### ` heading whose text contains neither `CLOSED` nor `DONE` looks in-flight. If one or more are in-flight, ask explicitly: "N checkpoint(s) look in-flight. Roll anyway?" Do NOT proceed without explicit yes.

Step 3 — run the script:
```
bash ~/.claude-memory/scripts/checkpoint-archive.sh <working-file> $ARGUMENTS
```

Step 4 — report back, three lines max:
- Snapshot path from the script output, or "nothing to roll" if the script no-oped.
- Checkpoint counts at roll time: total entries and in-flight entries.
- One-line summary of the rolled batch / slug.
