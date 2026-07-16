# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.

## Active

### Onboard GitHub Copilot as a harness → [plan](plans/onboard-copilot-harness.md)
- [x] Phase 0 — probe verification: real stdin for sessionStart/preToolUse/preCompact/postToolUse, deny semantics (exit-2 warning gotcha), registration schema, read-only tool set, version floor → findings: investigations/copilot-phase0-probes.md; fixtures: scripts/tests/fixtures/copilot/
- [x] Phase 1 — delivery face: manifest + sessionstart.sh adapter (lib.sh reuse, flat envelope) + _hook_register_copilot_json + install.sh entry
- [x] Phase 2 — guard: Copilot stdin path + JSON deny output branch + timeoutSec + real-stdin fixture (fails closed, not warned)
- [x] Phase 3 — compaction + breadcrumb: preCompact sentinel arm + postToolUse re-inject/clear
- [x] Phase 4 — executor face: copilot-mem.sh wrapper + exec_* block; task/explore via executor.sh
- [x] Phase 5 — tests wired into run-tests.sh + docs/harnesses/copilot.md + changelog.d entry
