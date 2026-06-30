# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

POS adoption — triage + rationale in `wikis/pos-adoption-backlog.md` (all 13 items have a verdict).

### Skill subsystem → [plan](plans/skill-subsystem.md)
- [x] Phase 1 — `metadata.tier` schema across all skills + docs (#10) — 12/12 classified, validator PASS
- [x] Phase 2 — `scripts/validate-skills.sh` + tests (#4) — 19-assertion test, wired into run-tests, validator PASS
- [x] Phase 3 — boundary check (#11): engine + Claude PostToolUse/Stop hooks; 2 validators (FAIL→fixed→PASS); 35 assertions. Codex trigger deferred (decision); live-wiring is user's step.
- [x] Phase 4 — skill creator (`new-skill.sh`) + installer/intake (`install-skill.sh`) (#12, #13); 47-assertion test; validator FAIL→fixed→PASS
- [x] Phase 5 — self-rating block + minimal partials (#6, #5): `apply-partial.sh` (marker-derived membership) + `skill-ratings.sh` + `partials/self-rating.md`; creator integration; applied to the four; 32-assertion test

### Derived state snapshot → [plan](plans/state-snapshot.md)
- [ ] Phase 1 — derivation sources + script-vs-flag decision (#8)
- [ ] Phase 2 — generator + dependency-free test
- [ ] Phase 3 — on-demand wire-up + README note

### Quick wins (inline, no plan)
- [x] #1 — added a `Resume:` field to the `/checkpoint` template (`claude/commands/checkpoint.md`): cold-start pointer (file to open, what's stubbed, line/function to start at)
- [x] #7 — recorded the Two-Path principle as an authoring rule (script action ⇔ hand-editable equivalent) in README "Mental model" + `identity.md` Orchestration

## Done
_(checked items stay above until the file is rolled)_
