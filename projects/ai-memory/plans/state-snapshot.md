---
plan: state-snapshot
status: draft
created: 2026-06-30
owner: claude (orchestrator)
---

# Plan — Derived cross-project "In Flight" state snapshot

## Goal
Give a single on-demand view of what's active across all projects — "what's on my plate" — without loading every project's `memory.md`. Unlike POS's hand-maintained `status.yaml`-per-context (which they admit drifts), this view is **derived** from existing sources, so it cannot diverge: it's a projection, regenerated like `index.md`, never hand-authored. Source of decision: `wikis/pos-adoption-backlog.md` item #8.

## Success criteria
- A script (e.g. `scripts/regenerate-state.sh`, or a flag on the index regenerator) produces a single `state.md` "In Flight" table with one row per project: `project | last touched | current goal | open todos`.
- Every column is **derived**, nothing hand-authored: `last touched` from file mtime / `git log`; `current goal` from each `memory.md` `## Current Goal`; `open todos` from each `todo.md` unchecked-box count.
- The view is **on-demand, not auto-injected** — it is not added to the SessionStart hook payload (preserves depth-first; it's the lean awareness layer, compatible with delegate-don't-load).
- Regeneration is idempotent and re-runnable; output cannot drift from sources (re-running with no source change yields no diff).
- macOS bash-3.2 compatible; dependency-free test under `scripts/tests/` covering the derivation.
- `_template` is excluded; the script tolerates projects missing a `## Current Goal` or `todo.md` gracefully.

## Design
- **Projection, not a new source of truth** — same principle as `index.md` (frontmatter-derived) and `domain/pluggable-providers.md`. The anti-pattern to avoid is POS's separately-authored `status.yaml`.
- **On-demand tier** — like `index.md` and domain files, read when asked ("what's on my plate?"), not injected every session. Auto-injecting cross-project state would fight depth-first.
- **Awareness ≠ loading** — the table surfaces *that* sibling work exists; it does not pull sibling `memory.md` into context. Fully compatible with the delegate-don't-load rule.
- **Reuse index machinery** — lean on `_lib.sh` frontmatter extraction and the existing regenerate pattern rather than a new parsing stack.

## Decisions (locked)
- Derived only; no hand-maintained status file.
- On-demand; never added to auto-injection.
- Columns: project, last touched, current goal, open-todo count.
- Standalone `scripts/regenerate-state.sh` → `state.md` (kept off the injection path; not a flag on the index regenerator).
- `last touched` = newest mtime of project files; `git log` rejected (13/14 projects gitignored). `working.md` counts toward recency but adds no column.

## Phases
### Phase 1 — Derivation sources — DONE
Locked decisions (grounded by inspecting the real tree — 14 projects):
- **Standalone script** `scripts/regenerate-state.sh` → writes `$MEMORY_DIR/state.md`. NOT a flag on `regenerate-index.sh`: `index.md` is on the SessionStart injection path, and this view must stay **off** it. Reuses `_lib.sh`.
- **`last touched` = newest file mtime** among each project's key files (`memory.md`, `todo.md`, `working.md`, `plans/*`), formatted `YYYY-MM-DD`. **`git log` rejected:** 13/14 real projects are gitignored (only `ai-memory`/`_template` tracked), so `git log` returns nothing for the projects that matter. mtime works for all; caveat (resets on clone/rsync) accepted for a personal awareness view. `working.md`'s mtime is included — it's the best recency signal — but its *content* is not (no blocker column; resists creep, resolves the risk note).
- **`current goal`** = first non-empty line under `## Current Goal`, truncated (~70 chars) for the table; `—` if absent.
- **`open todos`** = count of `- [ ]` lines in `todo.md` (0 if no file).
- **Sort:** last-touched descending (most recent on top — "what's on my plate").
- **Output:** whole-file generation (not a fenced block), with a "generated / on-demand / not injected — do not edit" header. Idempotent.
- **Exclude** `_template`; tolerate missing goal/`todo.md` gracefully.

### Phase 2 — Generator + tests — DONE
- [x] `scripts/regenerate-state.sh` (bash-3.2): derives the table, excludes `_template`, tolerates missing goal/`todo.md`, sorts last-touched desc, escapes table-breaking pipes, truncates long goals, `--stdout` mode. Idempotent.
- [x] `scripts/tests/test_regenerate_state.sh` — 20 assertions (open-box count, mtime-follows-newest-file, em-dash for missing goal, pipe-escape, truncation, `_template` exclusion, sort order, idempotency, file mode, empty-projects tolerance).

### Phase 3 — Wire-up + docs — DONE
- [x] `/state` command (`claude/commands/state.md`) — regenerates + prints, explicitly on-demand and delegate-don't-load.
- [x] README: `/state` row + a "Derived state snapshot" note (derived, on-demand, never injected, mtime rationale). `.gitignore`: `/state.md` (derived personal artifact).

## Risks / open questions — resolved
- ~~"In flight / blocked" fidelity~~ — **resolved:** stay on the locked columns; `working.md`'s mtime feeds `last touched` (best recency signal) but its content adds no blocker column (resists creep).
- ~~`last touched` source~~ — **resolved to mtime, not `git log`:** 13/14 real projects are gitignored, so `git log` is blank for the projects that matter. mtime works for all; clone/rsync reset caveat accepted for a personal awareness view.
- Row kept lean (4 columns) — no dashboard creep.
