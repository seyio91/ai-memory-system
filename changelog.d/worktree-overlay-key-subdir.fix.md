- **The `working:` breadcrumb no longer advertises a file that does not exist.** From any subdirectory of a
  main checkout — at any depth, in any repo — `resolve_session_key` reported a linked worktree and keyed the
  scratchpad on the literal string `.git`, so the per-prompt breadcrumb named
  `projects/<project>/working..git.md`. Nothing on disk matched. `/checkpoint` is instructed to use that path
  *verbatim* and explicitly warned against hand-building `working.md`, so following it would have created a
  phantom file, reported success, and left the real working memory untouched — the guard rail that exists to
  protect concurrent sessions was what routed the write into nowhere.
- **Cause: two `git rev-parse` forms were compared in different shapes.** git returns `--git-dir` absolute
  from a subdirectory but `--git-common-dir` relative, with a depth-dependent prefix (`../.git`,
  `../../.git`). They only compared equal at the repo root, so every other cwd looked like a linked worktree.
  Both are now resolved to real absolute paths before comparison, which also makes a repo reached through a
  symlink compare equal to the same repo reached directly.
- **A derived worktree key is now validated, and rejected rather than coerced.** Empty, dot-leading, or
  separator-bearing keys fall back to the shared `working.md`; a wrong-but-well-formed key is harder to
  notice than no key at all. The check deliberately does not reuse the marker sanitizer, which lowercases —
  that would have silently moved an existing `working.wt-featureB.md` to `working.wt-featureb.md`.
