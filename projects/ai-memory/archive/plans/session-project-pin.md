---
plan: session-project-pin
status: done
completed: 2026-07-20
created: 2026-07-20
owner: claude (orchestrator)
---

# Plan — Session-scoped project pin

## Goal
The active project is re-resolved from cwd on **every** prompt, so a session that `cd`s into
another repo silently repoints every memory write — `/checkpoint`, `/promote-memory`, plan and
todo edits — at the wrong project. Resolve the project **once per session** instead, at
`SessionStart`, and honour that pin for the rest of the session regardless of where cwd wanders.
Executors and subagents are deliberately unaffected: they must keep resolving from their own cwd,
because that is what makes cross-project delegation work.

## Success criteria
- [ ] 1. A session started in repo A, then `cd`-ed into repo B's tree, still renders
      `project=A` in `<memory:active>`, and its `working:` line is A's path.
- [ ] 2. `<memory:active>` carries a `session:` line equal to the hook's `session_id`.
- [ ] 3. When cwd resolves to B while pinned to A, the breadcrumb carries exactly **one**
      `pinned:` note naming both; when cwd and pin agree, no note is emitted.
- [ ] 4. `/pin B --session <id>` mid-session changes the **next** prompt's breadcrumb to B —
      verified by a live exercise, not only by a unit test.
- [ ] 5. With no `session_id` on stdin and no pin file, the rendered breadcrumb is
      **byte-identical** to today's.
- [ ] 6. A pin naming a project whose directory no longer exists falls back to cwd resolution
      rather than emitting a broken path.
- [ ] 7. `SessionStart` writes the pin exactly once across its 12 chunk invocations; the
      compact path writes none.
- [ ] 8. Stale `*.project` files are pruned; fresh ones survive.
- [ ] 9. Full local suite green; `check-docs` passes with `--session` documented.

## Design

**Chosen: a new per-session state file**, `$STATE_DIR/<session_id>.project`, written by
`session_start_memory.sh` and read by `inject.sh`. Purely additive — the working compaction path
is untouched.

Unit boundaries:
- `hooks/lib.sh` — `session_pin_file <session_id>`, alongside `recompact_sentinel`. Single source
  of the path.
- `session_start_memory.sh` — non-compact path only, guarded by `hook_chunk_is_first` (it runs
  12×): resolve, write the pin if a project resolved, prune old pins. The compact path writes
  nothing; the pin from startup already spans compaction under the same `session_id`.
- `inject.sh` — pin wins when valid, else `detect_project "$CWD"` exactly as today.
- `formatters/{xml,md}.sh` — breadcrumb gains `session:` always, and `pinned:` only on divergence.
- `memory-pin.sh` — `--session <id>` writes the pin file in addition to the marker and reverse map.

`inject.sh` is shared across harnesses, so this is written once and degrades by itself: no
`session_id` → no pin → today's behaviour. No harness special-casing.

The write is **unconditional on every non-compact SessionStart**, so the invariant is "the pin
equals the project resolved at the last SessionStart". `resume` and `/clear` re-pin naturally,
and no stale pin can outlive its session with nothing able to clear it.

Every failure path falls back to today's behaviour: absent `session_id`, absent pin file, pin
naming a dead project, unwritable `STATE_DIR`, or a pin pruned under a long-lived session. It
degrades, never corrupts. Retention for `*.project` is 7 days, deliberately longer than the
sentinel's `-mtime +2` — a sentinel is consumed within one prompt, a pin must outlive a
multi-day session.

Alternatives considered:
- **One consolidated per-session state file** replacing `.recompact` and the pin → rejected for
  now: tidier long-term, but it rewrites a compaction path that took live `/clear` testing to get
  right, for no functional gain. Revisit if a third piece of per-session state appears.
- **Pin on every resolution (last one wins)** → rejected: identical to today's flip, fixes nothing.
- **Pin on first successful resolution rather than SessionStart** → rejected: only matters when
  Claude is launched outside the target repo, which the owner confirmed does not happen. Costs a
  state transition for no real coverage.
- **Env var (`AI_MEMORY_PROJECT`) instead of a file** → rejected: env inherits into child
  processes, so an executor launched in a sibling repo would resolve the *orchestrator's* project.
  That is strictly worse than the bug being fixed — and it is a live bug in the antigravity
  harness today (`agy.sh:27` exports it; `preinvocation.sh:30` prefers it over cwd).
- **`/pin` clears pins naming another project** → rejected: cannot identify which pin file belongs
  to this session, so it would reach across concurrent sessions.
- **`/pin` requires a restart** → rejected: `/pin` would visibly stop working at the exact moment
  people reach for it.

## Decisions (locked)
- Pin captured at **SessionStart only**; never changes mid-session except via `/pin --session`.
- Divergence emits **one breadcrumb line** when cwd and pin disagree (visible to the model, not
  printed to the user).
- **`session_id` is exposed** in `<memory:active>` so `/pin` can target the live session
  deterministically, without touching other sessions' state.
- Executors and subagents keep **cwd-based resolution**. Probe (2026-07-20) established that
  `UserPromptSubmit` never fires for Claude subagents and they receive **no** memory injection at
  all, so a session-keyed pin cannot leak into delegated work.
- Antigravity's `AI_MEMORY_PROJECT` env leak is **out of scope** — separate task.

## Phases

### Phase 1 — probe + path helper
- Verify whether Codex supplies `session_id` on its hook stdin. If it does, Codex inherits this
  feature and needs coverage; if not, it no-ops. Do not assume either way.
- Add `session_pin_file` to `hooks/lib.sh`.

### Phase 2 — write the pin
- `session_start_memory.sh`: write on the non-compact path under `hook_chunk_is_first`; prune
  `*.project` older than 7 days.
- Tests: written once across 12 invocations; compact path writes none; nothing written when no
  project resolves; prune spares fresh files.

### Phase 3 — read the pin
- `inject.sh`: pin wins when valid; validate the project dir exists; fall back otherwise.
- Tests: pin beats cwd; dead pin falls back; no `session_id` renders byte-identical to today.

### Phase 4 — breadcrumb surface
- `formatters/xml.sh` + `formatters/md.sh`: `session:` always, `pinned:` on divergence only.
- Tests: note present exactly once on disagreement, absent on agreement, both formats.

### Phase 5 — `/pin --session`
- `memory-pin.sh --session <id>`; update `commands/pin.md` to read `session:` from the breadcrumb
  and pass it, degrading with a clear message when absent.
- **Live exercise on the default path**: `/pin <other>` mid-session, confirm the next prompt's
  breadcrumb changed. Prose-command logic is not gated by any test in `scripts/tests/`.

### Phase 6 — docs + route
- `docs/harnesses/claude.md` breadcrumb table, `docs/scripts.md` if `--session` warrants a row,
  changelog fragment.
- Mutation-test each control before trusting green. Full local suite, then branch + PR
  (`scripts/`, `harnesses/`, `docs/`, `commands/` are all system).

## Risks / open questions
- **`session_id` becomes model-visible** — it can reach transcripts or a pasted commit message.
  Low harm, but a real consequence of the `/pin` decision.
- **Codex inherits this via shared `inject.sh`** — Phase 1 resolves whether that means untested
  coverage or a no-op.
- A pin does not survive a project **rename**; criterion 6's fallback catches it, but the session
  silently reverts to cwd behaviour.
- Two extra breadcrumb lines per prompt (one always, one conditional) — small against the
  10,000-char chunk cap, but it is per-prompt forever.
- Pruning can delete the pin of a session older than the retention window; it degrades to cwd
  resolution rather than failing, but the protection quietly disappears.
