---
doc: worktree-overlay-key-subdir
kind: investigation
status: closed — fixed and merged (PR #86, 2026-07-20)
created: 2026-07-20
owner: seyi (reported); claude (review + fix)
---

> **Resolution (2026-07-20).** Fixed in PR #86. Two corrections to the analysis below, kept
> verbatim as filed: (1) the cause is the reverse of the hypothesis in "Likely cause" — at the
> repo root the bare `.git` is what makes it *work*; git returns `--git-dir` absolute but
> `--git-common-dir` relative from a subdirectory, so the equality test compared incomparable
> forms. (2) Scope is any subdirectory, any depth, any repo — not just this tree. Acceptance
> criterion 3 was retargeted from the file to the key: `working.md` may legitimately not exist
> yet, so the invariant is that a derived key is rejected unless well-formed. The two adjacent
> findings were verified but NOT fixed here — the dangling `~/.claude/hooks/*` symlinks (6, not
> 4; 5 of them name files gone from the tree entirely, so removal not repointing) and the
> cwd-based project-resolution question, which was filed as no-fix-requested.

# Bug: the `working:` breadcrumb points at a file that does not exist

The `<memory:active>` breadcrumb injected on every prompt advertises a working-memory
file that is not on disk. Any command that follows it verbatim writes to the wrong
place — silently, because the breadcrumb reads as authoritative.

## Observed

In a session whose cwd was inside the memory repo itself
(`/Users/seyi/Projects/claude/memory/projects/git-cli`), the injected breadcrumb was:

```
<memory:active project="ai-memory" cwd="/Users/seyi/Projects/claude/memory/projects/git-cli">
working: /Users/seyi/Projects/claude/memory/projects/ai-memory/working..git.md
```

Note the doubled dot in `working..git.md`. On disk, only `working.md` exists:

```
$ ls projects/ai-memory/working*
-rw-r--r--  25617  projects/ai-memory/working.md
```

So the overlay key resolved to the literal string `.git`, producing
`working.` + `.git` + `.md`.

## Why this matters

`/checkpoint` instructs the agent to *use the `working:` path verbatim* and explicitly
warns against hand-building `projects/<active>/working.md`, on the grounds that doing so
would clobber a concurrent session's file. Followed literally here, `/checkpoint` would
have created a brand-new `working..git.md` alongside the real one. The checkpoint would
appear to succeed. The real working file would never be updated, and nothing would
surface the divergence — the next session reads `working.md` and sees no checkpoint.

This is a fail-open path: the guard rail that exists to protect concurrent sessions is
what routes the write into a phantom file.

## Likely cause — please verify before fixing

The repo is **not** a linked worktree. It is the main worktree:

```
$ git -C /Users/seyi/Projects/claude/memory rev-parse --git-dir
.git
$ git -C /Users/seyi/Projects/claude/memory worktree list
~/Projects/claude/memory  76f3d14 [fix/promote-memory-section-scoped-reset]
```

`scripts/hooks/session_start_memory.sh:35` documents the intended behaviour:

> `inject.sh` — a session opened in a linked worktree must render `working.<wt>.md`.

The hypothesis is that the overlay branch fires in a **main** worktree too, and the key
derivation — which probably reads `rev-parse --git-dir` and expects an absolute
`…/.git/worktrees/<name>` path — gets the bare relative string `.git` in the main
worktree and uses it as the key. Confirm this rather than assuming it; the exact
derivation is in `scripts/hooks/inject.sh` (and possibly `memory_common.sh`).

## Scope of the fix

1. In a main worktree, the breadcrumb must name `working.md` — no overlay suffix.
2. In a linked worktree, it must name `working.<key>.md` with a non-empty, filesystem-safe key.
3. **A breadcrumb must never name a path that cannot be resolved.** If the derived path
   does not exist and cannot be created, that is a hook bug and should be loud, not a
   string handed to the model as fact. Consider having `inject.sh` stat the file it is
   about to advertise.

## Acceptance criteria

- From the main worktree, the `working:` line reads `…/projects/<active>/working.md`.
- From a linked worktree created with `git worktree add`, it reads
  `…/projects/<active>/working.<key>.md` with a sane key, and `/checkpoint` appends there.
- A regression test covers both. `scripts/tests/` is the existing home for these; the
  double-dot case (`working..*.md`) is worth asserting against by name, since it is the
  exact string that shipped.
- `scripts/check-docs.sh` still passes if any documented behaviour changes.

## Two adjacent findings, same session

**1. Stale hook symlinks from the `~/Downloads` move — dangling, currently inert.**

```
~/.claude/hooks/inject_memory.sh        -> /Users/seyi/Downloads/personal/claude/memory/... (DANGLING)
~/.claude/hooks/memory_common.sh        -> (DANGLING)
~/.claude/hooks/session_start_memory.sh -> (DANGLING)
~/.claude/hooks/block_task_tools.sh     -> (DANGLING)
...
```

The old tree is gone. These are **not** what runs today — `~/.claude/settings.json`
invokes `bash /Users/seyi/.claude-memory/scripts/hooks/inject.sh` with
`MEMORY_DIR=/Users/seyi/.claude-memory`, and `~/.claude-memory` correctly symlinks to
`/Users/seyi/Projects/claude/memory`. So the active path is healthy and this is leftover
cruft. It is still worth removing or repointing: a future `link-skills.sh`-style installer
or a manual `~/.claude/hooks/...` reference would resolve into a directory that no longer
exists, and the failure would look like a hook that silently does nothing. The project
memory's own path note (2026-07-18) listed `config.local.sh`, `index.md`, and `repo_path`
as move-time updates — the `~/.claude/hooks/` symlinks were missed and belong on that list.

**2. cwd-based project resolution diverges from session topic — by design, but worth a think.**

Resolution is working correctly: `/Users/seyi/Projects/git-cli/.agents/memory-project`
says `git-cli`, the memory repo's own marker says `ai-memory`, and cwd was in the latter.
But the *session* was entirely about git-cli — the only reason cwd had moved was that
earlier shell commands `cd`'d into the memory tree to edit that project's memory files.
So a session doing legitimate cross-repo work (change the code in repo A, record it in
repo B) has a breadcrumb that flips to B mid-session, and any memory write after that
point lands in the wrong project.

This is not obviously a bug — cwd is a reasonable signal — but the failure is silent and
the blast radius is another project's memory. Options worth weighing: pin the project at
session start and require an explicit `/pin` to change it; warn when the resolved project
changes mid-session; or resolve from the *first* prompt's cwd rather than each prompt's.
No fix requested here — flagging it because it is the same failure family as the bug
above: **the breadcrumb is treated as ground truth by every memory-writing command, so
anything it gets wrong is written silently.**

## Reproduction

```sh
cd /Users/seyi/Projects/claude/memory/projects/git-cli   # or any dir inside the memory repo
# start a session, then inspect the injected <memory:active> block
# expected: working: …/projects/ai-memory/working.md
# actual:   working: …/projects/ai-memory/working..git.md   (file does not exist)
```

## Note on how this surfaced

A `/checkpoint` invocation for a git-cli session was about to write into
`projects/ai-memory/working..git.md`. It was caught only because the agent noticed both
that the project was wrong for the session's content and that the filename looked
malformed. Neither check is guaranteed — the command's own instructions say to trust the
path verbatim. Treat "the agent happened to notice" as the thing to engineer away.
