- **`/plan-archive` now moves the plan's linked investigation too.** It resolves the
  investigation by the plan's frontmatter `task_ref` first, falling back to a same-slug
  filename match, and moves it from `investigations/` to `archive/investigations/` in the
  same invocation. A destination collision aborts only the investigation move (reported,
  not silent) and never blocks the plan's own archival.
- **`lint-memory` gains rule 10: stale investigation detection.** A live
  `investigations/<slug>.md` whose `task_ref` matches a plan already in `archive/plans/`
  now warns — the work shipped and the investigation was left behind. The check is
  purely local frontmatter comparison and never calls the task provider.
