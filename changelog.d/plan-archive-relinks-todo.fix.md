- **`/plan-archive` now relinks the live `todo.md`.** Moving a plan to `archive/plans/` left every
  `todo.md` reference pointing at a file that no longer existed, and nothing caught it — the command
  read `todo.md` only to count unchecked boxes, and `lint-memory` checks that `plans/` exists as
  scaffold but never validates link targets. The dangling link then survived until the next
  `/todo-archive` roll, which can be weeks. A new Step 7b rewrites `plans/<slug>.md` to
  `archive/plans/<slug>.md` in the live file only. Snapshots under `archive/todos/` are deliberately
  left alone: they record what `todo.md` said the day it was rolled, so editing one to reflect a later
  move would falsify an audit record — a dangling link there is correct.
