---
plan: archive-investigation-on-task-done
status: active
created: 2026-07-18
owner: claude (orchestrator)
task_provider: notion
task_ref: 39ef6850-c619-80b7-af64-c2f96d9635a2
---

# Archive investigation when a task is done

## Goal
Make `investigations/` reflect only *live* work: when a plan is archived, its linked
investigation moves to `archive/investigations/` in the same step, and `lint-memory`
flags any live investigation whose work has already shipped.

## Success criteria
1. `/plan-archive <slug>` moves the plan **and** its linked investigation, resolving the link
   by the plan's frontmatter `task_ref` first, falling back to a same-slug filename match.
2. When no investigation is linked, `/plan-archive` behaves exactly as today (no error, no noise).
3. When an investigation is found but `archive/investigations/<slug>.md` already exists,
   `/plan-archive` aborts the investigation move, reports it, and still archives the plan.
4. `lint-memory` emits a WARN for a live `investigations/<slug>.md` whose `task_ref` matches a
   plan already in `archive/plans/` (work shipped, investigation left behind).
5. `scripts/tests/test_lint_memory.sh` covers the new rule: one stale fixture warns, one live
   fixture (plan still in `plans/`) does not.
6. `scripts/run-tests.sh` passes; `scripts/check-docs.sh` passes.
7. The existing real-world offender — `projects/ai-memory/investigations/executor-output-normalization.md`,
   whose plan is already in `archive/plans/` — is archived as part of this work.

## Design
**Extend `/plan-archive`** rather than adding a command. `docs/task-provider.md` already states the
doctrine — an investigation moves "when the task closes and the consuming plan has shipped … same
trigger and same convention as plan archival" — so the trigger is settled; only the mechanism is
missing. Piggybacking on the existing step means nothing new to remember, and forgetting is precisely
the current failure mode.

Link resolution is `task_ref`-first because the plan slug and investigation slug are not guaranteed
equal (`on-demand-project-load` is an investigation whose plan may land under a different name);
same-slug fallback covers investigations written before the `task_ref` convention landed.

`lint-memory` gets a companion rule so the stale state is *detectable* rather than dependent on the
archival step having fired — including for investigations that never produced a plan under the same
name. The staleness signal is purely local (a matching `task_ref` in `archive/plans/`); it does **not**
call the task provider, keeping lint offline and fast.

Rejected:
- *New `/investigation-archive` command* — adds a surface the user must remember; the doctrine already
  binds the move to plan archival.
- *Both (command + hook)* — the orphan case (investigation whose task closed with no plan) is covered
  well enough by the lint warning plus a manual `mv`; a whole command for it is unearned.

## Decisions (locked)
- Trigger: `/plan-archive`, same invocation, no new command.
- Link resolution: frontmatter `task_ref` match, then same-slug filename fallback.
- Lint staleness signal: `task_ref` present in a file under `archive/plans/`. No provider call.
- Collision at the destination never blocks the plan's own archival.

## Phases
- [ ] **Phase 1 — `/plan-archive` extension.** Add the investigation-resolution + move steps to
      `commands/plan-archive.md` (resolve by `task_ref`, fall back to slug; collision handling;
      report both moves).
- [ ] **Phase 2 — lint rule.** Add rule 10 to `scripts/lint-memory.sh`: live investigation whose
      `task_ref` matches a plan in `archive/plans/` → WARN.
- [ ] **Phase 3 — tests.** Extend `scripts/tests/test_lint_memory.sh` with stale + live fixtures;
      run `scripts/run-tests.sh`.
- [ ] **Phase 4 — docs + changelog.** Update `docs/task-provider.md` (name the mechanism, not just
      the convention) and add a `changelog.d/` entry; run `scripts/check-docs.sh`.
- [ ] **Phase 5 — clear the backlog offender.** Archive
      `investigations/executor-output-normalization.md` via the new flow.

## Risks / open questions
- Commands are model-executed markdown, so Phase 1 has no unit test — its correctness rests on the
  prose being unambiguous. Phase 5 doubles as its live exercise.
- A plan archived *before* its investigation's task closes would move the investigation early. Judged
  acceptable: plan archival already implies the work shipped, and the file remains resolvable by name
  in `archive/`.
- Investigations predating the `task_ref` convention rely on the slug fallback; a mismatched slug is
  silently skipped (the lint rule is the backstop).
