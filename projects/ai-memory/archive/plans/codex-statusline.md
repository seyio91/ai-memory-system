---
plan: codex-statusline
status: done
created: 2026-07-17
completed: 2026-07-17
owner: claude (orchestrator)
task_provider: notion
task_ref: 396f6850-c619-8146-8725-febbf7c600c9
---

# Codex statusline + memory-todo count

## Goal

Investigation settled: Codex CLI (0.144.4) ships a built-in TUI status line
(`/statusline`, `tui.status_line` in `config.toml`) with a **fixed item
vocabulary and no command-backed/custom segment** — so the memory-todo-count
segment structurally cannot be wired. Deliverable: document the finding (config
surface, item list, upstream feature requests, revisit condition) in
`docs/harnesses/codex.md` and close the task.

## Success criteria

- [x] `docs/harnesses/codex.md` has a status-line section stating: the surface
      exists (`/statusline`, `tui.status_line`), the item vocabulary is fixed
      (list verified against the 0.144.4 binary), no custom/script segment
      exists, and therefore no memory segment is possible — with the upstream
      issue refs (openai/codex#20140, #20244) as the revisit trigger.
- [x] Task `396f6850-c619-8146-8725-febbf7c600c9` flipped `done`; plan
      archived; todo rolled.

## Design

Document-and-close — the branch the task summary itself pre-authorized. The
memory system wires a statusline only where the harness exposes a script hook
(Claude `settings.json → statusLine`, Antigravity `settings.json → statusLine`
+ `statusline.sh`); Codex exposes item toggles only, verified two ways:

- Binary probe (0.144.4): item IDs `app-name project-name current-dir activity
  run-state thread-title git-branch context-remaining context-used
  five-hour-limit weekly-limit codex-version used-tokens total-input-tokens
  total-output-tokens thread-id fast-mode model-with-reasoning reasoning
  task-progress` — no `custom`/command item; no statusline-related feature
  flag in `codex features list`.
- Upstream: command-backed statusline rendering is an open feature request
  (openai/codex#20140, #20244).

Rejected alternatives: (a) manifest-wired `statusline_settings`/`_script` pair
— no script surface to target; (b) abusing `thread-title`/`terminal_title` as
a carrier — same fixed-item model, and it fights the user's own settings;
(c) shipping a default `tui.status_line` item set at install — user preference,
not memory wiring; zero memory value without a custom segment.

Dependency note: the "shared memory-todo-count segment" dependency (task
`396f6850-c619-81a4-a573-edac26f5372e`, Claude+Antigravity) dissolves for
Codex — nothing here consumes it. That task stays in the backlog untouched.

## Decisions (locked)

- No Codex statusline wiring until upstream ships a custom segment; the doc
  section is the single revisit anchor.

## Phases

- [x] Phase 1 — add the status-line section to `docs/harnesses/codex.md`;
      close out (task done, plan archived, todo rolled); commit direct to main.

## Risks / open questions

- Upstream may ship command-backed segments (#20140/#20244); the doc section
  names the watch condition. If it lands, reopen as a fresh task (manifest
  `statusline_*` pair + the shared todo-count segment).
