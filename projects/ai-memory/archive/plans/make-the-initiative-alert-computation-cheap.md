---
plan: make-the-initiative-alert-computation-cheap
status: done
completed: 2026-10-07
created: 2026-10-07
owner: claude (orchestrator)
task_provider: local
task_ref: make-the-initiative-alert-computation-cheap
---

# Make the initiative-alert computation cheap

## Goal
Cut `initiative-status.sh`'s per-call cost so the initiative alert stops dominating lint and the memory write guard, with byte-identical output.

## Success criteria
- `bash scripts/initiative-status.sh <slug>` stdout is byte-identical before/after for every real initiative (`memory-md-hygiene`, `vault-eks`) and for an edge-case fixture (pipes in cells, padded/tabbed/stage-qualified `depends_on`); `.state/` snapshots untouched.
- `initiative-status.sh memory-md-hygiene` wall time ≤ 0.25 s (was ~0.68 s).
- `bash scripts/run-tests.sh` green; summary counter reconciled against the file count.
- `bash scripts/lint-memory.sh` WARN **set** unchanged before/after; lint and guard wall time recorded before/after.
- `changelog.d/<id>.fix.md` fragment present.

## Design
**Original hypothesis was wrong.** Planned fix was a per-directory `task_ref` index for `find_task_plans`; profiling showed every `memory-md-hygiene` Target is `interactive`, so `find_task_plans` never runs (6 awk / 180 sed forks both before and after that change). Reverted it.

Actual hot spot: ~180 `sed` forks per run — `escape_cell` (`$(printf | sed)` per table cell, 6 × 25) and `trim` + stage-stripping per `depends_on` entry. Fix: bash parameter expansion (`${v//|/\\|}`, `#`/`%` whitespace trim into a `$TRIMMED` global); the stage-qualified `depends_on` path keeps its `sed` (rare, and bash's shortest-suffix match diverges from the regex on malformed input).

Rejected:
- Per-directory `task_ref` index — no measured cost on real initiatives.
- Persistent on-disk cache keyed on mtimes — invalidation surface, not needed.
- Per-slug memo across projects in `check-memory-size.sh` — alert is now ~0.14 s/project (~2.6 s of lint); not worth the coupling.

## Decisions (locked)
- Behaviour-preserving refactor; no output format change.
- System change → branch + PR via `git-cli ship --intent`.

## Measurements (2026-10-07, 19-project tree)
| | before | after |
|---|---|---|
| `initiative-status.sh memory-md-hygiene` | 0.68 s | 0.07 s |
| `lint-memory.sh` | 31.8 s | 16.8 s |
| guard on ai-memory `memory.md` | 1.44 s | 0.68 s |
| lint WARN set | 53 | 53 (identical) |
| suite (signing disabled) | — | 56/56 files, 56 passed |

Remaining lint cost is payload rendering in `check-memory-size.sh --payload` (~0.5 s/project, of which alert ~0.14 s) — outside this task.

## Phases

### Phase 1 — Remove per-call sed forks in initiative-status.sh
Replace `escape_cell`/`trim`/stage-strip `sed` forks with parameter expansion.
**Verify:** before/after stdout diff empty for both real initiatives and the edge-case fixture; timing ≤ 0.25 s; full suite green.

### Phase 2 — Measure end-to-end and decide on cross-project memo
**Depends:** P1
Time `lint-memory.sh` and a guarded ai-memory `memory.md` write before/after; compare WARN sets. Decide on per-slug memoization in `check-memory-size.sh` from the measured alert share. Add changelog fragment.
**Verify:** recorded before/after numbers; identical WARN set; fragment present.

## Risks / open questions
- Snapshot side effect: `initiative-status.sh` writes `initiatives/.state/<slug>.snapshot` on first run / stream-count change / `--ack`. Comparison runs must not ack; checksum the snapshot before/after.
