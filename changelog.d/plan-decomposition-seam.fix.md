- **`/start` scaffolded every plan with an invalid `status: active`.** `lint-memory.sh` accepts
  only `draft`, `in_progress`, `done`, so each plan the command created was born lint-dirty. Step 3
  now writes `status: in_progress`, and the three plans already carrying the bad value are fixed.
- **The skill-tracking test could never fail.** It asserted the bundled skill is not gitignored
  via `git check-ignore`, which short-circuits on *tracked* paths and returns "not ignored"
  without consulting `.gitignore` at all. Since the file is always tracked, the assertion passed
  for free — deleting the `!/skills/…` negation outright did not fail it. Now uses
  `--no-index` so the ignore rules are actually evaluated, and is mutation-tested in both
  directions.
- **Three stale cross-references to `identity.md` corrected.** The Task Contract and the
  Brainstorm gate both live in `orchestrator.md`, but `commands/new-plan.md` cited
  `identity.md → Task Contract` twice and `commands/start.md` cited
  `identity.md → Brainstorm gate` once. `docs/workflow.md` already had it right.
- **`projects/ai-memory/memory.md` listed the design-brainstorm skill as a remote skill** sourced
  from the `agent-skills` repo, contradicting `skills.toml`, which records it as authored and
  in-engine since #74.
