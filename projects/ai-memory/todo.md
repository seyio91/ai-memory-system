# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Codex compaction_recovery: arm the .recompact sentinel → [plan](plans/codex-arm-recompact-sentinel.md)
- [x] P1 — Spike [GATE]: forced Codex `/compact`; SC1 MATCH (session_id stable across compaction); arm event = `SessionStart source=compact`. VERDICT GO ✅
- [x] P2 — Arm script: harnesses/codex/hooks/arm_recompact.sh + test_codex_arm_recompact.sh (4 assertions); suite green 42/42; committed `37b8514`
- [ ] P3 — Manifest + driver wiring: codex [hooks] compaction_arm role + arm_script; _hook_register_native_json 5th role + ours marker; idempotent re-sync
- [ ] P4 — E2E verify + close: real compaction → full <memory:identity> payload; validator gate; mark plan done

## Done
_(checked items stay above until the file is rolled)_
