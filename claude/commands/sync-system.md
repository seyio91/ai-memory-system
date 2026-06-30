Pull the latest memory-system from the remote and reinstall every feature it ships (hooks, slash commands, skills, agents, statusline).

Use this after the remote has new commits — a plain `git pull` updates the repo files, but new commands/skills/agents only become visible to the harness once they are symlinked into `~/.claude/`. This command does both.

Argument: `$ARGUMENTS` — optional flags forwarded to the script:
- `--dry-run` — show the incoming commits and the changed-file stat, then stop without pulling or installing.
- `--no-pull` — skip the fetch/pull; just relink features from the current tree (use after a manual edit to the store).

Step 1 — run:
```
bash ~/.claude-memory/scripts/sync-system.sh $ARGUMENTS
```
Capture stdout and the exit code. The script does a `--ff-only` pull (it aborts, rather than merging, if the local branch has diverged) and then re-runs the idempotent `install.sh`, which relinks hooks, commands, skills, agents, and the statusline.

Step 2 — report concisely:
- If "already up to date": say so in one line and stop.
- If it pulled: summarize the incoming commits (the script prints the `git log --oneline` range) and name any **new** slash commands / skills / agents that got linked (lines like `link: <name>` in the install output). These are the freshly available features.
- If it aborted on divergence: surface the abort message — the user has local commits or a dirty tree and must resolve by hand. Do not attempt to merge or rebase.

Step 3 — if any new slash command was linked, remind the user once: slash commands load at session start, so they must restart or reconnect the session to see it.

Do not edit files from this command — it is pull-and-relink only.
