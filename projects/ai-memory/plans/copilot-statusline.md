---
plan: copilot-statusline
status: active
created: 2026-07-17
owner: claude (orchestrator)
task_provider: notion
task_ref: 3a0f6850-c619-8121-8bdf-f109446a4086
---

# Copilot statusline (memory-aware)

## Goal

Give GitHub Copilot CLI the same memory-aware statusline Claude and Antigravity
have — active project (🧠), folder, git branch, and `📋 N open` todos (shared
`_lib.sh count_open_todos`), plus a context-usage bar. Copilot exposes a
script-hook `statusLine` (`~/.copilot/settings.json`, JSON payload on stdin,
same model as Claude) gated behind the experimental `STATUS_LINE` flag — so
unlike Codex it can carry the full line.

## Success criteria

- [ ] `harnesses/copilot/statusline.sh` renders, from Copilot's stdin payload:
      line 1 `[model] 📁 folder 🌿 branch 🧠 project 📋 N open`; line 2 a
      context-usage bar + %. Project + `📋` appear only when a project resolves;
      N matches `count_open_todos`. jq-optional, bash-3.2-safe, never crashes.
- [ ] Manifest declares `statusline = ~/.copilot/statusline.sh`; install.sh
      symlinks it into place for the copilot (`copilot_hooks_json`) archetype —
      verified by a driver test.
- [ ] The settings.json `statusLine` entry **and** the `feature_flags.enabled:
      ["STATUS_LINE"]` flag are a documented manual step (install closing
      notes + `docs/harnesses/copilot.md`), not auto-written.
- [ ] `docs/harnesses/copilot.md` has a statusline section (payload fields
      used, the manual settings snippet, the experimental-flag caveat).
- [ ] Suite green (`run-tests.sh`) including new copilot statusline assertions
      (project → `N open`; dormant → no segment; no-jq fallback).

## Design

Mirror `harnesses/claude/statusline.sh` (closest analogue — same stdin-JSON
script-hook model), adapting to Copilot's payload:

- **Fields:** `model.display_name`, `workspace.current_dir` (folder + the dir
  git branch is derived from, exactly as Claude does — Copilot's payload has no
  local git-branch field), `context_window.current_context_used_percentage`
  (fallback `.used_percentage`) for the bar. Copilot has **no** `total_cost_usd`
  (its `cost.*` is durations/lines/premium-requests), so line 2 is the context
  bar only — no cost segment.
- **Memory segments:** source `_lib.sh`, `detect_active_project "$cwd"`, and
  `count_open_todos "$MEMORY_DIR/projects/$PROJECT/todo.md"` → `📋 N open` next
  to 🧠, both gated on a resolved project. Same guard/degrade discipline as the
  other two (missing lib/jq ⇒ omit, never crash).
- **Install wiring (symlink, Claude pattern):** manifest `statusline =
  ~/.copilot/statusline.sh`. The driver's statusline symlink currently lives
  inside `_hook_install_scripts`, reached only by the `hooks_dir` (Claude)
  branch; Copilot installs via `copilot_hooks_json` and never reaches it.
  **Hoist** the symlink into a small `_hook_link_statusline` called at
  `driver_install` top level whenever the `statusline` key is set (parallel to
  the existing `statusline_settings` block) — one code path, both harnesses,
  no double-link for Claude (remove it from `_hook_install_scripts`).
- **Settings + flag stay manual** (user-decided 2026-07-17): install symlinks
  the script but does not touch `~/.copilot/settings.json`; the `statusLine`
  entry + `feature_flags.enabled:["STATUS_LINE"]` are a documented step. Avoids
  auto-flipping an experimental flag; consistent with Claude's user-owned
  `statusLine` precedent.

Rejected: auto-merging the settings entry + flag (agy pattern) — would enable
an experimental feature under the user and widen driver surface; keeping the
symlink inside the Claude-only branch and duplicating it for copilot (two code
paths for one behaviour); a cost segment (no USD field in Copilot's payload).

## Decisions (locked)

- Symlink-wire the script; settings entry + `STATUS_LINE` flag are a documented
  manual step (user-decided 2026-07-17).
- Reuse the shared `_lib.sh count_open_todos` (shipped in the prior task) — no
  new counter.
- Emoji-default glyphs (matches Claude); no cost segment.

## Phases

- [x] Phase 1 — `harnesses/copilot/statusline.sh` (mirror Claude, adapt fields
      + memory segments).
- [x] Phase 2 — manifest `statusline` key; hoist `_hook_link_statusline` in
      `drivers/hook.sh` so the copilot branch symlinks it; driver test.
- [x] Phase 3 — copilot statusline tests (project / dormant / no-jq).
- [x] Phase 4 — `docs/harnesses/copilot.md` statusline section + install
      closing-notes manual step.
- [x] Phase 5 — validate (cross-model), live render (real payload), PR.
      (Executor codex `89253f3`; suite 47/0 @ LC_ALL=C; cross-model validate:
      ACCEPT; PR #76. Awaiting human merge.)

## Risks / open questions

- `STATUS_LINE` is experimental — its payload schema or the settings key could
  change. The doc section names it as the caveat/revisit anchor.
- Copilot fires the statusline "after each model response"; confirm the render
  is responsive (single awk over one small file — no git/network beyond the
  branch lookup Claude already does).
- Live render needs the flag enabled in a real Copilot session (manual) — Phase
  5 does a fixture/real-payload render; full interactive proof is
  flag-gated.
