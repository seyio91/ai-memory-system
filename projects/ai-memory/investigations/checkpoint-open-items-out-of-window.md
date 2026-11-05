---
kind: investigation
task_ref: checkpoints-record-changes-and-carry-open-items-forward
slug: checkpoint-open-items-out-of-window
status: scoped; awaiting /start brainstorm gate
created: 2026-11-05
---

# Open items stranded in checkpoints outside the load window

Found while reviewing `platform-sandbox` before a `/checkpoint-archive` run (2026-11-05). Sessions
load only the newest `AI_MEMORY_CHECKPOINT_WINDOW` checkpoints (default 2). Open follow-ups recorded
only in older entries drop out of every session, and `/checkpoint-archive` doesn't fully protect
them.

## Evidence (platform-sandbox, 9 checkpoints, 7 outside the window)

About nine follow-ups lived only in out-of-window entries: no `todo.md` line, task, Target or
`memory.md` entry. One was a security finding: a plain-text SMTP password in a MyCCV config. One was
a test harness kept only under `/private/tmp`, which can be cleared on reboot. Others covered a
crashlooping addon, an unloaded dashboard, a NodePool label to remove, a leftover Secret, a domain
promotion and monitor follow-ups. Most sat in one "carried open items" entry written at an earlier
checkpoint roll, so the carry-forward pattern had already been used once and had already fallen out
of view.

## Gaps

1. **Superseded entries are rolled without an open-item check.** `/checkpoint-archive` Step 3 skips
   them on the assumption that a later entry inherited their state. `/checkpoint` doesn't enforce
   that: a new entry summarises the current task and can drop a side item. In the evidence, the
   `/tmp` harness note was in a superseded entry, and no later entry repeated it.
2. **Keeping an entry doesn't make it visible.** An in-flight entry that is kept stays in
   `## Checkpoints`, but it's still outside the load window. A carry-over entry is "in-flight" for
   as long as its list is open, so it's kept forever and never loaded. The archive guard controls
   what gets archived, not what gets seen.
3. **The window warning names the count but not the content.** "N checkpoints are no longer loaded"
   doesn't say whether any of them hold open items.
4. **Volatile paths are accepted as durable references.** Nothing flags `/tmp` or `/private/tmp`
   paths in memory files, though those paths can vanish.
5. **Entries restate state instead of recording change.** `/checkpoint` synthesises all fields
   from the session's conversation. It reads the working file only to find where to append, never
   the previous entry's Next, `todo.md` or the plan. So each entry restates the plan's state at that
   moment:
   - **Across entries:** "Remaining walkthrough: P3" was Next in three consecutive 2026-11-04
     entries, and the P4c design was described in one entry, then again in the next.
   - **With other files:** the 2026-11-05 entry repeats merged PR numbers and criterion results
     already in `todo.md`, the plan and initiative D55.

   This is the same root as gap 1. With no reconciliation against the previous entry, items are
   both repeated (when the session mentions them) and dropped (when it doesn't).

## Options

- **A. `/checkpoint` carries forward.** When writing a new entry, read the previous newest entry's
  Next/Blockers. Any item not done, superseded or now tracked elsewhere is copied into the new entry.
  This keeps open items inside the window by construction. Cost: entries grow if items never close.
- **B. A standing, always-loaded section.** Add `## Carried follow-ups` to `working.md`, outside
  `## Checkpoints` and loaded every session, as the home for side items that aren't plan work.
  `/checkpoint` and `/checkpoint-archive` move untracked open items there instead of asking or
  keeping. A cap or lint keeps it short.
- **C. Archive checks every rolled entry.** Run the Step 3 tracked-elsewhere check on superseded
  entries too, comparing against the kept entries and the tracked stores. This closes gap 1 only.
- **D. A sharper window warning.** `/checkpoint`'s count line also lists the out-of-window entries
  that still name open items, and points at B or a task. This closes gap 3 only.
- **E. Lint volatile paths.** `/lint-memory` flags `/tmp`, `/private/tmp` and `$TMPDIR` paths in
  memory files. This closes gap 4. **Parked (2026-11-05):** wait until stranded `/tmp` artifacts
  recur. A naive match had 8 hits, most of them legitimate (commands, container facts). If it is
  revived, limit it to `working*.md` and add an opt-out marker.
- **F. Delta-only entries.** `/checkpoint` reads the previous newest entry and records only what
  changed since then. Done is new work only. Next and Blockers say for each prior item whether it
  is done, still open or moved, then add new ones. State that `todo.md`, the plan or an initiative
  already holds is linked, not restated. This closes gap 5 and, through the explicit per-item
  disposition, most of gap 1: an item can no longer disappear without a recorded "done" or "moved
  to …". Cost: `/checkpoint` must read and reconcile the prior entry, and a cold session may need to
  open the linked files for full state, which the Resume line already points to.

## Recommendation (2026-11-05)

**F + C.** Drop B and D, and park E (see above). A is subsumed by F.

- **F is the core fix, with one refinement.** Only **Done** becomes a delta. **Next** and
  **Blockers** restate every still-open item in full, never as a reference to an older entry. Each
  prior Next/Blockers bullet gets a disposition: done, still open (restated), or moved to task
  `<ref>`. This keeps the load window self-contained and makes every drop explicit.
- **C is the safety net for entries written before F.** Step 3 of `/checkpoint-archive`
  (`commands/checkpoint-archive.md`, "so skip them") runs the tracked-elsewhere check on superseded
  entries too. Existing working files, platform-sandbox included, were written without F.
- **Side items go to backlog tasks, not to a new section (drops B).** A third always-loaded tracker
  next to `todo.md` and the backlog duplicates both. "Moved to task `<ref>`" is F's durable home.
- **Gap 2 goes away with F.** Carry-over entries stop accumulating, so there is no need to load
  in-flight entries outside the window.
- **D is unneeded.** With F, open items stay inside the window.

Shape is not fully settled (F's reconciliation step and its wording in `/checkpoint`), so `/start`
runs `design-brainstorm`.

## Open questions

- ~~Does B overlap `todo.md` or the backlog?~~ Yes. B is dropped; side items become tasks.
- ~~Should in-flight entries outside the window be loaded anyway?~~ No. F removes the need.
- How is "open item" recognised in prose Next/Blockers without a marker? Proposed: the unit is a
  Next/Blockers bullet, and each prior bullet gets a disposition. That is the same model judgement
  Step 3 already uses, so no marker is needed. To confirm in brainstorm.
- ~~With F, what does a checkpoint after a no-change session contain?~~ Open items are restated in
  full, so the window keeps every open item; only Done shrinks.
- What does F do with a prior entry from a *different* piece of work (parallel threads in one
  project)? Reconcile only against the newest entry for the same work, or against the newest
  entry overall?

## Immediate remedy used in platform-sandbox

Before archiving: move each untracked item to a durable home (backlog task or a `working.md` section
outside `## Checkpoints`), copy the harness out of `/tmp` into `projects/platform-sandbox/scripts/`,
then run `/checkpoint-archive`.
