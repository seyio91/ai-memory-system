# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Project categories (client grouping) for state + billing → [plan](plans/project-categories-billing.md)
_Design approved 2026-07-02 (task 391f6850, started). Category = frontmatter (gitignored values); billing = plans created in window. Each phase gates on `run-tests.sh` green._
- [ ] Phase 1 — category field + lint (template placeholder, lint accepts-when-present, test)
- [ ] Phase 2 — category-aware /state (category column + grouping + `/state <category>` filter)
- [ ] Phase 3 — /billing (regenerate-billing.sh + command; plans/+archive/ created-in-window; gitignore output; tests)
- [ ] Phase 4 — personal-data audit (no client name in tracked files) + docs

### Make memory engine harness-agnostic → [plan](plans/make-memory-engine-harness-agnostic.md)
_Design approved 2026-07-02. Behavior-preserving refactors (P1–2) before new capability (P3–5); each phase gates on `run-tests.sh` green._
- [ ] Phase 1 — content core extraction (content-core.sh + xml/md formatters; rewire Claude+Codex; golden tests)
- [ ] Phase 2 — layout restructure (`claude/`→`harnesses/claude/`, Codex→`harnesses/codex/`; fix MEMORY_DIR depth; .gitignore/install paths)
- [ ] Phase 3 — manifest + archetype drivers (hook/file) + `install.sh` engine (`--harness` + auto-detect)
- [ ] Phase 4 — skills fan-out (manifest `skills_dir`) + commands surface (native/doc/none)
- [ ] Phase 5 — prove new harness (Gemini/Cursor) + agent-runnable install from Codex; docs + reverse no-bootstrap non-goal

## Done
_(checked items stay above until the file is rolled)_
