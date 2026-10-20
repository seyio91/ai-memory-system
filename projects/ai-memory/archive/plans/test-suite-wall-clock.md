---
plan: test-suite-wall-clock
status: done
completed: 2026-10-20
created: 2026-10-20
owner: claude (orchestrator)
task_provider: notion
task_ref: 3a1f6850-c619-81e6-b5ca-cc5a68346f42
---

# Cut test-suite wall-clock

## Goal

Cut the full local run from ~10.5 min to about a minute without losing coverage: make the manifest reader stop starting a process for every trim, run test files in parallel, and fix the lint hot path. Design: `test-suite-wall-clock`.

## Success criteria

1. Every test file reports the **same `N passed` count** as the 2026-10-20 baseline on `main` (scratchpad `baseline-counts.txt`, re-derivable by `run-tests.sh --tests-only` on the base commit). No file disappears from the run.
2. `manifest_get` / `manifest_keys` / `manifest_hooks` output is byte-identical to the old implementation for all four shipped manifests and for an edge-case fixture (leading/trailing tabs and spaces, inline `#` comments, `[section]` with padded name, `~` / `~/x` / `$HOME` values, empty value, no trailing newline). Holds under `/bin/bash` 3.2 and bash 5.
3. `bash scripts/validate-manifest.sh harnesses/claude/manifest` < 0.5s (was 6.9s).
4. `run-tests.sh` runs test files in parallel by default; per-file result lines print in the same (glob) order as today; pass/fail totals and the failing-file log dump behave as before; a deliberately failing test still fails the run with its log shown. Job count overridable (env var, documented in `docs/scripts.md` so `check-docs.sh` stays at 0 findings); `1` reproduces sequential behaviour.
5. Three consecutive parallel full runs give identical per-file counts (no shared-state flakes).
6. Full `bash scripts/run-tests.sh` wall-clock on this machine recorded before/after in the investigation; target ≤ 90s.
7. Full gate green: tests, python, shellcheck, check-docs; lint ERROR/WARN set unchanged from base. Changelog fragment present.

## Design

- **manifest.sh** — replace `_mf_trim` pipes with parameter-expansion trim (prototype: 6.9s → 0.08s, identical output on all four manifests, both bash versions). Then memoize `_mf_pairs` per file within a process (one parse per file, not per key) — a plain global keyed by path; invalidate nothing (manifests do not change mid-process). If memoizing adds risk for no measurable gain after the trim fix, drop it and say so.
- **run-tests.sh** — launch each hermetic test in the background writing to its own log + rc file, bounded to N concurrent jobs (bash 3.2: no `wait -n`; use a slot/poll loop or `xargs -P`). After all finish, iterate the list in order to print results exactly as today. Default N = CPU count (`sysctl -n hw.ncpu` / `nproc`), env override.
- **test_lint_memory.sh** — profile first (109 `lint-memory.sh` runs, 80s). Fix only fork-heavy hot spots inside `lint-memory.sh` with the same identical-output bar; do not restructure the test.

## Decisions (locked)

- Coverage is the constraint, speed the goal: any assertion-count drop fails the phase (`test_install_harness.sh` once ran 106/143 assertions ungated while looking green).
- No test is deleted, merged or skipped to save time.
- P1 and P3 touch disjoint files and may run in parallel; P2 is independent of both but its timing criterion is measured after P1.

## Phases

### Phase 1 — fork-free manifest reader
**Depends:** none
**Verify:** criteria 2 and 3; `test_validate_manifest.sh`, `test_install_harness.sh`, `test_executor.sh`, `test_copilot_*`, `test_codex_hooks.sh` counts equal baseline; their times recorded.

### Phase 2 — parallel test runner
**Depends:** none
**Verify:** criteria 4 and 5; a temp `test_zz_fail.sh` (not committed) makes the run exit non-zero with its log printed and is listed in the failure summary; `AI_MEMORY_TEST_JOBS=1` output matches today's format line for line.

### Phase 3 — lint-memory hot path
**Depends:** none
**Verify:** `test_lint_memory.sh` count equals baseline and its time is recorded before/after; `lint-memory.sh` on the real tree prints the identical finding set before and after.

### Phase 4 — record and ship
**Depends:** Phase 1, Phase 2, Phase 3
**Verify:** criteria 1, 6, 7; investigation `test-suite-wall-clock` carries the new measurements; PR open via `git-cli`.

## Risks / open questions

- Parallel runs expose hidden shared state (fixed `/tmp` paths, `$HOME` writes, ports). Criterion 5 is the detector; fix the test's isolation, never serialize around it silently.
- CI macOS runners have fewer cores; gain there is smaller than local.
- A trim rewrite that differs on exotic whitespace (`\r`, non-breaking space) — `[:space:]` covers `\r`; the old sed did too.
