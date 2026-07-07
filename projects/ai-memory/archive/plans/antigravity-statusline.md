---
plan: antigravity-statusline
status: done
created: 2026-07-07
completed: 2026-07-07
owner: claude (orchestrator)
---

# Plan — Antigravity memory-aware statusline

## Goal
Give the Antigravity CLI (`agy`) a custom statusline — like Claude's — that surfaces the **memory
project**, **folder**, and **brain information** (memory-load state + agy runtime state) at a glance,
auto-wired by the memory system's installer.

## Success criteria
- `harnesses/antigravity/statusline.sh` reads agy's stdin JSON payload and prints a formatted (ANSI)
  statusline containing: the active **memory project**, the **folder** (cwd basename), git **branch**
  (+dirty), **model**, a **context-window %** bar, and **agent state** (+ subagent/task counts).
- **Memory project + folder** resolve from `AI_MEMORY_PROJECT` / `AI_MEMORY_CWD` (exported by `agy.sh`),
  falling back to walking up `$PWD` for `.agents/memory-project`; a memory-load glyph shows when the
  project resolved (dormant otherwise).
- **Nerd Font glyphs with an emoji/text fallback** via `USE_NERD_FONTS` (default on; `false` → emoji).
- **Responsive** — collapses segments by `terminal_width` (wide single-line / medium two-line / narrow
  compact), no line-wrap.
- `install.sh --harness antigravity` **auto-wires** it: merges `{"statusLine": {...}}` into
  `~/.gemini/antigravity-cli/settings.json` (idempotent, **preserving** existing keys like `colorScheme`
  / `trustedWorkspaces`), pointing at the repo script. Re-run leaves a single entry.
- Tests: statusline renders expected segments from a sample payload (jq present + absent fallback);
  install registers `statusLine` without clobbering existing settings. Docs updated. Full suite green.

## Design
Reached via clarification (2026-07-07). Mechanism reverse-engineered from `agy` v1.0.16 + the official
`examples/statusline` and the community `agy-statusline`.

**agy contract.** agy invokes `settings.json → statusLine.command` each render, piping a JSON payload on
stdin: `.agent_state`, `.model.display_name`, `.context_window.used_percentage`, `.vcs.branch`,
`.vcs.dirty`, `.sandbox.enabled`, `.subagents`, `.task_count`, `.artifact_count`, `.terminal_width`. The
script prints the statusline to stdout. Config shape: `{"statusLine": {"type": "", "command": "bash
<script>", "enabled": true}}`. (There's also a `/statusline on|off` in-CLI toggle.)

**Script (`statusline.sh`).** Single `jq` pass over stdin (fallback to defaults if jq is absent).
Segments = memory (🧠 project + load state) · 📁 folder · branch(+dirty) · model · ctx bar+% · agent
state (+subagents/tasks). Memory project from `AI_MEMORY_PROJECT` (env, exported by `agy.sh`), else
`detect_active_project` walking up `$PWD`; folder from `AI_MEMORY_CWD` else `$PWD`. Nerd Font glyphs with
`USE_NERD_FONTS=false` → emoji/text. Responsive tiers modeled on the official example (wide/medium/narrow).

**Wiring (chosen: auto via install).** Antigravity uses a JSON settings file, not a symlink (Claude's
`statusline` key symlinks a script into `~/.claude/`). So the manifest gets a JSON-merge pair —
`statusline_settings = ~/.gemini/antigravity-cli/settings.json` + `statusline_script =
$MEMORY_DIR/harnesses/antigravity/statusline.sh` — parallel to `hooks_json`/`hook_script`. The `hook`
driver's registration step merges the `statusLine` entry into settings.json via the same idempotent
python3 merge used for hooks.json, preserving existing keys.
- *Rejected — reuse Claude's `statusline` symlink key:* Antigravity registers via a settings.json field,
  not a symlinked path; the mechanisms differ (like `hooks_dir` vs `hooks_json`).
- *Rejected — manual wire (print a snippet):* the user chose auto-wire for parity with the hooks flow.

## Decisions (locked)
- **Brain info = both** memory-load state **and** agy runtime state, responsive by terminal width.
- **Auto-wire via `install.sh`** (settings.json JSON-merge, idempotent, preserves existing keys).
- **Nerd Font glyphs with `USE_NERD_FONTS` emoji fallback** (default on).
- Memory project/folder resolve from the `agy.sh`-exported env first, cwd walk-up fallback.

## Phases
### Phase 1 — the statusline script
- `harnesses/antigravity/statusline.sh`: stdin parse (jq + fallback), memory project/folder resolution,
  Nerd Font/emoji glyph set, responsive segment rendering.

### Phase 2 — install wiring
- Manifest: `statusline_settings` + `statusline_script`. `hook` driver: merge `statusLine` into
  settings.json (idempotent, preserve keys). `validate-manifest`: register the new keys.

### Phase 3 — tests + docs
- Tests: statusline render (jq present/absent, project resolved/dormant, responsive width); install
  registers statusLine without clobbering. Docs: `docs/harnesses/antigravity.md` statusline section.

## Risks / open questions
- **statusline cwd/env** — the statusline command's cwd may be the config dir (like hooks) rather than
  the workspace; the `AI_MEMORY_PROJECT`/`AI_MEMORY_CWD` env exported by `agy.sh` is the reliable source
  (only set when launched via the wrapper). Direct `agy` (no wrapper) → project may be blank; acceptable.
- **jq dependency** — the official script requires `jq`; provide a graceful no-jq fallback (degraded
  segments) so the statusline never errors the CLI.
- **Nerd Font** — glyphs need a Nerd Font in the terminal; the `USE_NERD_FONTS=false` toggle covers the
  rest. Documented, not enforced.
- Live visual verification needs a real `agy` TUI session (the render can be unit-tested headless by
  piping a sample payload).
