Show the open threads in the active project — what's unfinished, waiting, or next ("what's the open thread?"). Read-only: never edit any file.

Step 1 — resolve the active project from the `<memory:active project="...">` breadcrumb. If absent, abort and tell the user to pin one (`/pin <project>` from inside the repo). Take the working file from the breadcrumb's `working:` line verbatim (it may be a worktree overlay) and `todo.md` from the directory of its `project:` line. Read the `repo_path` from the project's `memory.md` frontmatter (`$MEMORY_DIR` means the memory root).

Step 2 — gather four sources. Skip any that is missing or empty; never read `archive/`.
- **Last checkpoint** — the newest (bottom) `###` entry under `## Checkpoints` in the working file: its date + title, `**Next:**`, `**Blockers:**`, `**Resume:**`.
- **Open threads** — bullets under `## Open threads` in the working file, excluding any whose text starts with `CLOSED` or `CONCLUDED`. Reduce each to its bold lead or first sentence.
- **Unticked todos** — `- [ ]` lines in `todo.md`, grouped under their `###` heading.
- **Open PRs** — from `repo_path`: GitHub remote → `gh pr list --state open --author @me --json number,title,headRefName,isDraft,reviewDecision`; Bitbucket remote → `bkt pr list`. If the CLI fails, show `PRs: unavailable (<reason>)` — do not retry.

Step 3 — cross-check before printing: a checkpoint `Next` item that an open PR, a ticked todo, or a later commit (`git -C <repo_path> log --oneline -10`) shows as done is stale — drop it and note `(stale: <evidence>)` once at the end rather than listing it as open.

Step 4 — print one compact block, nothing else:

```
## Open threads — <project>

Last checkpoint: <date> — <title>
Next:      <bullets>
Blockers:  <bullets or none>
Resume:    <line>

PRs:       #<n> <title> [<branch>] <draft|review state>
Todos:     <heading>: <n> open — <first unticked item>
Threads:   - <one line each>
```

Omit a section with nothing in it. If the user asked a focused question ("what's blocked?", "anything waiting on me?"), answer that from the gathered sources instead of printing the whole block. Do not load sibling projects' memory — `/state` is the cross-project view.
