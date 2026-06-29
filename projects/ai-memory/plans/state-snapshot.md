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

## Phases
### Phase 1 — Derivation sources
- Confirm each column's source + extraction (`_lib.sh` helpers, mtime/`git log`, todo unchecked-count).
- Decide standalone script vs. flag on the index regenerator, and the output path/format.

### Phase 2 — Generator + tests
- Implement the generator (bash-3.2); exclude `_template`; handle missing fields.
- Add a dependency-free test fixture under `scripts/tests/`.

### Phase 3 — Wire-up + docs
- Expose it (script or `/state`-style command), explicitly on-demand.
- Document in README that it's a derived, on-demand awareness view (not injected).

## Risks / open questions
- **"In flight / blocked" fidelity:** `current goal` + open-todo count may under-capture true blockers. The latest `working.md` checkpoint is richer but `working.md` is gitignored/per-machine — decide whether to read it when present or stay purely on tracked sources.
- **`last touched` source:** file mtime is simplest but unreliable across clones/rsync; `git log` is portable but misses uncommitted work. Likely prefer `git log` with an mtime fallback.
- Keep the row lean — this is a ~20-line awareness view, not a dashboard; resist column creep.
