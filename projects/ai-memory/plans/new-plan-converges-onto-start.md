---
plan: new-plan-converges-onto-start
status: in_progress
created: 2026-09-09
owner: claude (orchestrator)
task_provider: local
task_ref: 3d6f6850-c619-818a-a5a4-f9a116870a5c
---

# Plan — /new-plan converges plan-first work back onto /start

## Goal
`/new-plan` is a second entry point into plan-tier work that skips the task lifecycle, so plan-first work leaves its task in `backlog` or absent — 8 of 10 live plans carry no `task_ref`. Give `/new-plan` a `--task`/`--no-task` surface that runs the same linking step as `/start` from one shared source, and add a lint rule so an unlinked plan is detected rather than silently normal.

## Success criteria
- `/new-plan <slug> --task <ref>` writes `task_ref` + `task_provider` frontmatter, sets plan `status: in_progress`, pushes the drafted Goal back via `taskctl update`, flips the task to `started`, and appends a `todo.md` entry with per-phase checkboxes carrying `(needs: Pn)`.
- `/new-plan <slug> --no-task` writes `task_ref: none` and makes zero `taskctl` calls.
- `/new-plan <slug>` with neither flag asks exactly once (paste ref / capture now / plan-only) and each of the three answers reaches its documented outcome; live-exercised on the plan-only path.
- `/new-plan <slug> --task <ref>` where the task's `project` differs from the active project aborts without writing frontmatter and names `/start <ref>` as the route.
- `bash scripts/apply-partial.sh --file <path> --partial task-link` injects the block; a second run is a byte-identical no-op; first injection without `--force` is refused; `--skill` + `--file` together exits 2; a path outside `MEMORY_DIR` is refused.
- The injected block in `commands/new-plan.md` and `commands/start.md` is byte-identical to `scripts/partials/task-link.md` — proven by a test, not by inspection.
- `lint-memory.sh` WARNs on a live plan with no `task_ref`, stays silent on `task_ref: none` and on a real ref, and never warns on `archive/plans/`. Mutation-tested: deleting the rule fails the tests.
- Rule 10 does not treat `task_ref: none` as a matchable ref.
- Full suite green under `/bin/bash` 3.2 with the printed file count reconciled against `tests: N passed`; lint baseline unchanged at 18 WARNs.

## Design
Chosen: a shared partial plus a flag-driven trigger plus a detection rule — three layers, each covering what the others structurally cannot.

- **`scripts/partials/task-link.md`** is the single source of the linking prose: resolve ref → ensure `task_ref`/`task_provider` frontmatter and plan `status: in_progress` → `taskctl update <ref> --summary "<Goal>"` → `taskctl set-status <ref> started` → append the `todo.md` entry. Written idempotently on the frontmatter step so `/start`, which already stamps `task_ref` at scaffold time, no-ops there.
- **`apply-partial.sh` gains `--file <path>`** beside `--skill`, reusing the existing marker, force-on-first-injection and `--all` re-sync semantics. `--all` must enumerate carriers across `commands/*.md` as well as `skills/*/SKILL.md`. Mutually exclusive with `--skill`; target path must resolve inside `MEMORY_DIR`.
- **`/new-plan` takes `--task <ref>` / `--no-task`**, and asks once when neither is given. The linking step runs *after* today's Step 4 (Goal drafted), because the summary pushed to the backend must be the real Goal, not a placeholder; it replaces today's Step 5, which only reminds the user to add a todo checkbox.
- **`/start` Step 4's body is replaced by the injected block**, so the two entry points cannot drift.
- **Lint rule 12** WARNs on a live plan with no `task_ref`; `task_ref: none` is the explicit opt-out that makes plan-only a recorded decision rather than an omission.

Alternatives considered:
- Backlog title-similarity matching instead of flags → rejected: fuzzy matching in prose no test can gate, and a wrong match silently links the wrong ref.
- Always-ask with no flags → rejected: same prompt on the default path, but nothing scriptable and no explicit plan-only record.
- `/new-plan` referencing `commands/start.md → Step 4` by prose → rejected: a Step renumber in `/start` silently breaks it.
- Duplicating the linking prose into `/new-plan` → rejected: guaranteed drift, against this tree's doc-rot doctrine.
- Lint rule with no opt-out marker → rejected: plan-only stops being legitimately possible and the 8 legacy plans become permanent noise.
- No lint rule at all → rejected: if the prompt is skipped or the command edited, the gap returns silently — the exact failure that produced this task.

## Decisions (locked)
- Detection is flag-driven (`--task` / `--no-task`), with a single ask as the unflagged default.
- The linking step lives in one partial, injected into both commands; neither command owns a private copy.
- Plan-only is explicit: `task_ref: none`, not an absent field.
- `/new-plan` stays active-project-scoped. A cross-project `--task` aborts and redirects to `/start`.
- The 8 existing unlinked plans are stamped `task_ref: none` in the same change, holding the lint baseline at 18.
- Phases 1-3 and Phase 4 are independent and can be fanned out in parallel.

## Phases

### Phase 1 — `apply-partial.sh --file` target mode
- Add `--file <path>` beside `--skill`; reject both together (exit 2); resolve and contain the path inside `MEMORY_DIR`.
- Teach `--all` to enumerate carriers across `commands/*.md` in addition to `skills/*/SKILL.md`.
- New `scripts/tests/test_apply_partial.sh`; wire it into `run-tests.sh`'s glob.
- Add/refresh the `docs/scripts.md` entry for the new flag.

**Depends:** none
**Verify:** `--file` injects with `--force` and is refused without it; a second run leaves the target byte-identical; `--skill`+`--file` exits 2; a path outside `MEMORY_DIR` is refused; the new test file appears in the run's printed file list and the `tests: N passed` total rises by its assertion count.

### Phase 2 — author and inject the `task-link` partial
- Write `scripts/partials/task-link.md` with the full linking prose (ref resolution, idempotent frontmatter, `taskctl update`, `set-status started`, `todo.md` entry with `(needs: Pn)`).
- Inject into `commands/new-plan.md` and `commands/start.md` via `apply-partial.sh --file ... --force`.
- Add the drift gate asserting both injected blocks match the source byte-for-byte.

**Depends:** Phase 1
**Verify:** both command files carry the `<!-- partial:task-link START ... -->` block; the drift test passes, and mutating one injected copy by a single character fails it.

### Phase 3 — command surfaces
- `/new-plan`: parse `--task <ref>` / `--no-task`, reject both; the unflagged ask (paste ref / capture now / plan-only); cross-project abort naming `/start`; `taskctl get` error surfaced before any write; Goal >500 chars condensed, never mid-word truncated; linking placed after Step 4, replacing Step 5.
- `/start`: replace Step 4's body with the injected block, keeping Step 3's scaffold-time `task_ref` write.
- `changelog.d/<id>.feature.md` fragment.

**Depends:** Phase 2
**Verify:** live exercise of `/new-plan` on the unflagged plan-only path and on `--task <ref>` produces the frontmatter, backend state and `todo.md` entry the success criteria name; `/start`'s Step 4 contains no prose outside the managed block.

### Phase 4 — detection rule
- `lint-memory.sh` rule 12: live plan under `projects/*/plans/` with no `task_ref` → WARN; `task_ref: none` suppresses; `archive/plans/` exempt.
- Teach rule 10 to skip `none` rather than treat it as a matchable ref.
- Stamp `task_ref: none` on the 8 existing unlinked plans.
- Seeded-defect tests in `test_lint_memory.sh`, both directions.

**Depends:** none
**Verify:** rule 12 fires on a seeded unlinked plan and is silent on `none`, on a real ref, and on an archived plan; deleting the rule body fails the new tests; a full `lint-memory.sh` run still reports 18 WARNs.

### Checkpoint — pre-PR gate
- Full suite under `/bin/bash` 3.2, printed file count reconciled against `tests: N passed` (no `| tail`).
- `lint-memory.sh` at baseline 18.
- Live exercise of `/new-plan` on its **default** path and `/start` on a real task.
- Human review, then branch + PR (system change: `scripts/`, `commands/`, `docs/`). Plan/todo/memory edits are housekeeping and ride whichever route the artifacts were born on.

## Risks / open questions
- `--file` widens `apply-partial.sh` from SKILL.md files to arbitrary paths; the `MEMORY_DIR` containment guard is the only thing standing between it and an arbitrary file rewrite.
- The unflagged ask adds friction to every `/new-plan`; if it gets skipped in practice, rule 12 is the backstop — that division of labour is the design, not a fallback.
- `task_ref: none` is new frontmatter vocabulary; any future ref-matching rule must treat it as a non-ref.
- Rule 12 raises the lint baseline 18 → 26 unless the 8 legacy plans are stamped in the same change.
- No executable test reaches prose commands — Phases 2 and 3 are gated only by the drift test plus live exercise.
