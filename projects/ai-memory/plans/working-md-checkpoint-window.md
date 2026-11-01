---
plan: working-md-checkpoint-window
status: in_progress
created: 2026-11-01
owner: claude (orchestrator)
task_provider: notion
task_ref: 3dbf6850-c619-813b-8532-e4943c94375d
risk: medium
---

# Plan — Keep newest working.md loaded; warn before the payload cap

## Goal
Every session loads the newest working.md state: the payload carries only the newest checkpoints (a render window), so tail truncation can never drop the latest entries first; checkpoints always land in `## Checkpoints`; and the session is warned before the payload reaches its chunk cap.

## Success criteria
- R1 — Rendering a working.md with 7 checkpoints yields only the newest 2 `### ` entries under `## Checkpoints`; preamble lines before the first entry (e.g. the `_(rolled …)_` line) pass through, followed by one `_(5 older checkpoints not loaded — see working.md)_` line (absent when nothing is omitted); every other section is identical to the unfiltered render (not the raw file — `xml.sh`'s `$(cat …)` already strips trailing newlines). Proven on both formatters (xml, md).
- R2 — `AI_MEMORY_CHECKPOINT_WINDOW=3` renders 3; the var has a row in `docs/scripts.md` and `bash scripts/check-docs.sh` passes.
- R3 — Rendering never modifies working.md (file hash identical before/after a session-start render).
- R4 — If the filter fails, the unfiltered file is rendered (fail-safe), proven by an injected failure.
- R5 — `check-memory-size.sh --payload` measures the windowed payload (same render path as the hook).
- R6 — `lint-memory.sh` WARNs on a checkpoint entry outside `## Checkpoints` — a dated `### YYYY-MM-DD` heading whose entry contains a `**Task:**` line (dated learnings headings without it are not checkpoints: fiter-cloudformation and git-cli carry 4 such, which must NOT warn); a mutation removing the rule fails its test; the live tree shows exactly 3 WARNs before the ai-memory fix and 0 after.
- R7 — A payload needing `cap − 1` or `cap` slices carries the near-cap marker at the end of slice `idx == total`, trimmed to fit `MAX` with the same loop the overflow marker uses; `cap − 2` does not; over-cap keeps the existing overflow marker only; the payload tail is otherwise intact.
- R8 — `/checkpoint`, when ≥5 checkpoints sit outside the window after its write, reports it in one line and offers `/checkpoint-archive` (live-exercised).
- R9 — Full gate green (`bash scripts/run-tests.sh`), changed scripts pass under `/bin/bash` 3.2.

## Design
- **Render window (chosen).** Shared `render_working <path>` filter (awk, bash-3.2 safe) applied at the working-section output of `scripts/formatters/xml.sh` and `md.sh`. Finds fence-depth-0 `## Checkpoints`, emits only its last `${AI_MEMORY_CHECKPOINT_WINDOW:-2}` `### ` entries, prefixed by one omitted-count line; all other sections pass through. Covers every harness and injection path (session start, `@memory`, post-compaction) and the size checker, since all render through the formatters. The file is never mutated (Two-Path holds). On filter failure, emit the raw file.
- **Placement.** Convention: `## Checkpoints` is the last section of working.md, so an end-of-file append is correct. `docs/file-formats.md` → `working.md shape` + `/checkpoint` prose state it (`projects/_template/working.md` is empty by design — nothing to edit there); lint WARN on dated entries outside the section. One-time hand fix of ai-memory's working.md (move `## Open threads` above `## Checkpoints`, relocate the 4 misfiled dated entries). Other projects already have Checkpoints last (checked 2026-11-01).
- **Near-cap marker** in `scripts/payload-slices.py`, which already knows slice count and cap: at count ≥ cap − 1 append a marker line to the last slice. Chunked harnesses only (claude, codex).
- **`/checkpoint` warning** keyed on hidden count (entries outside the window) ≥ 5, not file size — file size no longer governs what loads.
- Rejected: auto-roll on write → manual writes and other harnesses bypass it. Overflow-aware cut in the slicer → puts working.md structure knowledge in the format-agnostic slicer. File-size trigger for `/checkpoint` → nags without a load-time reason once the window exists. Windowing Open threads / Cross-project learnings → not chronological, "newest" ill-defined.

## Decisions (locked)
- Window = newest 2 by position, overridable by `AI_MEMORY_CHECKPOINT_WINDOW`.
- Open threads and Cross-project learnings out of scope.
- Near-cap = slices ≥ cap − 1. `/checkpoint` warn = hidden ≥ 5.
- copilot/antigravity caps split to their own task.
- No migration script: working.md is personal and gitignored; the lint WARN points at each bad file.
- P1, P2, P3 touch disjoint files and can fan out in parallel; P4 follows P1 + P2 (shares `commands/checkpoint.md` with P2 and reads P1's window var).

## Phases
### Phase 1 — Render window filter
- `render_working` in the shared hook/formatter layer; wire into `formatters/xml.sh` and `formatters/md.sh` working branches.
- Fail-safe fallback to raw file.
- `docs/scripts.md` row for `AI_MEMORY_CHECKPOINT_WINDOW`.
- Tests: 0/1/2/7 checkpoints, missing section, `###` inside a fence, env override, injected failure, both formatters, `check-memory-size.sh --payload` sees the windowed render.

**Depends:** none
**Verify:** R1–R5 pass via new tests; `bash scripts/run-tests.sh --only formatter` and a live `bash scripts/hooks/session_start_memory.sh` render on ai-memory show 2 checkpoints + the omitted line; `shasum` of working.md unchanged.

### Phase 2 — Checkpoints-last placement
- `docs/file-formats.md` (`working.md shape`) + `commands/checkpoint.md`: `## Checkpoints` is the last section.
- `lint-memory.sh` rule: dated `### YYYY-MM-DD` entry containing `**Task:**` outside `## Checkpoints` → WARN; fence-aware (reuse `checkpoint-archive.sh`'s section parser behaviour); seeded-defect + mutation test + negative case for a dated learnings heading.
- Hand-fix `projects/ai-memory/working.md` (gitignored, done by the orchestrator on main).

**Depends:** none
**Verify:** R6 — new lint test passes and fails under mutation; `bash scripts/lint-memory.sh` on the live tree reports 3 misplaced-checkpoint WARNs before the hand-fix (all ai-memory) and 0 after; no WARN on fiter-cloudformation or git-cli.

### Phase 3 — Near-cap marker
- `payload-slices.py`: marker in last slice at slices ≥ cap − 1.
- Tests in `test_payload_slices.sh`: cap − 1 and cap marked, cap − 2 unmarked, tail intact, overflow marker unchanged.

**Depends:** none
**Verify:** R7 — `bash scripts/run-tests.sh --only payload_slices` green, including the cap − 2 negative case.

### Phase 4 — /checkpoint hidden-count warning
- `commands/checkpoint.md`: after the write, count `### ` entries in `## Checkpoints`; if count − window ≥ 5, one-line notice + offer `/checkpoint-archive`.
- Changelog fragment `changelog.d/working-md-checkpoint-window.feature.md`.

**Depends:** Phase 1, Phase 2
**Verify:** R8 — live `/checkpoint` on a scratch working.md with 8 entries emits the notice; with 6 entries it does not.

### Checkpoint — pre-ship
- Full gate (R9), lint set diffed before/after, `/bin/bash` 3.2 run of changed scripts.
- Live exercise: new session on ai-memory shows the window; real `/checkpoint`.
- Validator `scope: final`, cross-model.
- Human review → `git-cli ship` (branch → PR); never merge.

## Risks / open questions
- Open threads keeps growing unbounded; the near-cap marker is the only signal. Revisit if it becomes the overflow cause.
- Window of 2 by position can show two entries from one workstream while another stream's latest is hidden; per-workstream windowing deferred until it bites.
- Whole-payload harnesses (copilot, antigravity) have no declared cap, so no near-cap marker — separate task.
- The window applies to every render path — session start, `@memory`, post-compaction re-inject, and codex's static base from `build-context-md.sh` — so a post-compaction session sees only the newest 2 from disk, whatever it had in context before.
- The window hides older checkpoints from the session; anything still open in them must be in Open threads, todo.md or a task — `/checkpoint-archive`'s open-item check remains the safety net.
