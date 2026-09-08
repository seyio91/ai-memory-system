# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Move root seed templates into `templates/` → [plan](archive/plans/move-root-templates.md)
- [x] Phase 1 — move the five files; `install.sh` seed paths, `_lib.sh:skill_manifest_template`, `.gitignore` negation + comments
- [x] Phase 2 — tests (`test_install_harness.sh`, `test_lib.sh`, `test_brainstorming_skill_tracking.sh`); mutation-check that fixtures exercise the new path
- [x] Phase 3 — docs (`install.md`, `file-formats.md`, `harnesses/claude.md`), changelog fragment, full suite, branch + PR

### Close the plan-decomposition seam in the Tier-3 pipeline → [plan](plans/plan-decomposition-seam.md)
- [ ] Phase 0 — refresh the plan against `main` (5 files drifted since `v1.4.0`)
- [ ] Phase 1 — per-phase criteria in the Task Contract  (needs: P0)
- [ ] Phase 2 — decomposition rule as `/new-plan` Step 3.5  (needs: P1)
- [ ] Phase 3 — declared dependency edges  (needs: P1)
- [ ] Phase 4 — rename `brainstorming` → `design-brainstorm`  (needs: P0)
- [ ] Phase 5 — record expand–contract sequencing
- [ ] Checkpoint — full test run + lint + live `/new-plan` exercise + human review  (needs: P1,P2,P3,P4,P5)
- [ ] Phase 6 — changelog fragment + `git-cli ship` (no merge)  (needs: checkpoint)

## Done
_(checked items stay above until the file is rolled)_
