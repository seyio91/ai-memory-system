# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

POS adoption — triage + rationale in `wikis/pos-adoption-backlog.md` (all 13 items have a verdict).

### Skill subsystem → [plan](plans/skill-subsystem.md)
- [x] Phase 1 — `metadata.tier` schema across all skills + docs (#10) — 12/12 classified, validator PASS
- [x] Phase 2 — `scripts/validate-skills.sh` + tests (#4) — 19-assertion test, wired into run-tests, validator PASS
- [ ] Phase 3 — post-run boundary check + violation fixture (#11)
- [ ] Phase 4 — skill creator + installer/intake (#12, #13)
- [ ] Phase 5 — self-rating block + minimal partials, first-party workflow skills only (#6, #5)

### Derived state snapshot → [plan](plans/state-snapshot.md)
- [ ] Phase 1 — derivation sources + script-vs-flag decision (#8)
- [ ] Phase 2 — generator + dependency-free test
- [ ] Phase 3 — on-demand wire-up + README note

### Quick wins (inline, no plan)
- [ ] #1 — add a `resume:` line to the `/checkpoint` template (`claude/commands/checkpoint.md`): prose "open file X, Y is stubbed, start at Z"
- [ ] #7 — record the Two-Path principle as an authoring rule (script action ⇔ hand-editable equivalent) in README/`identity.md`

## Done
_(checked items stay above until the file is rolled)_
