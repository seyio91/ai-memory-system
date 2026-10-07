---
plan: batch-payload-checks-across-projects-in-lint
status: in_progress
created: 2026-10-07
owner: claude (orchestrator)
task_provider: local
task_ref: batch-payload-checks-across-projects-in-lint
---

# Batch payload checks across projects in lint

## Goal
Let `check-memory-size.sh --payload` take several projects in one call so the project-independent domain-index render and the initiative alert are computed once per run rather than once per project, and have `lint-memory.sh` use it, cutting lint from ~17 s to ~11 s with identical findings.

## Success criteria
- `lint-memory.sh` full stdout is identical before/after on the real tree (same WARN/ERROR lines, same order).
- `lint-memory.sh` wall time ≤ 12 s (was ~16.8 s), measured before/after.
- `check-memory-size.sh --payload <p>` (single project, the write guard's path) output and exit code unchanged for every real project; guard wall time not worse than ~0.7 s.
- `check-memory-size.sh --payload p1 p2 …` output equals the concatenation of the per-project runs, in argument order, for every real project.
- `--working` with more than one project is a usage error (exit 2).
- `bash scripts/run-tests.sh` green (signing disabled locally); summary counter reconciled against the file count.
- `docs/scripts.md` usage row updated; `check-docs` passes; `changelog.d/<id>.fix.md` present.

## Design
`--payload` accepts one or more project names; `check_payload` runs per project in argument order inside one process. Cache scoping:
- **Run-scoped (computed once):** domain-index stats (`_cms_domain_*`), manifest fields/min cap, slicer MAX.
- **Project-scoped (reset per project):** targeted flag, alert stats.
- **Alert text keyed by the ordered list of active initiatives targeting the project.** `_compute_initiative_alert_lines` is a pure function of that list (glob-order concatenation of each initiative's stale lines), so projects sharing the same list share one `--alert-lines` subprocess. The list comes from the same one-subprocess `lib.sh` call that answers "targeted?" today (`_initiative_targets_project` per initiative), so no extra fork per project; empty list ⇔ not targeted.

`lint-memory.sh` collects all project names and makes one `--payload` call. The guard keeps calling with a single project.

Rejected:
- On-disk cache shared by guard runs — invalidation surface across initiatives, plans, todos.
- Per-initiative alert memo inside `lib.sh` — the alert runs in a subprocess, so an in-process memo there would not survive; keying in the caller is where the reuse is visible.
- Teaching `render-session-payload.sh --alert-lines` multiple projects — moves the batching into the renderer for no extra saving.

## Decisions (locked)
- Behaviour-preserving for single-project callers; no output format change.
- System change → branch + PR via `git-cli ship --intent`.

## Phases

### Phase 1 — Multi-project `--payload` in check-memory-size.sh
Arg parsing for 1+ projects (`--working` only with exactly one); split caches into run-scoped vs project-scoped; key the alert cache by the targeting-initiative list.
**Verify:** for every real project, single-project output + exit code identical to `main`; multi-project output equals concatenated single runs; `--working` with 2 projects exits 2; `test_check_memory_size.sh` green.

### Phase 2 — lint-memory.sh uses one batched call; docs, changelog, measure
**Depends:** P1
Replace the per-project loop with one call; update `docs/scripts.md`; add fix fragment; time lint and the guard before/after.
**Verify:** lint stdout identical to baseline; lint ≤ 12 s; full suite green; `check-docs` passes; fragment present.

## Risks / open questions
- Fail-open scope widens: a checker crash mid-run now drops findings for the remaining projects, not just one. Script is `set -uo pipefail` without `-e` and every render is already a fail-open subprocess, so the exposure is a bug in the checker's own loop.
- Global caches leaking between projects would produce plausible-but-wrong findings for later projects — Phase 1's per-project equivalence check is the guard against this.
