# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### skills.toml recurse field → [plan](plans/skill-recurse-field.md)
- [x] Phase 1 — schema + parser: `_manifest_tsv` emits `recurse`/`prefix`/`exclude`; `name` optional when recurse; loops don't skip nameless recurse rows (validated PASS)
- [x] Phase 2 — resolver recurse branch: find-walk (prune-on-match) + exclude globs + identity (frontmatter/basename+prefix) + per-skill cache copy (validated PASS)
- [x] Phase 3 — lockfile expanded set + 6th `origin` column; plain resolve replays as cache-hits (validated PASS — offline replay 70ms, zero fetch)
- [x] Phase 4 — `--update`-only prune (origin-keyed) + `--dry-run` preview; collision hard-error (validated PASS — 9 criteria + dry-run accuracy + no temp leak)
- [x] Phase 5 — `--list`/`--dry-run` recurse output; fixture-repo test suite (a–f) (validated PASS — test_skill_recurse.sh 41/0, shellcheck clean; runner green modulo env-only locale artifact in test_executor.sh)

## Done
_(checked items stay above until the file is rolled)_
