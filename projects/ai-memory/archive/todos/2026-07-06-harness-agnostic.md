# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### ✅ Project categories (client grouping) for state + activity → [plan](archive/plans/project-categories-activity.md)
_**Shipped 2026-07-02** — PRs #12–#15; task 391f6850 done; plan archived. Category = frontmatter (gitignored values); activity report = plans created in window._
- [x] Phase 1 — category field, setter (`/pin --category`, `/new-project` prompt, hand-edit) + lint _(suite 20/20 green)_
- [x] Phase 2 — category-aware /state (category column + grouping + `/state <category>` filter) _(state test 36/36, suite 20/20)_
- [x] Phase 3 — /activity (regenerate-activity.sh + command; plans/+archive/ created-in-window; gitignore output; tests) _(activity test 30/30, suite 21/21)_
- [x] Phase 4 — personal-data audit (no client name in tracked files) + docs _(audit clean; suite 21/21)_

### Make memory engine harness-agnostic → [plan](plans/make-memory-engine-harness-agnostic.md)
_Design approved 2026-07-02. Behavior-preserving refactors (P1–2) before new capability (P3–5); each phase gates on `run-tests.sh` green._
- [x] Phase 1 — content core extraction (content-core.sh + xml/md formatters; rewire Claude+Codex; golden tests) _(byte-identical verified; suite 22/22)_
- [x] Phase 2 — layout restructure (`claude/`→`harnesses/claude/`, Codex→`harnesses/codex/scripts/`; MEMORY_DIR depth `../../..`; install/link/executor/test paths) _(suite 22/22; live install repointed + verified)_
- [x] Phase 3 — manifest + archetype drivers (hook/file) + `install.sh` engine (`--harness` + auto-detect) _(byte-identical claude repro; suite 24/24)_
- [x] Phase 4 — skills fan-out (manifest `skills_dir`, gate lifted) + commands surface (native/skill/doc/none; command-skills for Codex) _(suite 25/25; claude byte-identical)_
- [x] Phase 5 — registered **Antigravity** (deliver face proven; execute face declared → runtime in P7); shared `build-context-md.sh` (codex golden intact); docs + non-goal reversal _(suite 26/26; Cursor deferred)_
- [x] Phase 6 — de-brand project marker `.claude/memory-project` → `.agents/memory-project` (readers+writer+lint back-compat; `migrate-marker.sh`) _(suite 27/27; run `--apply` post-merge on 14 checkouts)_
- [x] Phase 7 — executor roles (`task`/`exploration`) + `harness[:model]` config via manifest `exec_*`; codex special-case deleted; Codex + Antigravity executor faces live _(executor 37; suite 27/27)_

## Done
_(checked items stay above until the file is rolled)_
