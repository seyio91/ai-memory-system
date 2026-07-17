---
plan: statusline-memory-todo-count
status: active
created: 2026-07-17
owner: claude (orchestrator)
task_provider: notion
task_ref: 396f6850-c619-81a4-a573-edac26f5372e
---

# Statusline memory-todo count for Claude + Antigravity

## Goal

Add a memory-aware open-todos segment (`📋 N open`) to both statuslines —
`harnesses/claude/statusline.sh` and `harnesses/antigravity/statusline.sh` —
counting unchecked `- [ ]` boxes in `projects/<active>/todo.md` via the same
counter `/state` uses. On agy it **replaces** the runtime `tasks` counter
(user-decided 2026-07-17); Claude gains it as a new segment.

## Success criteria

- [ ] `count_open_todos` lives once in `scripts/_lib.sh`;
      `regenerate-state.sh` calls the lib copy (local definition deleted);
      `test_regenerate_state.sh` still green.
- [ ] Claude statusline: with an active project, line 1 shows `📋 N open`
      after the 🧠 project segment; N matches the fence-aware count of
      `projects/<active>/todo.md`; no project ⇒ no segment; render never
      crashes (jq/lib missing ⇒ segment silently omitted).
- [ ] agy statusline: `tasks N` (runtime `.task_count`) is gone; `📋 N open`
      renders in its line-2 slot when a project is resolved, omitted when
      dormant; `subagents` + `sandbox` untouched; Nerd Font variant gets a
      glyph like the other segments; emoji remains default.
- [ ] Both statuslines stay responsive: the count is a single awk pass over
      one small file, no git/network calls added.
- [ ] Suite green (`run-tests.sh`), including updated `test_antigravity.sh`
      statusline assertions (tasks-segment assertions removed/replaced).

## Design

One counter, one home: move `count_open_todos()` (fence-aware awk) from
`regenerate-state.sh` into `scripts/_lib.sh`; `/state` and both statuslines
call it, so the "open todos" fact can't fork (preventing-drift rule).

- **Claude** (`statusline.sh` already sources `_lib.sh`): after resolving
  `PROJECT`, call `count_open_todos "$MEMORY_DIR/projects/$PROJECT/todo.md"`
  and append `📋 N open` to line 1 next to the 🧠 segment. Segment only when a
  project resolves.
- **agy** (`statusline.sh` deliberately lean): guarded
  `. "$MEMORY_DIR/scripts/_lib.sh"` (skip segment if missing — a statusline
  must never crash the CLI); drop `.task_count` from the jq parse and the
  `TSK` segment; new `📋 N open` segment in the line-2 slot where `tasks` sat
  (80–119-col layout; ≥120 layout never showed the counters — unchanged).
  `G_TODO` glyph pair: emoji `📋` default, Nerd Font octal variant under
  `USE_NERD_FONTS=true`.

Rejected: duplicating the awk in each statusline (one fact, three homes);
showing the segment when dormant (no source file to count); keeping agy's
`tasks` alongside (user chose replace — one fewer segment, runtime task count
was low-value).

## Decisions (locked)

- agy: **replace** the `tasks` runtime counter with the memory segment
  (user-decided 2026-07-17); `subagents` stays.
- Counter is shared from `_lib.sh`, not per-script.
- Emoji-default glyphs, Nerd Font opt-in — unchanged convention.

## Phases

- [ ] Phase 1 — lift `count_open_todos` into `_lib.sh`; repoint
      `regenerate-state.sh`; suite green.
- [ ] Phase 2 — Claude statusline segment.
- [ ] Phase 3 — agy statusline: replace `tasks` with the segment; update
      `test_antigravity.sh` assertions; suite green.
- [ ] Phase 4 — validate (cross-model), live render check both harnesses,
      PR.

## Risks / open questions

- A pathological todo.md (huge file) would slow every render — accepted; the
  file is rolled at each plan completion, so it stays small by lifecycle.
- Claude's statusline has no dedicated test file today; Phase 2 rides on the
  shared-lib test + live render check rather than adding a new harness test.
