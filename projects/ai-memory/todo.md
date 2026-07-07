# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Antigravity memory-aware statusline → [plan](plans/antigravity-statusline.md)
_Design locked 2026-07-07: memory project + folder + brain info (memory-load + agy runtime), auto-wired via install (settings.json merge), Nerd Font w/ emoji fallback._
- [x] Phase 1 — statusline.sh (stdin parse + memory/folder resolution + responsive render) — verified across widths + no-jq fallback
- [x] Phase 2 — install wiring (manifest statusline_settings/_script; hook driver settings.json merge; validate-manifest) — merges preserving existing keys
- [x] Phase 3 — tests + docs — 48 antigravity assertions incl. statusline; wired live on real settings.json

## Done
_(checked items stay above until the file is rolled)_
