---
plan: port-v2-improvements
status: done
created: 2026-06-03
completed: 2026-06-03
owner: orchestrator
---

# Port v2 memory-system improvements into the live system

Source spec: `/Users/seyi/Downloads/memory-v2.md`. Port the patterns that matured in the
single-agent variant back into this dual-agent (Claude + Codex) system. Four batches,
independent of each other.

## Batch A — Hook fixes (`inject_memory.sh`)

Fixes a real concurrent-session bug + moves to the supported injection channel.

- **Per-session markers.** Replace the single shared `~/.claude/memory_last_session` file
  with per-session marker files at `~/.claude/memory_sessions/<session_id>`. "First prompt"
  = marker absent. On first-prompt branch: write the marker (`: > "$marker"`) and
  opportunistically sweep markers older than 2 days
  (`find "$MARKDIR" -type f -mtime +2 -delete`).
- **`additionalContext` contract.** Stop `echo`ing blocks to stdout. Emit
  `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":<esc>}}`.
  Add a `json_escape` helper falling back `jq -Rs .` → `python3 -c json.dumps` → hand-rolled
  sed/awk. If nothing to inject, `exit 0` silent.
- Preserve existing block selection: identity/project/index once per session; working every
  prompt when non-empty.

## Batch B — Cross-project relationships (the capability)

`codex-mem.sh` already injects `memory.md` wholesale, so a `## Related Projects` table
reaches Codex for free. Work is: rule + scaffold + docs.

- **`identity.md`** — add the delegate-don't-load rule under Orchestration: when a task
  matches a `## Related Projects` row, do NOT load the sibling's `memory.md`; delegate
  sibling-scoped work to an executor (Codex `--executor`, Claude subagent fallback) with a
  self-contained prompt (points at `identity.md` + sibling `memory.md`, default deliverable
  = plan only). Plan-set execution: walk persisted plans in order, delegate each, pause at
  human/CI gates.
- **`_template/memory.md`** — append the commented-out `## Related Projects` block after the
  five required sections (HTML-commented so lint's section check stays inert until used).
- **`~/.claude/CLAUDE.md`** — short pointer to the cross-project model in the memory-system
  section.
- **README** — add the `## Cross-project relationships` section (distributed map,
  delegate-don't-load hop, delegation contract, plan-set execution).

## Batch C — Tests suite (`scripts/tests/`)

Dependency-free bash 3.2 tests; each sets `MEMORY_DIR` to a `mktemp -d` sandbox.

- `_assert.sh` — `assert_eq` / `assert_contains` / `assert_exit` / `finish`.
- `test_lib.sh`, `test_new_project.sh`, `test_regenerate_index.sh`, `test_lint_memory.sh`,
  `test_archive_cleanup.sh`, `test_codex_mem.sh` (AGENTS.md build order + `--executor`
  expansion), `test_inject_memory.sh` (additionalContext contract + marker behavior).
- Runner: `for t in scripts/tests/test_*.sh; do bash "$t"; done` — all pass.

## Batch D — Docs + scaffold-only

- **`new-project.sh`** — stop writing `.active_project` (pin-first). Update CLAUDE.md's
  "switch active project" note to pin-first; keep `.active_project` as optional fallback.
- **README** — add Domain-vs-skill section, per-session-marker + additionalContext
  description in Auto-injection, `scripts/tests/` references, `## Related Projects` in File
  format conventions, troubleshooting rows (identity re-injected every prompt; cross-project
  delegate sees wrong project).

## Validation

- Run `scripts/tests/` → all pass.
- `scripts/lint-memory.sh` → exit 0.
- Pipe a fake UserPromptSubmit JSON into `inject_memory.sh` twice with same `session_id`:
  first emits identity, second omits it; confirm valid `additionalContext` JSON both times.
- Confirm `_template` still passes lint (commented block inert).
