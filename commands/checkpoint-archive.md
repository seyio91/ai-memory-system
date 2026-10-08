Snapshot the active project's `## Checkpoints` section into `archive/working/` and reset only that section.

Argument: `$ARGUMENTS` — optional one-line slug for the snapshot filename (kebab-case).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, abort and tell the user to pin the repo. Read the **working-file path** from the `working:` line of the `<memory:active>` breadcrumb, exactly like `/checkpoint`; it may be `working.<key>.md` for a worktree overlay. If the breadcrumb has no `working:` line, fall back to `~/.claude-memory/projects/<active>/working.md`.

Step 2 — read that working file and classify every `### ` entry under the fence-depth-0 `## Checkpoints` section from its **content**, never from a heading keyword (no writer emits a status marker, and `/checkpoint` forbids editing a prior entry, so a heading cannot be relied on to say an entry closed). Group entries by the work they track — the `**Task:**` line, else the plan, task or PR the heading names. Each entry is exactly one of:
- **superseded** — a later entry tracks the same work. Only the newest entry per piece of work can be in-flight.
- **closed** — the newest for its work, and it records the work as finished (merged/shipped and closed out: plan archived, task done, branch removed), with Next empty or pointing only at *new* work.
- **in-flight** — the newest for its work, and its Next or Blockers names an unfinished step *of that same work* (an unmerged PR, an unrun migration, a pending phase, an open close-out step).

Then collect the **open items**: every in-flight entry's unfinished step, plus any follow-up, carry-forward or blocker a non-superseded entry flags as still open (a closed entry can still carry one). For each open item, check whether it is already tracked outside `## Checkpoints` — an unchecked `todo.md` box, a backlog task, an initiative Target, or a `working.md` section the roll does not touch. If every open item is tracked elsewhere, the roll loses nothing: proceed without asking. Otherwise list each untracked open item with its entry and ask: "N open item(s) are tracked only in checkpoints. Roll anyway?" Do NOT proceed without explicit yes. When the user says yes, offer to carry the listed items into the fresh `## Checkpoints` section after Step 3.

Step 3 — run the script:
```
bash ~/.claude-memory/scripts/checkpoint-archive.sh <working-file> $ARGUMENTS
```

Step 4 — report back, three lines max:
- Snapshot path from the script output, or "nothing to roll" if the script no-oped.
- Checkpoint counts at roll time: total, superseded, closed, in-flight, and untracked open items.
- One-line summary of the rolled batch / slug.
