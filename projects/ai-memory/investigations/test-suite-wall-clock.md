---
investigation: test-suite-wall-clock
task_provider: notion
task_ref: 3a1f6850-c619-81e6-b5ca-cc5a68346f42
created: 2026-07-18
owner: claude (orchestrator)
---

# Test-suite wall-clock — where the ~179s actually goes

Measured 2026-07-18 on the dev machine (macOS, bash 3.2 floor), each stage timed
separately in the same hermetic env `run-tests.sh` uses.

## Headline

Full run ≈ **179s**. Bash suite **167.5s (94%)**; all other stages **11.8s (6%)**.

The distribution is extremely skewed:

| Test | Time | Share of suite |
|---|---|---|
| `test_install_harness.sh` | **67.0s** | **40%** |
| `test_validate_manifest.sh` | 18.7s | 11% |
| `test_release.sh` | 15.3s | 9% |
| next 6 files (6-7s each) | ~40s | 24% |
| remaining 39 files | ~26s | 16% |

Median test: **0.24s**. The bottom 30 files together total ~4s — less than the
shellcheck stage alone.

Non-test stages: shellcheck-prod 6.1s, shellcheck-tests 3.5s, check-docs 0.86s,
lint-memory 0.73s, validate-skills 0.36s, python-unittest 0.24s.

## What this refutes

Two assumptions going in, both wrong:

- **"shellcheck is the slow part."** It is 9.6s, ~5%. It was the prime suspect and
  is nearly irrelevant.
- **"`--no-lint` is the speed escape hatch."** It saves ~1.1s. It is a correctness
  toggle, not a performance one, and using it as one is a false economy.

## Why `test_install_harness.sh` is the target

482 lines, 7 `install.sh` invocations, ~10s per invocation. It is 40% of local runs
*and* 40% of both CI matrix legs (ubuntu + macos), so the fix pays twice per push.

It is also the one case the new `--changed` selector cannot help: editing
`install.sh` selects this test, so a "fast" run is still 67s — only ~2.5x better
than the full suite. Selector and speedup are complementary, not alternatives.

## Hard constraint on any fix

This file was **silently broken from `742f083` until 2026-07-18**: 106 of 143
assertions were ungated because an assertion hardcoded a value the code derives
from config, so the matcher found 0 entries and the file still *looked* like one
failing test. See the corresponding gotcha in project memory.

Therefore: **assertion count before == assertion count after** is a required check
on any speedup, and the repaired manifest-derived expectations must not be traded
back for hardcoded ones to save setup time. A faster test that silently covers less
reproduces the exact defect this file already shipped once.

Watch it fail before trusting it — mutate a manifest value and confirm the test
goes red.

## Not investigated

- Whether the ~10s per `install.sh` invocation is inherent (real filesystem work)
  or incidental (redundant full installs where a fixture would do). That profiling
  is the first step of the actual task.
- `test_validate_manifest.sh` (18.7s) and `test_release.sh` (15.3s), the #2 and #3
  costs. Together another 20% — worth a look once the big one lands.
