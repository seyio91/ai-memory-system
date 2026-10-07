---
plan: memory-size-budgets
status: in_progress
created: 2026-10-07
owner: claude (orchestrator)
task_provider: local
task_ref: add-byte-payload-size-budgets-to-memory-lint-and-write-guard
---

# Memory size budgets — lint + write guard

Initiative `memory-md-hygiene`, Target `ai-memory/size-budget-lint`. Inputs: wiki
`memory-md-content-contract`, investigations `lint-memory-size-and-drift-gaps` and `memory-md-audit-2026-10`.

## Goal

Detect oversized project memory and session-payload truncation at write time and at lint time: WARN when a
project `memory.md` exceeds 16 KB or carries lines over 400 B, ERROR when a project's rendered payload
needs more chunks than a harness's `session_chunks`, and catch bracketed/bulleted dated entries in project memory.

## Success criteria

1. `scripts/check-memory-size.sh --file <memory.md>` emits one WARN for > 16 KB and one WARN per file for lines > 400 B (count + longest line numbers); clean at exactly 16,384 B and exactly 400 B.
2. `scripts/check-memory-size.sh --payload <project>` renders per harness declaring `session_chunks` (claude/xml, codex/md), counts slices with the **same** code delivery uses, and emits ERROR when slices > `session_chunks`. On today's tree: ERROR for `platform-sandbox` on both harnesses, none for any other project.
3. Delivery output is byte-identical before and after the slicer extraction (diff of `emit_hook_chunk` output for every chunk index on the platform-sandbox payload is empty).
4. `check-changelog-drift.sh` flags `**[YYYY-MM-DD]**` and `- **YYYY-MM-DD` in `projects/*/memory.md`; does **not** flag them in `domain/*.md` (domain WARN set unchanged vs. before).
5. `/promote-memory`'s project `## Decisions Log` route no longer writes a date prefix; domain `## Knowledge` route unchanged.
6. `lint-memory.sh` runs both size checks across all projects; new WARN/ERROR set equals exactly: budget WARN on the 7 files > 16 KB, long-line WARN per affected file, payload ERROR for platform-sandbox ×2 harnesses. No other lint line changes.
7. `memory_write_guard.sh`: write to `projects/*/memory.md` → drift + both size checks, exit 2 on any finding; write to `projects/*/working*.md` → payload check only (no drift); exit 0 when clean; still fails open.
8. Every new control is mutation-tested: deleting/inverting each threshold or branch fails at least one test (mutation verified landed with `cmp` + `bash -n`). Tests seed the empty file / empty project case.
9. `bash scripts/run-tests.sh` full run green (file count reconciled with summary); `scripts/check-docs.sh` green; `changelog.d/<id>.feature.md` present.

## Design

- **New `scripts/check-memory-size.sh`** — hand-runnable (Two-Path), same shape as `check-changelog-drift.sh`: `<file>:<line>: <reason>` output, exit 0 clean / 1 findings / 2 usage. Thresholds are constants defined once in this script.
- **Shared slicer** — the greedy line-slicing in `emit_hook_chunk` (inline Python, `MAX = 9000`) moves to one shared location both delivery and the checker call, so the check can never disagree with what is delivered.
- **Payload composition** mirrors `session_start_memory.sh`: `render_full` + initiative alert, per harness format from its manifest.
- **The working file is pinned explicitly, never resolved from cwd.** `render_full` picks `working.<key>.md` from the caller's cwd, so a check run inside a worktree silently drops the shared `working.md` (P1 measured platform-sandbox at 8 slices from the worktree vs. 20 with the real `working.md`). Lint checks one payload per existing working file (shared `working.md` and each `working.<key>.md` overlay); the guard checks the payload with the file just written.
- **Consumers call by subprocess**, not sourcing — matching the initiative checker's fail-open reuse rule.
- **Drift regex** widens only for `projects/*/memory.md`; domain `## Knowledge` stays dated by design.
- **Guard** scope extends to `projects/*/working*.md` (incl. worktree overlays) for payload only.
- Rejected: inline checks in `lint-memory.sh` duplicated in the guard (two definitions drift); byte approximation `bytes ≤ chunks × 9000` (greedy line slicing can pass while delivery truncates); session-start warning (too late, model not at the write); per-line long-line WARN (~160 WARNs bury every other signal); configurable thresholds via `config.local.sh` (new doc-gate surface, no need).

## Decisions (locked)

- Budget 16 KB per `memory.md`; 400 B per line; payload overflow is ERROR, the rest WARN.
- No size checks on `domain/*.md` (lazy-loaded, not injected); no check for harnesses without `session_chunks` (copilot, antigravity).
- This plan does **not** trim any file — lint is expected dirty on landing; trims are the per-project tasks.
- P1 and P3 are independent and may run in parallel.

## Phases

### Phase 1 — Extract the shared slicer
Move slice computation out of `emit_hook_chunk` into one shared helper callable from bash and from a checker (e.g. `scripts/payload-slices.py` with a `--count` mode); `emit_hook_chunk` calls it.
**Verify:** criterion 3 diff is empty for every chunk index; existing chunk/hook tests green; helper `--count` on the platform-sandbox xml payload returns > 12.

### Phase 2 — `check-memory-size.sh` with tests
`--file` and `--payload` modes, thresholds as constants, tests in `scripts/tests/test_check_memory_size.sh` (empty, at-threshold, over-threshold, multi-harness fixture manifests). Add to `docs/scripts.md`.
**Depends:** P1
**Verify:** criteria 1, 2 and 8 for this script; `check-docs.sh` green.

### Phase 3 — Widen drift regex for project memory; drop date prefix from promote's Decisions Log route
Edit `check-changelog-drift.sh` (path-scoped pattern) and `commands/promote-memory.md`; extend its tests.
**Verify:** criteria 4, 5 and 8 for the new pattern; domain WARN set identical before/after (`lint-memory.sh | grep domain/` diffed).

### Phase 4 — Wire into lint and the write guard
`lint-memory.sh` calls the checker for every project; `memory_write_guard.sh` adds size + payload on `memory.md` writes and payload-only on `working*.md` writes. Update the wiki `memory-md-content-contract` "What is enforced today", `docs/` guard description, and add the changelog fragment.
**Depends:** P2, P3
**Verify:** criteria 6 and 7; guard tests cover memory.md, working.md, working.<key>.md, out-of-scope path, and checker-missing fail-open.

### Checkpoint — pre-PR
Full `run-tests.sh` (reconcile file count vs. summary), `lint-memory.sh` new-set diff vs. criterion 6, `check-docs.sh`, live exercise: edit a project `memory.md` and a `working.md` in-session and observe the guard's exit-2 feedback. Validator pass against `## Success criteria`. Then branch + PR via `git-cli ship --intent`.

## Risks / open questions

- **Accepted (2026-10-07):** lint ~27 s (baseline ~5.5 s), guard +~1.4 s per large-project memory.md write — the sound pre-filter forces exact renders on the 5 largest projects, and each pays ~0.9 s for `render_initiative_alert`. Shipped as-is; optimisation tracked as task `make-the-initiative-alert-computation-cheap`.

- Fail-open guard: a crashed checker is silent and reads as clean (same known limitation as the initiative checker).
- Rendering every project × harness may slow `lint-memory.sh`; measure in P4 — if > a few seconds, payload-check only projects whose memory+working exceed a cheap byte pre-filter.
- Copilot/antigravity deliver 1/1 with no cap; if either gains a cap, add `session_chunks` to its manifest and the check picks it up.
- Domain file budgets deferred.
- Engine work belongs in a worktree or branch; plan/todo bookkeeping stays in the main checkout (`MEMORY_DIR` is pinned there).
