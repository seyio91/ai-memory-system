---
plan: checkpoints-record-changes-and-carry-open-items-forward
status: in_progress
created: 2026-11-05
owner: claude (orchestrator)
task_provider: local
task_ref: checkpoints-record-changes-and-carry-open-items-forward
---

# Checkpoints record changes and carry open items forward

## Goal

Make `/checkpoint` keep one living entry per piece of work (dated Done groups, current Next/Blockers/Resume, every prior open item accounted for), make `/checkpoint-archive` check open items on every rolled entry, and raise the load window default to 5 so open work stays visible without rolling every few days.

## Success criteria

1. **S1 — one entry per piece of work.** `/checkpoint` matches the session's work to an existing `## Checkpoints` entry by its `**Task:**` line (plan, task or PR named). When several entries match (legacy per-session entries), the newest one is the match. A match rewrites that entry in place and moves it to the bottom; no match appends a new entry. The heading keeps its original start date and is never rewritten. Section order is therefore last-touched, not start-date.
2. **S2 — dated Done, current state elsewhere.** On rewrite, Done gains a new `- [YYYY-MM-DD]`-prefixed group at its end and older groups are byte-identical; Next, Blockers and Resume are replaced. An item closed between sessions still lands in today's group, marked as done outside the session.
3. **S3 — nothing drops silently.** Every bullet in the entry's prior Next/Blockers appears in exactly one place afterwards: today's Done group (done, or `moved to task <ref>`), or restated in Next/Blockers. Tracked state (`todo.md` phases, plan, initiative Target) is pointed at, not copied.
4. **S4 — side items are nudged, never captured.** `/checkpoint` writes nothing to the backlog. Its report lists each open Next/Blockers item that has no `todo.md` box, backlog task or initiative Target as a task candidate.
5. **S5 — window default 5, warning on any loss.** `render_working` defaults to 5 (invalid values fall back to 5); `docs/scripts.md` and `commands/checkpoint.md` say 5; `/checkpoint`'s warning fires whenever count > window. `test_render_working.sh` and `check-docs.sh` pass.
6. **S6 — archive checks every rolled entry.** `commands/checkpoint-archive.md` Step 3 runs the tracked-elsewhere open-item check on superseded entries as well as closed ones; classification is otherwise unchanged and `checkpoint-archive.sh` is untouched.
7. **S7 — docs and gate.** `docs/file-formats.md` documents the Done-group shape, the rewrite rule and last-touched ordering; `docs/harnesses/claude.md` rows for `/checkpoint` and `/checkpoint-archive` match; `/threads` shows `<start date> (last touched <date of the last Done group>)`; `changelog.d/<id>.feature.md` names the per-work entry model, the window default and the archive check; full `bash scripts/run-tests.sh` green.

## Design

**Living entry per piece of work.** `/checkpoint` reads the working file (the overlay file when in a worktree), matches by `**Task:**` line, and either rewrites the newest match in place and moves it to the bottom (S1–S3) or appends. The heading shape `### YYYY-MM-DD — <title>` is unchanged, so lint rule 19, `checkpoint-archive.sh --list` and the window formatter see nothing new; the window's "newest N by position" now means last-touched. Reconciliation is model judgement from session context, the same classification `/checkpoint-archive` Step 3 already does; no marker is introduced. The "never delete or overwrite a prior checkpoint" rule is replaced by S1–S2: older Done groups and other entries are never edited.

**Window.** `AI_MEMORY_CHECKPOINT_WINDOW` default 2 → 5. Measured on this project: last 2 entries ≈ 4.4 KB, last 5 ≈ 8.5 KB; Claude registers 12 × 10 KB chunks and uses 6 today. The warning threshold moves from `count − window ≥ 5` to `count > window`. Entries that fall out of the window are not carried; the warning is the signal to roll.

**Archive.** Script unchanged. Step 3 of the command extends the open-item check to superseded entries. Under the new model "superseded" only arises for entries written before this change (or for a legacy entry whose work a living entry continued); once those roll, entries are closed or in-flight only.

Rejected:
- **Append-only with carry-forward** (every session a new entry, open items re-copied each time) — repeats every open item per session; the living entry writes it once.
- **Window carry** (restate open items of an entry about to leave the window into the written entry) — copies one thread's items into an unrelated entry and leaves the pushed-out entry in-flight forever; the window of 5 plus the warning is the chosen mitigation.
- **Heading date span (`start → last`)** — second rewrite rule and a new heading shape for no gain; the last Done group shows the last touch.
- **Standing `## Follow-ups` section** for side items — a third tracker beside `todo.md` and the backlog; tasks are the durable home.
- **Auto-capturing side items as tasks** — a backend write the user never approved.
- **Lint for volatile `/tmp` paths** — parked in the investigation until it recurs.

## Decisions (locked)

- Match key is the `**Task:**` line's plan/task/PR, not the heading and not position; newest match wins.
- Heading keeps the start date only.
- Done groups are `- [YYYY-MM-DD] …` bullets appended per session; Next/Blockers/Resume replaced.
- Pointer, not copy, for anything `todo.md`, a plan or an initiative tracks.
- `/checkpoint` never writes to the task backend; the report lists every untracked open item (no cap).
- Window default 5; warning on any entry outside the window; no carry.
- `checkpoint-archive.sh` is not changed.

## Phases

### Phase 1 — Window default and warning threshold
- `scripts/formatters/working.sh`: default and fallback 2 → 5, header comment.
- `scripts/tests/test_render_working.sh`: the fallback assertion at ~L73 (`falls back to 2`) and the `--payload` cap case at ~L140–161, which relies on the default window fitting a one-chunk cap (larger fixture or explicit window).
- `docs/scripts.md` env-var row; `commands/checkpoint.md` count line (default 5, fire when count > window).
- `bash scripts/check-docs.sh` clean.

**Verify:** `bash scripts/run-tests.sh --only render_working` green; `grep -n 'CHECKPOINT_WINDOW' docs/scripts.md commands/checkpoint.md scripts/formatters/working.sh` shows 5 everywhere; `check-docs.sh` exit 0. (S5)

### Phase 2 — `/checkpoint` living entries
- Rewrite `commands/checkpoint.md` Steps 2–4: match by Task line (newest match); rewrite-in-place-and-move vs append; dated Done groups; reconciliation of prior Next/Blockers (S3); pointer rule; task-candidate lines in the Step 5 report (S4). Step 2's "chronological, oldest at top" becomes last-touched order. Remove the "never overwrite" sentence and the same-day clause; replace with the S1–S2 rules.
- Keep Step 3a (initiative decision stream) and the overlay-path handling as they are.

**Depends:** Phase 1 (the count line it edits).
**Verify:** live exercise on a fixture working file holding (a) two legacy entries for the same work, the newer with two open Next items, one of which this session completed and one tracked nowhere; (b) an unrelated in-flight entry below them. After `/checkpoint`: the newer matching entry is last, its heading unchanged, Done has a new dated group containing the completed item, the open item is still in Next, the older legacy entry and the unrelated entry are byte-identical, and the report names the untracked item as a task candidate. (S1–S4)

### Phase 3 — Archive check, docs, `/threads`
- `commands/checkpoint-archive.md` Step 3: run the open-item check on all rolled entries; drop the "superseded entries hand their state to a later entry, so skip them" clause; note that superseded arises only for pre-change entries or a legacy entry a living entry continued.
- `docs/file-formats.md` `## Checkpoints` block (~L185–201): Done-group shape, rewrite rule, last-touched ordering.
- `docs/harnesses/claude.md` rows for `/checkpoint` and `/checkpoint-archive`.
- `commands/threads.md`: last checkpoint line shows `<start date> (last touched <date of the last Done group>)`; fall back to the heading date when Done has no dated group (legacy entry).
- `changelog.d/checkpoints-record-changes-and-carry-open-items-forward.feature.md`.

**Depends:** Phase 2.
**Verify:** live exercise: a fixture with one superseded entry whose Next holds an item tracked nowhere → `/checkpoint-archive` lists it and asks before rolling; `grep -c 'skip them' commands/checkpoint-archive.md` is 0; `/threads` on a living entry prints both dates and on a legacy entry prints one; `docs/file-formats.md` shows the `- [YYYY-MM-DD]` group; the changelog fragment names all three changes. (S6, S7 docs)

### Phase 4 — Validate and ship
- Full gate `bash scripts/run-tests.sh` (with the gpgsign overrides), final validator pass against S1–S7, `git-cli ship --intent`.

**Depends:** Phases 1–3.
**Verify:** gate green; validator READY; PR open. (S7)

## Risks / open questions

- **Entries grow** by one Done group per session; the archive at close is the only trim. Revisit if entries routinely exceed a few KB.
- **The S3 invariant is not machine-checked.** A model that drops a bullet still drops it silently; a lint for this is out of scope.
- **Entries outside the window are not carried** (rejected above). With three or more parallel threads in one project the oldest-touched one leaves the window; the count > window warning is the only signal.
- **Legacy entries** (written per session) rely on S6 at archive time; nothing back-fills them into the per-work shape.
- **Concurrent sessions on the same work** can clobber each other's in-place rewrite. The append model had the same file-level race; not new, not addressed.
- **Window 5 and the payload cap:** headroom is ample today (6 of 12 chunks used), but a project with very long entries could hit the per-chunk cap sooner than before; `check-memory-size.sh --payload` is the check.
- **Report noise:** the S4 nudge repeats every untracked open item on every `/checkpoint` until it is filed or closed. Uncapped by decision; revisit if it gets long.
