# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Harden the executor deny-list → [plan](plans/deny-list-hardening.md)
- [ ] Phase 1 — `scripts/deny-match.sh`: tokenized + adjacency matchers, `sh -c` recursion
- [ ] Phase 2 — `json_parser_available()`; `pretooluse.sh` fails closed for guarded roles
- [ ] Phase 3 — specs + `helm uninstall`/`delete`; gitignored `deny-list.local.txt` overlay
- [ ] Phase 4 — tests: allow/deny table, fail-closed, overlay, dirty-tracked guard
- [ ] Phase 5 — docs: antigravity.md §Enforcement, deny-list header, CHANGELOG (Fixed)

### Task summary: hard 500-char gate, long-form by name → [plan](plans/task-summary-gate.md)
- [x] Phase 1 — contract gate: `SUMMARY_MAX_CHARS`, `validate_summary()`, wrap `capture`/`update`
- [x] Phase 2 — CLI surface: verify non-zero exit + JSON `{"error": ...}`
- [x] Phase 3 — tests: offline reject (local + notion), `update(title=)` unaffected, 500/501 boundary, legacy read
- [x] Phase 3b — wire the python suite into run-tests.sh; `check-provider-tests.sh` + pairing test
- [x] Phase 4 — docs: task-provider.md gate section + narrowed invariant, `/task` + `/start`, CHANGELOG

### Configurable cross-model Validator role → [plan](plans/cross-model-validator.md)
- [x] Phase 1 — executor.sh: `validate` role (no legacy chaining; exec_readonly path)
- [x] Phase 2 — Antigravity guard: widen read-only gate to explore|validate
- [x] Phase 3 — tests: test_executor.sh + test_antigravity.sh
- [x] Phase 4 — docs + doctrine: identity.md, workflow.md, config.local.sh.example, memory.md, system-overview.md, scripts.md, showcase.md, CLAUDE.md

## Done
_(checked items stay above until the file is rolled)_
