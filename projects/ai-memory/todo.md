# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

POS adoption — triage + rationale in `wikis/pos-adoption-backlog.md` (all 13 items have a verdict).

Skill subsystem (#4/#5/#6/#10/#11/#12/#13) + quick wins #1/#7 — **shipped** in PR #8 (`aab1575`); plan archived at `archive/plans/skill-subsystem.md`.

### Derived state snapshot → [plan](plans/state-snapshot.md)
- [x] Phase 1 — derivation sources + script-vs-flag decision (#8): standalone `regenerate-state.sh`→`state.md`; mtime not git-log (projects gitignored)
- [x] Phase 2 — `regenerate-state.sh` + `test_regenerate_state.sh` (20 assertions); full suite 19 files green
- [x] Phase 3 — `/state` command + README "Derived state snapshot" note + `.gitignore /state.md`
- [ ] **POS thread cleanup (after state-snapshot ships):** move `wikis/pos-comparison.md` + `wikis/pos-adoption-backlog.md` → `archive/wikis/` — they are plan references (a comparison + triage backlog), not docs of an existing system component, so they don't belong in `wikis/`; held only because the state-snapshot plan still references the backlog

## Done
_(checked items stay above until the file is rolled)_
