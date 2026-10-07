---
plan: make-the-initiative-alert-computation-cheap
status: in_progress
created: 2026-10-07
owner: claude (orchestrator)
task_provider: local
task_ref: make-the-initiative-alert-computation-cheap
---

# Make the initiative-alert computation cheap

## Goal
Cut `initiative-status.sh`'s per-call cost by resolving plan `task_ref`s with one awk pass per plans directory instead of one `extract_fm_field` fork per plan file per Target, so the initiative alert stops dominating lint and the memory write guard.

## Success criteria
- `bash scripts/initiative-status.sh <slug>` stdout is byte-identical before/after for every real initiative (`memory-md-hygiene`, `vault-eks`), and the `.state/` snapshot is untouched by the comparison runs.
- `initiative-status.sh memory-md-hygiene` wall time ≤ 0.25 s (was ~0.68 s).
- `bash scripts/run-tests.sh` green; summary counter reconciled against the file count.
- `bash scripts/lint-memory.sh` WARN **set** unchanged before/after; lint wall time recorded before/after (target ≤ 10 s, was ~27-30 s).
- Guard cost on an ai-memory `memory.md` write recorded before/after.
- Exact-match semantics preserved: a `task_ref` that is a prefix of another never matches, and only frontmatter `task_ref` counts (pinned by a test).
- `changelog.d/<id>.fix.md` fragment present.

## Design
Hot spot: `find_task_plans` (`scripts/initiative-status.sh`) loops `"$dir"/*.md` calling `extract_fm_field` per file, and is called twice per `software_adw` Target with a `task:` (live `plans/`, then `archive/plans/`). With 7 ai-memory Targets × 63 archived plans that is ~440 awk forks per call.

Fix: build a per-directory index once — a single awk over all `*.md` in the dir emitting `<task_ref>\t<path>` from frontmatter only (same `---` bounds and trailing-whitespace trim as `extract_fm_field`) — memoized per dir for the run; `find_task_plans` then filters the index by exact string equality. Output, ordering (glob order) and fail-closed duplicate reporting stay identical.

Rejected:
- Persistent on-disk cache keyed on mtimes — invalidation surface across plans/archive/todo/initiative files; not needed if the in-process fix lands the cost.
- `grep -l '^task_ref: <ref>$'` — matches outside frontmatter and diverges from `extract_fm_field`'s whitespace handling.
- Per-slug memo across projects in `check-memory-size.sh` — only if P2's measurement says lint is still too slow.

## Decisions (locked)
- Behaviour-preserving refactor; no output format change.
- System change → branch + PR via `git-cli ship --intent`.

## Phases

### Phase 1 — Batch task_ref lookup in initiative-status.sh
Replace the per-file fork loop with a memoized per-directory awk index; add a test pinning exact-match + frontmatter-only semantics (prefix ref, body-only `task_ref:` line).
**Verify:** before/after stdout diff empty for both real initiatives; timing ≤ 0.25 s; `test_initiative_status*` + full suite green.

### Phase 2 — Measure end-to-end and decide on cross-project memo
**Depends:** P1
Time `lint-memory.sh` and a guarded ai-memory `memory.md` write before/after; compare WARN sets. Only if lint > 10 s, add per-slug memoization in `check-memory-size.sh`. Add changelog fragment.
**Verify:** recorded before/after numbers; identical WARN set; fragment present.

## Risks / open questions
- Snapshot side effect: `initiative-status.sh` writes `initiatives/.state/<slug>.snapshot` on first run / stream-count change / `--ack`. Comparison runs must not ack; checksum the snapshot before/after.
- Glob ordering must match the old loop so the duplicate-plan evidence lists paths in the same order.
