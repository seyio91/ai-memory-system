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

1. **S1 — one entry per piece of work.** An entry's **work reference** is derived from its `**Task:**` line: the plan slug if one is named (`plan <slug>` or `plans/<slug>.md`), else the task ref, else the PR number; a Task line naming several is matched on any of them. The session's reference is derived the same way from the work it did. `/checkpoint` matches on the plan slug when both sides have one (a plan-bearing entry never matches a session on a different plan, even if they share a task or PR); when either side has no plan, any shared identifier matches. When several entries match, a match on a plan slug outranks a match on a task ref or PR only; among equals, the **bottom-most in the working file** is the match. A match rewrites that entry in place and moves it to the bottom; no match, or no `**Task:**` line to derive from, appends a new entry. On a match the `**Task:**` paragraph (it may wrap) gains that piece's identifiers it lacked, never another piece's, and never loses or rewords any. The heading keeps its original start date and is never rewritten. Section order is therefore last-touched, not start-date. A session that worked on several pieces of work runs the match-and-write steps once per piece, each with its own reference set, in the file order of their matched entries with new entries last; two pieces that resolve to the same entry are one pass; so each piece's entry is updated (or created) on its own; work and side items that belong to no piece go into the last entry written in the session (a session with no piece writes one new entry). Step 3a runs once per session.
2. **S2 — dated Done, current state elsewhere.** Every `/checkpoint` run on a matched entry appends one new `- [YYYY-MM-DD]`-prefixed group at the end of Done — always a new group, never merged into an earlier one, even on the same day — and older groups are byte-identical; Next, Blockers and Resume are replaced.
3. **S3 — nothing drops silently.** Before writing, `/checkpoint` looks up the state of every tracker a prior Next/Blockers bullet names, the way `/threads` Step 3 does: `todo.md` boxes, `taskctl get <ref>` for task refs, plan `status:`, `gh pr view` for PR numbers; a lookup that fails leaves the item open. Then every prior Next/Blockers bullet appears in exactly one place afterwards: today's Done group (done this session, done outside the session per the lookup, or `moved to <todo box | task <ref> | plan <slug> | initiative Target>`), or restated in Next/Blockers; a lookup settles an item only when the tracker is the item's own subject (a tracker the item merely mentions or waits on never closes it); a terminal state (`done`/`archived` task, merged or closed PR, ticked box, plan `done`, todo link into `archive/plans/` = archived) lands in Done with that state named, never as "done" when it was not; a plan the entry's own Task names that is absent from `plans/` with no live `todo.md` link counts as archived, any other missing slug is state unknown. A home counts only when the item names it (box text, task ref, plan slug, Target); nothing is searched for. Tracked state (`todo.md` phases, plan, initiative Target) is pointed at, not copied.
4. **S4 — side items are nudged, never captured.** `/checkpoint` writes nothing to the backlog (`tasks/` and `archive/tasks/` listings identical before and after). Its report lists each open Next/Blockers **side item** — one that is not a step of the entry's own piece of work — that names no `todo.md` box, backlog task, plan or initiative Target as a task candidate (an entry's own steps close with the entry and need no other home); these lines are exempt from the report's three-line cap.
5. **S5 — window default 5, warning on any loss.** `render_working` defaults to 5 (invalid values fall back to 5); `docs/scripts.md` and `commands/checkpoint.md` say 5; `/checkpoint`'s warning fires when count > window and not when count = window. `test_render_working.sh` green.
6. **S6 — archive checks every rolled entry.** `commands/checkpoint-archive.md` Step 3 runs the tracked-elsewhere open-item check on superseded entries as well as closed ones, and its justification no longer says `/checkpoint` forbids editing a prior entry; classification is otherwise unchanged and `git diff --stat main -- scripts/checkpoint-archive.sh` is empty.
7. **S7 — docs and gate.** `docs/file-formats.md` documents the Done-group shape, the rewrite rule and last-touched ordering; `docs/harnesses/claude.md` rows for `/checkpoint` and `/checkpoint-archive` describe the new behaviour; `/threads` shows `<start date> (last touched <date of the last Done group>)`; `changelog.d/<id>.feature.md` names the per-work entry model, the window default and the archive check; full `bash scripts/run-tests.sh` green.

## Design

**Living entry per piece of work.** `/checkpoint` reads the working file (the overlay file when in a worktree), derives the session's work reference, matches by shared identifier (S1), and either rewrites the bottom-most match in place and moves it to the bottom (S1–S3) or appends. The heading shape `### YYYY-MM-DD — <title>` is unchanged, so lint rule 19, `checkpoint-archive.sh --list` and the window formatter see nothing new; the window's "newest N by position" now means last-touched. Reconciliation of prior items starts from tracker lookups (S3) and falls back to session context; a state that cannot be read keeps the item open. The "never delete or overwrite a prior checkpoint" rule is replaced by S1–S2: older Done groups and other entries are never edited.

**Window.** `AI_MEMORY_CHECKPOINT_WINDOW` default 2 → 5. Measured on this project (`awk` over the last N `### ` entries of `projects/ai-memory/working.md`): last 2 ≈ 4.4 KB, last 5 ≈ 8.5 KB. Slices are 9,000 bytes (`scripts/payload-slices.py:17`), 12 chunk entries are registered (`harnesses/claude/manifest`), and this session's injection arrived as `of="6"`. `bash scripts/check-memory-size.sh --payload ai-memory` exits 0 silently at both windows. The warning threshold moves from `count − window ≥ 5` to `count > window`. Entries that fall out of the window are not carried; the warning is the signal to roll.

**Archive.** Script unchanged. Step 3 of the command extends the open-item check to superseded entries. Under the new model "superseded" only arises for entries written before this change (or for a legacy entry whose work a living entry continued); once those roll, entries are closed or in-flight only.

Rejected:
- **Append-only with carry-forward** (every session a new entry, open items re-copied each time) — repeats every open item per session; the living entry writes it once.
- **Window carry** (restate open items of an entry about to leave the window into the written entry) — copies one thread's items into an unrelated entry and leaves the pushed-out entry in-flight forever; the window of 5 plus the warning is the chosen mitigation.
- **Heading date span (`start → last`)** — second rewrite rule and a new heading shape for no gain; the last Done group shows the last touch.
- **Standing `## Follow-ups` section** for side items — a third tracker beside `todo.md` and the backlog; tasks are the durable home.
- **Auto-capturing side items as tasks** — a backend write the user never approved.
- **Lint for volatile `/tmp` paths** — parked in the investigation until it recurs.

## Decisions (locked)

- One match-and-write pass per piece of work the session touched.
- Match key is a shared plan slug, task ref or PR number between the session's work and the entry's `**Task:**` line; the plan slug takes priority when both sides have one; bottom-most match wins; no Task line never matches.
- Heading keeps the start date only.
- Done groups are `- [YYYY-MM-DD] …` bullets, one new group per `/checkpoint` run, never merged; Next/Blockers/Resume replaced.
- Prior items are reconciled from tracker lookups first, session context second; unknown state stays open.
- Pointer, not copy, for anything `todo.md`, a plan or an initiative tracks; a move may target any of those or a task.
- `/checkpoint` never writes to the task backend; the report lists every untracked open item (no cap; exempt from the three-line rule).
- Window default 5; warning on any entry outside the window; no carry.
- `checkpoint-archive.sh` is not changed.

## Phases

### Phase 1 — Window default and warning threshold
- `scripts/formatters/working.sh`: default and fallback 2 → 5, header comment.
- `scripts/tests/test_render_working.sh`: every assertion that assumes the default window of 2 — L41, L45, L73 (`falls back to 2`), L104, L130, L132, L166, L173, L178 — plus the `--payload` cap case at ~L140–161: five entries cannot fit a one-chunk cap with the current fixture, so either shrink the entries or pass an explicit window.
- `docs/scripts.md` env-var row (`check-docs.sh` does not compare the Default column, so the grep below is the check); `commands/checkpoint.md` count line (default 5, fire when count > window).

**Verify:** `bash scripts/run-tests.sh --only render_working` green; `grep -n 'CHECKPOINT_WINDOW' docs/scripts.md commands/checkpoint.md scripts/formatters/working.sh` shows 5 and no 2 on those lines; `bash scripts/check-docs.sh` exit 0. (S5 except the warning boundary, which Phase 2 exercises)

### Phase 2 — `/checkpoint` living entries
- Rewrite `commands/checkpoint.md` Steps 2–5: work-reference derivation and bottom-most match (S1); rewrite-in-place-and-move vs append; one new dated Done group per run (S2); tracker lookups then reconciliation of prior Next/Blockers with the four move targets (S3); pointer rule; task-candidate lines in the Step 5 report, exempt from the three-line cap (S4); warning when count > window, stating N = count − window explicitly (the old wording left N implied, and it can now be 1). Step 2's "chronological, oldest at top" becomes last-touched order. Remove the "never overwrite" sentence and the same-day clause; replace with the S1–S2 rules.
- Keep Step 3a (initiative decision stream) and the overlay-path handling as they are.

**Depends:** Phase 1 (the count line it edits).
**Verify:** live exercise on fixture working files, one `/checkpoint` run each; compare with `diff` against a copy taken before the run:
- **match + rewrite:** two legacy entries naming the same plan, the lower one with Next = {an item ticked in the fixture `todo.md`, an item tracked nowhere} and Blockers = {one item}; an unrelated in-flight entry below. After: the lower matching entry is last; heading unchanged; Done ends with one new `[today]` group holding the ticked item as done outside the session; the untracked item and the Blockers item are restated; the older legacy entry and the unrelated entry are byte-identical; the report names the untracked item as a task candidate and nothing else about it.
- **match by PR and by task ref:** one entry whose Task names only a PR number, one naming only a task ref; a session on each matches it.
- **append:** no entry shares an identifier → a new entry at the bottom, every existing entry byte-identical. Same for an entry with no `**Task:**` line.
- **same day twice:** a second run on the matched entry adds a second `[today]` group; the first is byte-identical.
- **pointer:** a prior Next bullet listing two unticked phases becomes a pointer to `todo.md`, not a list.
- **backlog untouched:** `ls tasks archive/tasks` identical before and after every run.
- **warning boundary:** fixtures with 5 and 6 entries (window 5) — no warning line at 5, the warning at 6.
(S1–S5)

### Phase 3 — Archive check, docs, `/threads`
- `commands/checkpoint-archive.md` Step 3: run the open-item check on all rolled entries; drop the "superseded entries hand their state to a later entry, so skip them" clause; reword L13's "`/checkpoint` forbids editing a prior entry" to the new rule (a living entry is rewritten, so a heading or position still says nothing about closure); note that superseded arises only for pre-change entries or a legacy entry a living entry continued.
- `docs/file-formats.md` `## Checkpoints` block (~L185–201): Done-group shape, rewrite rule, last-touched ordering.
- `docs/harnesses/claude.md` rows for `/checkpoint` and `/checkpoint-archive`.
- `harnesses/codex/scripts/codex-mem-checkpoint.sh` (~L108, L112): the scaffold still says "append to WORKING_MD" and writes an undated Done scaffold; align its wording and Done shape with the living-entry rule (the Codex skill text itself is generated from `commands/checkpoint.md`).
- `commands/threads.md`: last checkpoint line shows `<start date> (last touched <date of the last Done group>)`; fall back to the heading date when Done has no dated group (legacy entry).
- `changelog.d/checkpoints-record-changes-and-carry-open-items-forward.feature.md`; and edit the unreleased `changelog.d/working-md-checkpoint-window.feature.md` ("default 2", "5 or more entries") so the two fragments agree — they ship in the same release.

**Depends:** Phase 2.
**Verify:** live exercise: a fixture with one superseded entry whose Next holds an item tracked nowhere → `/checkpoint-archive` lists it and asks before rolling; `grep -c 'skip them\|forbids editing a prior entry' commands/checkpoint-archive.md` is 0; `git diff --stat main -- scripts/checkpoint-archive.sh` empty; `/threads` on a living entry prints both dates and on a legacy entry prints one; `docs/file-formats.md` shows the `- [YYYY-MM-DD]` group and the ordering note; `grep -n 'living\|rewrit' docs/harnesses/claude.md` hits both command rows; the changelog fragment names all three changes. (S6, S7 docs)

### Phase 4 — Validate and ship
- Full gate `bash scripts/run-tests.sh` (with the gpgsign overrides), final validator pass against S1–S7, `git-cli ship --intent`.

**Depends:** Phases 1–3.
**Verify:** gate green; validator READY; PR open. (S7)

## Risks / open questions

- **Entries grow** by one Done group per session; the archive at close is the only trim. Revisit if entries routinely exceed a few KB.
- **The S3 invariant is not machine-checked.** A model that drops a bullet still drops it silently; a lint for this is out of scope.
- **Entries outside the window are not carried** (rejected above). A project with more than five living entries loses the oldest-touched from the payload; the count > window warning is the only signal.
- **Tracker lookups cost time** on every `/checkpoint` (taskctl, gh). Acceptable; `/threads` already pays it.
- **Legacy entries** (written per session) rely on S6 at archive time; nothing back-fills them into the per-work shape.
- **Concurrent sessions on the same work** can clobber each other's in-place rewrite. The append model had the same file-level race; not new, not addressed.
- **Window 5 and the payload cap:** `check-memory-size.sh --payload` passes today at 5, but a project with very long entries could hit the 9,000-byte slice budget sooner than before; that script is the check.
- **A PR-only entry whose work later gets a plan** is matched only if the session names the PR too; a session naming only the plan appends a second entry, and the PR-only one lingers until `/checkpoint-archive` classifies it under S6.
- **An entry naming several pieces of work** (plan A + task B) still matches a session that touched only task B when that session has no plan of its own; plan-slug priority covers the common case, not this one. Rare; accepted.
- **Report noise:** the S4 nudge repeats every untracked open item on every `/checkpoint` until it is filed or closed. Uncapped by decision; revisit if it gets long.
