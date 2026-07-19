# Archived todo — ai-memory — 2026-07-19

# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.

## Active

### Archive investigation when a task is done → DONE, shipped in PR #81, archived → [plan](archive/plans/archive-investigation-on-task-done.md)
- [x] Phase 1 — `/plan-archive` extension (resolve linked investigation, move it). Fixed a defect the suite could not see: Step 5 said "skip to Step 8" twice, skipping **Step 7, the plan move** — the no-investigation path archived nothing. Live-exercised on `hook-chunk-ordering` (no linked investigation) after the fix: plan moved, source gone.
- [x] Phase 2 — `lint-memory` rule 10 (stale live investigation); mutation-tested both directions (silenced → 3 fail; scan live `plans/` → 4 fail)
- [x] Phase 3 — tests in `test_lint_memory.sh`
- [x] Phase 4 — docs + changelog entry
- [x] Phase 5 — archived `executor-output-normalization` **manually** (`mv`, not `/plan-archive`): no `task_ref` and its plan was already in `archive/plans/`, so the command aborts at Step 2 and rule 10 can't match — the orphan case the Design anticipated. Clears one baseline lint warning.

### Hook chunk ordering envelope → DONE, archived → [plan](archive/plans/hook-chunk-ordering.md)
- [x] Phase 1 — envelope in `emit_hook_chunk` (`scripts/hooks/lib.sh`)
- [x] Phase 2 — tests: `strip_chunks` helper in `_assert.sh`; out-of-order assertions in `test_shared_hooks.sh` + `test_inject_memory.sh`
- [x] Phase 3 — verify: suite 47/1 (the 1 pre-existing at HEAD); mutation-check watched failing; live shuffled reassembly == `render_full` (43,776 B)
- [x] Phase 4 — docs (`docs/harnesses/claude.md` + codex caveat), manifest comment corrected, gotcha in project memory
- [x] Phase 5 — restore the install gate: `test_install_harness.sh` broken since `742f083` (106 of 143 assertions ungated); expectations now manifest-derived, `set +e` so failures report. Suite 48/0.

### Memory injection size guard + compress memory base → DONE, archived → [plan](archive/plans/memory-injection-size-guard.md)
- [x] Phase 1 — measure the inline cap ⚠️ **wrong by ~3x** — measured the Bash tool cap (30,000), not the hook cap
- [x] Phase 1a — validate Phase 1 → refuted: hook `additionalContext` cap is ~10,000 chars, budget 20000 unsafe
- [x] ~~Phase 1b — live-confirm the ~10,000 hook cap~~ — CLOSED, superseded (chunking makes the exact cap non-binding)
- [x] ~~Phase 2 — guard in `lib.sh`~~ — CLOSED, superseded: the overflow marker (`lib.sh:151`) already is the guard
- [x] ~~Phase 3 — tests for the guard~~ — CLOSED, superseded: already covered by `test_shared_hooks.sh:177-179`
- [x] Phase 4 — compress `## Architecture Decisions` (34.2KB → 7.5KB, 37 entries intact, validated + repaired)
- [x] Phase 5a — trim gotchas (15.5KB → 4.4KB, 24 entries intact); memory.md 55.3KB → 17.8KB
- [x] Phase 5b — `/checkpoint-archive` on `working.md` (14.2KB → 3.7KB; 8 entries archived, live backlog carried forward)
- [x] **Real fix** — `session_chunks = 12` applied + registered (12 entries/event; payload now 6 chunks, max 8,711 chars)
- [x] Phase 6 — verify end to end: **`/clear` 2026-07-18 CONFIRMS per-entry budgeting** — 5 chunks ≤8,996 chars all arrived whole, no truncation marker, no spill preview. Exposed a *separate* ordering bug → `plans/hook-chunk-ordering.md`
- [x] Phase 7 — docs delivered via the ordering plan's Phase 4 (`docs/harnesses/claude.md` + codex caveat, manifest comment, memory gotcha); ~~`AI_MEMORY_INJECT_WARN_BYTES`~~ never built
- [x] Criterion 7 — **verified 2026-07-18 (2nd `/clear`, post-ordering-fix)**: 6 chunks, all 5 sections inline, no truncation marker, correct reassembly from arrival order 3,2,5,4,1,6. Criterion 5 closed as a **miss** (AD 7,595 B vs ≤6KB); criteria 1-4, 8 superseded

### Carried out of the injection plan (unowned)
- [x] CHANGELOG entry for the chunking fix (`session_chunks`/`inject_chunks`, per-entry cap, ordering envelope) — shipped across `742f083`/`d154319` with no changelog record. **DONE via PR #78** (`915741c`): fragment `changelog.d/memory-injection-chunking.fix.md` covers all three — the `1/1` fast path + ~10,000-char cap, the `<memory:chunk index of>` ordering envelope, and the overflow marker. `assemble-changelog.sh --check` passes; it renders under `### Fixed`. A fragment, not a `CHANGELOG.md` edit — release assembly is deterministic from `changelog.d/`.
