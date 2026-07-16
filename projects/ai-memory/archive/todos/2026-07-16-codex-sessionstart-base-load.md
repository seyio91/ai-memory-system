# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Codex base-load → SessionStart hook (retire generated AGENTS.md) → [plan](plans/codex-sessionstart-base-load.md)
Move Codex's dynamic memory base off the `codex-mem.sh` file-build onto a `SessionStart` hook
(startup inject proven by live probe 2026-07-16); leave a hand-owned static `AGENTS.md` for
workflow rules + overlay. Mirrors the Antigravity model; makes plain `codex` alias-free.
- [x] Phase 1 — `drivers/hook.sh`: format-wrap `session_cmd` (md for codex) + `test_codex_hooks.sh` assertion (branch `e14ba60`, Validator-verified)
- [x] Phase 2 — relocate `session_start_memory.sh` → `scripts/hooks/` (same name); re-point Claude manifest; `AI_MEMORY_SKIP_INJECT` gates + tests (codex untouched) (branch `d70d7f4`, Validator-verified)
- [x] Phase 3 — flip codex manifest (`session_bootstrap`); retire AGENTS.md build; `arm_recompact.sh` → N/N+1 shim; header-keyed migration; bare = skip-inject + doc-bytes-0 (branch `efaa0b1`+`954e4f1`+`0a323ae`, Validator 9/9 PASS; also fixed latent `AI_MEMORY_CWD` overlay-routing bug in the shared session script)
- [x] Phase 3b — chunked hook injection (~10KB/msg hard cap found; chunk transport; domain table RESTORED on corrected numbers; also fixes shipped >10KB post-compact + @memory re-inject truncation) (branch `f49785b`+`e79ecc3`+`bbd73cc`, Validator 7/8→fixes applied; codex-executor-built)
- [x] Phase 4 — verify: 96,399B reassembled BYTE-FOR-BYTE from real codex rollout across 12 chunks; paid E2E probe (model quoted working-tail + identity rule); bare run zero leakage; docs + memory.md/identity.md/domain-codex updated
- [x] Ship: PR #68 merged 2026-07-16 (CI green both jobs); plan done → archived; live install re-registered (12+12 chunked hooks) + AGENTS.md migration run; Notion `39ef6850` closed; N+1 shim-deletion task filed

### Release automation (changelog fragments + computed versioning) → [plan](plans/release-automation.md) ✅ DONE
Phase A merged in PR #63 (`dc98a6f`); Phase B merged in PR #64 (`d69b431`). Pipeline verified in
production: the #64 merge auto-opened a Release v1.4.0 PR, it got CI via `RELEASE_PAT`, and publish
correctly skipped when the user closed it. Plan done + archived; Notion task closed.
- [x] Phase A0 — `.github/workflows/tests.yml` runs `run-tests.sh` (ubuntu + macos/bash-3.2, shellcheck pinned)
- [x] Phase A1 — `changelog.d/` convention + `assemble-changelog.sh` (assemble + `--bump`) + tests
- [x] Phase A2 — `release.sh` consumes fragments + `--ci` non-interactive + tests
- [x] Phase A3 — adopt per-PR fragment step + docs (`changelog.d/README`, `docs/scripts.md`, cutover)
- [x] Phase B — `--prepare`/`--publish` + `release-pr.yml` + `release-publish.yml` (PR #64)

## Done
_(checked items stay above until the file is rolled)_
