# Todo snapshot — POS adoption (rolled 2026-06-30)

> Fully-ticked snapshot taken when the POS-adoption thread closed (both plans shipped + merged). Original `todo.md` reset after this snapshot.

## Active

POS adoption — triage + rationale in `archive/wikis/pos-adoption-backlog.md` (all 13 items had a verdict).

Skill subsystem (#4/#5/#6/#10/#11/#12/#13) + quick wins #1/#7 — **shipped** in PR #8 (`aab1575`); plan archived at `archive/plans/skill-subsystem.md`.

### Derived state snapshot → [plan](archive/plans/state-snapshot.md)
- [x] Phase 1 — derivation sources + script-vs-flag decision (#8): standalone `regenerate-state.sh`→`state.md`; mtime not git-log (projects gitignored)
- [x] Phase 2 — `regenerate-state.sh` + `test_regenerate_state.sh` (21 assertions); full suite 19 files green
- [x] Phase 3 — `/state` command + README "Derived state snapshot" note + `.gitignore /state.md`
- [x] POS thread cleanup: archived `state-snapshot.md` plan + both POS triage wikis → `archive/wikis/`; recorded decisions in `memory.md` (shipped PR #9, `c655151`)
