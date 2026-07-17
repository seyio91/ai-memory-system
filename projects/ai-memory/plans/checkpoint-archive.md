---
plan: checkpoint-archive
status: active
created: 2026-07-17
owner: claude (orchestrator)
task_provider: notion
task_ref: 3a0f6850-c619-8177-b4b7-efc1da5d0177
---

# Checkpoint-archive: roll working.md checkpoints independently

## Goal

Give the `## Checkpoints` section of `working.md` its own archival roll — a
`/checkpoint-archive` command + `scripts/checkpoint-archive.sh` mirroring
`/todo-archive` — that snapshots the section to `archive/working/` and resets
only it, decoupled from `/promote-memory`'s learnings-gated whole-file reset.
Fixes the accumulation: closed-task checkpoints pile up because the close-out
never touches `working.md`, `/checkpoint` is append-only, and the only reset
path (`/promote-memory`) aborts when the *Cross-project learnings* section is
empty — which is exactly when checkpoints have grown.

## Success criteria

- [ ] `scripts/checkpoint-archive.sh <working-file> [slug]`: snapshots the
      `## Checkpoints` section (heading + entries) to
      `<project>/archive/working/YYYY-MM-DD-HHMM[-slug].md`, then resets **only
      that section** to a dated `_(none yet — rolled …)_` placeholder. Every
      other section (`## Cross-project learnings`, `## Open threads`, the H1,
      anything else) is left **byte-identical**. bash-3.2-safe (awk, no
      mapfile/assoc arrays).
- [ ] Operates on the **passed working-file path**, not a hardcoded
      `working.md` — so a per-worktree overlay (`working.<key>.md`) rolls
      correctly.
- [ ] No-op guard: an already-empty/placeholder `## Checkpoints` section (or a
      file with no such section) exits 0 and reports "nothing to roll" without
      writing a snapshot.
- [ ] `/checkpoint-archive [slug]` command: resolves the active project's
      working file from the `<memory:active>` breadcrumb (like `/checkpoint`),
      **warns + asks** if any checkpoint entry looks in-flight (no `CLOSED`/
      `DONE` marker) — mirroring `/todo-archive`'s unchecked-items gate — then
      calls the script. Reports snapshot path + counts.
- [ ] Tests (`scripts/tests/test_checkpoint_archive.sh`): sibling sections
      preserved; section reset to placeholder; no-op on empty; slug in
      filename; per-worktree path honored. Suite green (`run-tests.sh`),
      shellcheck + doc-vs-code clean.
- [ ] Docs: `docs/harnesses/claude.md` slash-command table gains the row; a
      one-line cross-ref from `/promote-memory` clarifies the split (learnings
      vs checkpoints).

## Design

Section-scoped roll, script = mechanism / command = policy — the same split
`/todo-archive` (agent) and `/pin`→`memory-pin.sh` (wrapper) already use, but
with a tested script because a section-preserving rewrite of `working.md` is
more error-prone than todo-archive's whole-file copy.

- **Script** (`checkpoint-archive.sh`): awk splits the file at `## `
  second-level headings. Emit the `## Checkpoints` block to the snapshot
  (prefixed `# Archived checkpoints — <project> — YYYY-MM-DD`), then rewrite
  the file with that block replaced by `## Checkpoints\n\n_(none yet — rolled
  <date> to archive/working/<file>)_`. `_template/working.md` is empty, so the
  reset is an inline placeholder, not a template copy. Timestamp from shell
  `date +%Y-%m-%d-%H%M` (same convention `/promote-memory` writes).
- **Command** (`/checkpoint-archive`): thin wrapper. Resolves the working file
  from the breadcrumb (honors worktree overlays), scans entries for a
  `CLOSED`/`DONE` marker, and if any entry lacks one asks "N checkpoint(s) look
  in-flight — roll anyway?" before invoking the script. The record is
  **archived, not deleted** — so `/checkpoint`'s "never delete a checkpoint"
  rule holds (it's relocated to `archive/working/`, same as promote-memory).
- **Decoupled from `/promote-memory`**: independent command; promote-memory
  keeps its whole-file, learnings-gated roll. The two now cover the two halves
  of `working.md` (learnings → promote; checkpoints → checkpoint-archive).

Rejected: CLOSED-only selective roll (needs a status schema on checkpoints —
`CLOSED` is a prose convention, fragile to parse; the in-flight *warning*
gives the safety without the fragility); command-only like todo-archive
(section-preserving rewrite deserves a tested mechanism); auto-roll on task
close (fights the "you decide when the batch is stale" model, and loses
in-flight context); folding into `/promote-memory` (keeps the learnings-gate
coupling that *is* the bug).

## Decisions (locked)

- Roll the **whole `## Checkpoints` section** (snapshot + reset), with an
  agent-side in-flight warning — not a CLOSED-only selective roll.
- Tested **script + thin command**, not command-only.
- Archive (relocate), never delete — preserves the chronological record and
  the `/checkpoint` no-delete rule.
- Reuse the `archive/working/YYYY-MM-DD-HHMM.md` destination + naming that
  `/promote-memory` already uses.

## Phases

- [ ] Phase 1 — `scripts/checkpoint-archive.sh` (awk section split, snapshot,
      inline reset; working-file arg; no-op guard).
- [ ] Phase 2 — `scripts/tests/test_checkpoint_archive.sh` (siblings preserved,
      reset, no-op, slug, worktree path).
- [ ] Phase 3 — `/checkpoint-archive` command (wrapper + in-flight gate) +
      docs (claude.md table row, promote-memory cross-ref).
- [ ] Phase 4 — validate (cross-model), suite green, PR.

## Risks / open questions

- Section detection must be robust to a `## ` heading appearing inside a fenced
  code block within a checkpoint body — guard the awk with fence tracking (same
  pattern `count_open_todos` uses).
- If `## Checkpoints` is the file's last section vs. followed by `## Open
  threads`, the rewrite must place the placeholder correctly either way — a
  test covers both orderings.
- New slash command needs a session restart to autocomplete (known; note in
  the report).
