- **`/new-plan` no longer skips the task lifecycle.** It takes `--task <ref>` or
  `--no-task` and otherwise asks once, then runs the same linking step as
  `/start` — both commands now share one injected `task-link` partial rather
  than separate copies. `apply-partial.sh` gained a `--file` target mode to
  carry it. A new lint rule flags a live plan with no `task_ref`; `task_ref: none`
  is the explicit marker for deliberately plan-only work.
