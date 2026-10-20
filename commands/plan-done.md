Mark a plan complete by setting its frontmatter `status:` to `done` and stamping a `completed:` date.

Argument: `$ARGUMENTS` — the plan slug (filename without `.md` extension).

Step 1 — resolve the active project from the injected memory context: the `<memory:active project="...">` breadcrumb (present every prompt) or the `<memory:project name="...">` block. If neither is present, no project is pinned to this repo — abort and tell the user to pin it (`/pin <project>` from inside the repo, or add `.agents/memory-project`).

Step 2 — locate the plan at `~/.claude-memory/projects/<active>/plans/$ARGUMENTS.md`. If missing, abort with the path and a hint to check `ls plans/`.

Step 3 — read the frontmatter. Capture the current `status:` value. If it's already `done`, tell the user and stop — don't re-stamp `completed:`.

Step 4 — edit the frontmatter:
- Replace `status: <current>` with `status: done`.
- If there's no `completed:` line, insert one immediately after `status:` with today's date (from the `<memory:identity>` injection context — do not invent). Use the format `completed: YYYY-MM-DD`.
- If `completed:` already exists, leave it untouched (preserve the original completion date).
- Leave every other frontmatter field exactly as-is.

Step 5 — sanity check the todo. Grep `~/.claude-memory/projects/<active>/todo.md` for unchecked checkboxes in the section that references `plans/$ARGUMENTS.md`. If any are still open, mention them to the user as a heads-up — but don't block; this command only flips the status, archival is a separate step.

Step 5b — resolve the initiative's open decision proposals. Read the plan's `task_ref:` (from Step 3's frontmatter). If it is absent or `none`, skip this step silently. Otherwise run `grep -l -- '- task: <task_ref>' ~/.claude-memory/initiatives/*.md` with the exact full ref (never a prefix), keeping only files with `kind: initiative` and `status: active`. No match → skip silently. On a match, run `bash ~/.claude-memory/scripts/initiative-status.sh <slug> --list-proposed` (slug = the file's basename without `.md`) — each proposed entry in full (head and continuation lines, blank-line separated), legacy included, not only ones from this plan (entries carry no Target link). Non-zero exit → report its stderr to the user and stop; never treat a failure as "no proposals". Exit 0 with no output → skip silently. Otherwise put each one to the user (one `AskUserQuestion` question per entry, ≤4 per call; without the tool, a numbered list) with the entry text and four answers, so it resolves in one round:
- **Confirm** → the user names the artifact that absorbed it (merged PR, shipped doc, doctrine line) in the answer itself. Set the status to `confirmed <today>` (replacing the entry's date, never adding a second), delete the `  unconfirmed:` line if present (a confirmed entry never keeps it), and record the artifact: append `; absorbed by <artifact>` to an existing `evidence:` line, else add `  evidence: <artifact>`. With `AskUserQuestion`, the Confirm option's description must say "type the artifact as your own (Other) answer"; a typed artifact = Confirm, Confirm selected without text = **Agreed, no artifact**.
- **Agreed, no artifact** → the entry stays `proposed`; update or add `unconfirmed:` to say it is agreed and what artifact would clear it.
- **Reject** → set the status to `rejected <today>` (replacing the entry's date, never adding a second) and delete the `  unconfirmed:` line if present. The entry stays in the stream.
- **Leave** → no change.
Edit only the status and date on the entry line and its `evidence:`/`unconfirmed:` lines; never edit an entry's decision text. Never decide on the user's behalf.

Step 6 — report back, three lines max (four if Step 5b resolved proposals):
- File path edited.
- Status transition (e.g. `in-progress → done`, `completed: 2026-05-19 stamped`).
- Proposals resolved, if Step 5b ran: `<initiative>: D<n> confirmed, D<m> rejected, D<k> left` (agreed-without-artifact counts as left).
- A one-line nudge: "Run `/plan-archive $ARGUMENTS` when you're ready to move it to `archive/plans/`."
