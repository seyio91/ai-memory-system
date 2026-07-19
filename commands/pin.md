Run `bash ~/.claude-memory/scripts/memory-pin.sh "$ARGUMENTS" --session <id>` from the current repository (the script uses `git rev-parse --show-toplevel`, so the working directory must be inside the checkout you want to pin to project `$ARGUMENTS`).

**Read `<id>` from the `session:` line of the `<memory:active>` breadcrumb** in this prompt's injected context, and pass it verbatim. This is required for the pin to take effect *now*: the active project is fixed once at `SessionStart` and held for the whole session, so writing only the on-disk marker would leave this session pointed at the old project until it restarts — silently, since the marker would look correctly written.

If the breadcrumb has **no** `session:` line (an older session, or a harness that supplies no session id), run the command without `--session` and tell the user plainly that the marker is written but this session keeps its current project until restarted.

The script writes both directions of the map in one action, plus the live-session pin when `--session` is given:
- **Forward** — `<repo-root>/.agents/memory-project` naming the project, so any session opened in that checkout auto-loads its context (readers still fall back to the legacy `.claude/memory-project`).
- **Reverse** — the project's `memory.md` frontmatter gets `repo` (the `origin` remote) and `repo_path` (the checkout path relative to `AI_MEMORY_PROJECTS_ROOT`).

- **Live session** — with `--session <id>`, `.sessions/<id>.project` is rewritten so the very next prompt resolves to the new project. Confirm the script printed `session: <id> (live session repinned)`; if it did not, the session was not repinned.

Confirm the recorded `repo` and `repo_path` from the script's output. If it warned that the checkout is not under `AI_MEMORY_PROJECTS_ROOT` (so an absolute `repo_path` was stored), surface that to the user — they may want to set `AI_MEMORY_PROJECTS_ROOT` to match where their checkouts live.
