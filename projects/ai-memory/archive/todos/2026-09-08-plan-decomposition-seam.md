# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Move root seed templates into `templates/` → [plan](archive/plans/move-root-templates.md)
- [x] Phase 1 — move the five files; `install.sh` seed paths, `_lib.sh:skill_manifest_template`, `.gitignore` negation + comments
- [x] Phase 2 — tests (`test_install_harness.sh`, `test_lib.sh`, `test_brainstorming_skill_tracking.sh`); mutation-check that fixtures exercise the new path
- [x] Phase 3 — docs (`install.md`, `file-formats.md`, `harnesses/claude.md`), changelog fragment, full suite, branch + PR

### Close the plan-decomposition seam in the Tier-3 pipeline → [plan](archive/plans/plan-decomposition-seam.md)
- [x] Phase 0 — refresh the plan against `main` (43 hits / 14 files re-measured; 2 new files found)
- [x] Phase 1 — per-phase criteria in the Task Contract (Task Contract is in `orchestrator.md`, not `identity.md`)
- [x] Phase 2 — decomposition rule as `/new-plan` Step 3.5
- [x] Phase 3 — declared dependency edges (+ `status: active` bug; 3 plans fixed, not 2)
- [x] Phase 4 — rename `brainstorming` → `design-brainstorm` (+ `.gitignore` negation; fixed a vacuous check-ignore control)
- [x] Phase 5 — record expand–contract sequencing (domain files are gitignored — local only)
- [x] Checkpoint — full test run + lint + live `/new-plan` exercise + human review
- [x] Phase 6 — changelog fragment + `git-cli ship` → PR #100, CI green, merged as `5e0f8ae`
- [x] Post-merge — `/plan-done`, `/plan-archive`, `taskctl set-status … done` (merged as #100; released as v1.5.0)

## Done
_(checked items stay above until the file is rolled)_
