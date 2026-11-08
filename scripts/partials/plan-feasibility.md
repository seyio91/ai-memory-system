## Plan feasibility

A pre-delegation gate: run it once the plan's Phases are drafted, before offering or delegating Phase 1. It checks the plan against the repo **at a base commit**, never the working tree. Not for plans still carrying scaffold placeholders — the brief answers `REVISE: not drafted` for those.

1. Take `base`: the main SHA recorded in the plan's `## Decisions` (record it there before Phase 1 if absent), else `git merge-base origin/<default> HEAD` in the plan's repo. Pass the same `base:` on every later run.
2. Run the brief, in the plan's repo, with the plan path, repo path and `base:` in the prompt: `bash scripts/executor.sh --role validate --run --brief plan-feasibility "<plan path, repo path, base: <sha>>"`, or the Agent tool with subagent type `plan-feasibility`. Exit 3 with `EXECUTOR_USE_SUBAGENT` means use the Agent tool.
3. Act on the verdict (first line of the report):
   - `READY` — proceed.
   - `CAUTION` — proceed, and copy each finding into the plan's `## Risks / open questions`.
   - `REVISE` — fix the plan for each finding and re-run **once**. A second `REVISE` goes to the user; do not delegate Phase 1.
