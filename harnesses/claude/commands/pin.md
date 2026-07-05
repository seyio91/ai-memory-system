Run `bash ~/.claude-memory/scripts/memory-pin.sh "$ARGUMENTS"` from the current repository (the script uses `git rev-parse --show-toplevel`, so the working directory must be inside the checkout you want to pin to project `$ARGUMENTS`).

The script writes both directions of the map in one action:
- **Forward** — `<repo-root>/.claude/memory-project` naming the project, so any session opened in that checkout auto-loads its context.
- **Reverse** — the project's `memory.md` frontmatter gets `repo` (the `origin` remote) and `repo_path` (the checkout path relative to `AI_MEMORY_PROJECTS_ROOT`).

Confirm the recorded `repo` and `repo_path` from the script's output. If it warned that the checkout is not under `AI_MEMORY_PROJECTS_ROOT` (so an absolute `repo_path` was stored), surface that to the user — they may want to set `AI_MEMORY_PROJECTS_ROOT` to match where their checkouts live.
