Roll the active project's superseded and closed `## Checkpoints` entries into `archive/working/`, keeping in-flight entries in place.

Argument: `$ARGUMENTS` — optional one-line slug for the snapshot filename (kebab-case).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, abort and tell the user to pin the repo. Read the **working-file path** from the `working:` line of the `<memory:active>` breadcrumb, exactly like `/checkpoint`; it may be `working.<key>.md` for a worktree overlay. If the breadcrumb has no `working:` line, fall back to `~/.claude-memory/projects/<active>/working.md`.

Step 2 — list the entries with the script, which owns entry numbering and fence handling:
```
bash ~/.claude-memory/scripts/checkpoint-archive.sh --list <working-file>
```
It prints one `<n><TAB><### heading>` line per entry in file order. Exit 2 means the section is missing or the file is malformed (a duplicate `## Checkpoints`, or a code fence left open): report the stderr message and stop. Empty output means nothing to roll: report that and stop.

Step 3 — read the working file and classify every listed entry from its **content**, never from a heading keyword (no writer emits a status marker, and `/checkpoint` rewrites a living entry in place — its heading keeps the start date and its Done gains dated groups — so a heading says nothing about closure, and the newest entry for a piece of work is the bottom-most one naming it). Group entries by the work they track — the `**Task:**` line, else the plan, task or PR the heading names; two entries naming different plan slugs are different work even when they share a task or PR. Each entry is exactly one of:
- **superseded** — a later entry tracks the same work. Only the newest entry per piece of work can be in-flight. Under the living-entry rule, superseded arises only for entries written before it (one per session) or a legacy entry whose work a living entry continued.
- **closed** — the newest for its work, and it records the work as finished (merged/shipped and closed out: plan archived, task done, branch removed), with Next empty or pointing only at *new* work.
- **in-flight** — the newest for its work, and its Next or Blockers names an unfinished step *of that same work* (an unmerged PR, an unrun migration, a pending phase, an open close-out step).

In-flight entries are **kept**: they stay in `## Checkpoints` untouched. Superseded and closed entries are rolled to `archive/working/`.

Then collect the open items on the **rolled** entries: any follow-up, carry-forward or blocker a superseded or closed entry still flags as open. For each, check whether it is tracked elsewhere — an unchecked `todo.md` box, a backlog task, an initiative Target, a kept in-flight entry, a later entry that records it done, or a `working.md` section the roll does not touch. If every open item is tracked, proceed without asking. Otherwise list each untracked item with its entry and ask: "N open item(s) on rolled checkpoints are tracked nowhere else. Roll anyway?" Do NOT proceed without explicit yes.

Step 4 — if you asked the user in Step 3, re-run `--list` first; if its output differs from Step 2's, another session changed the file: stop, report it, and start again from Step 2. Then run the script, passing one `--keep <n>` per in-flight entry, numbered from Step 2's list. Options go **before** the working file:
```
bash ~/.claude-memory/scripts/checkpoint-archive.sh --keep <n> [--keep <n> ...] <working-file> $ARGUMENTS
```
With no in-flight entries, omit `--keep` and the whole section rolls. If every entry is in-flight the script reports nothing to roll and writes nothing. An invalid `--keep` exits 2 without writing: report it and stop, never retry without the keep.

Step 5 — report back, three lines max:
- Snapshot path from the script output, or "nothing to roll" if the script no-oped.
- Checkpoint counts at roll time: total, rolled (superseded + closed), kept (in-flight), and untracked open items.
- One-line summary of the rolled batch / slug.
