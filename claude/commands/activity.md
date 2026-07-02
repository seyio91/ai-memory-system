Show the **activity report** — the plans *created* within a time window, grouped by category (client/group). Useful for reviewing or invoicing a client's work over a period.

The unit is a **plan** (each carries `created:` frontmatter), not a completed task — so this is independent of the task backend. Both live plans and archived plans are counted (a plan created this window may already be done). This is an **on-demand, personal** view: the output artifact is gitignored and never auto-injected.

Parse `$ARGUMENTS`: the first bare word is a **category**; `--all` covers every category; `--since <N>` or `--since <N>d` sets the window (default 30 days). Require either a category or `--all`.

Step 1 — regenerate and print the report:
```
# one category, default 30-day window:
bash ~/.claude-memory/scripts/regenerate-activity.sh "<category>" --stdout
# a custom window:
bash ~/.claude-memory/scripts/regenerate-activity.sh "<category>" --since 90d --stdout
# every category:
bash ~/.claude-memory/scripts/regenerate-activity.sh --all --stdout
```
`--stdout` prints without writing the file. Drop it to also refresh `~/.claude-memory/activity.md` on disk (a gitignored personal artifact).

Step 2 — present the report as-is. It is grouped under a `## <category>` heading per client (uncategorized last), each a table of `Project | Plan | Created | Status`, newest first, with a per-section and total plan count. If the window is empty it says so.

Step 3 — if the user is invoicing or reviewing a specific client, lead with that category's section and its count; otherwise show the report and stop. Do not load any project's `memory.md` to answer — the report is already derived.
