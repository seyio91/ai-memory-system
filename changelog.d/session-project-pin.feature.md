- **The active project is now resolved once per session, not on every prompt.** `SessionStart` records the
  resolved project in `$MEMORY_STATE_DIR/<session_id>.project` and every later prompt honours it, so a session
  that `cd`s into another repository keeps writing memory to the project it is *about*. Previously resolution
  re-walked from `cwd` each prompt, so a shell command that changed directory silently repointed
  `/checkpoint`, `/promote-memory`, and every plan or todo edit at a different project's memory — with the
  breadcrumb reporting the new project as if it were correct.
- **`<memory:active>` gained two lines.** `session:` always (the hook's `session_id`, which `/pin` needs to
  repin a live session — the agent cannot learn it otherwise, since the hook stdin carrying it is consumed by
  a separate process), and `pinned:` only when `cwd` resolves to a different project than the one in force,
  so a deliberate `cd` is explained rather than silently ignored.
- **`/pin` and `memory-pin.sh` take `--session <id>`**, rewriting the live session's pin alongside the marker
  and reverse map. Without it the marker is still written, but the running session keeps its project until
  restart — `/pin` now says so explicitly instead of appearing to work.
- **Executors and subagents keep resolving from their own `cwd`, by design.** That is what makes cross-project
  delegation work. The pin is a session-keyed *file* rather than an environment variable precisely because env
  inherits into child processes: an exported project would follow an executor into a sibling repo and resolve
  the orchestrator's project there — worse than the bug being fixed, and a live defect in the antigravity
  harness today, tracked separately.
- Every failure path degrades to the previous behaviour rather than corrupting: no `session_id`, no pin file,
  a pin naming a deleted or renamed project, or an unwritable state directory all fall back to the `cwd` walk.
  Pins are swept after `AI_MEMORY_PIN_RETAIN_DAYS` (default 7) — deliberately longer than the `.recompact`
  sweep, because a sentinel is consumed on the next prompt while a pin must outlive a multi-day session.
