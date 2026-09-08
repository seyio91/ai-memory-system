---
plan: plan-decomposition-seam
status: active
created: 2026-09-08
owner: claude (orchestrator)
task_provider: local
task_ref: close-the-plan-decomposition-seam-in-the-tier-3-pipeline
---

# Plan — Close the plan-decomposition seam in the Tier-3 pipeline

## Goal

`/new-plan` defers decomposition to `## Phases` but no rule anywhere states *how* to decompose,
and the Task Contract puts success criteria at plan level only — so a multi-phase plan gets one
terminal Validator pass and a phase-2 defect surfaces only after phase 6 is built on it. Give the
pipeline a decomposition rule, per-phase criteria, and declared dependency edges, and remove the
duplicate `brainstorming` skill name while in there.

## Success criteria

- `identity.md` → Task Contract states that plan-tier work carries **per-phase** checkable
  criteria, not only plan-level ones.
- `commands/new-plan.md` scaffold emits a `**Verify:**` line and a `**Depends:**` line under each
  `### Phase N`, and carries a Step 3.5 decomposition rule (sizing bar, dependency ordering,
  checkpoint placement).
- `commands/start.md` mirrors declared dependencies onto the `todo.md` checkboxes it appends, as
  `(needs: Pn)`.
- The in-tree brainstorming skill resolves to a single unambiguous name; no tracked, non-archive
  file still points at the old name for *invocation* purposes.
- `scripts/run-tests.sh` passes in full, with the reported `tests: N passed` counter reconciled
  against the printed file count (not a `tail`-truncated view).
- A `changelog.d/<id>.<kind>.md` fragment exists for the change.
- No file under `projects/*/archive/` is modified.

## Design

**Chosen approach** — four independent edits to the existing pipeline, no new skill, no new
artifact type. Findings and rejected external skills are recorded in the investigation
`planning-decomposition-seam`.

- **Decomposition rule lives inline in `/new-plan` as Step 3.5.** Self-contained, versioned with
  the tree, visible to the repo's own gates.
  - *Alternative — a new `plan-decomposition` skill* → rejected: an extra indirection at the exact
    moment `/new-plan` already has the file open.
  - *Alternative — reference `superpowers:writing-plans`* → rejected: binds the pipeline to a
    cached plugin version this tree does not control and cannot gate. Per the recorded lesson, a
    doctrine contradiction across a repo boundary is structurally invisible to any check that runs
    here.
- **Phase criteria as a `**Verify:**` line per phase.** Smallest diff to the scaffold, greppable,
  gives the Validator an unambiguous anchor.
  - *Alternative — nested sub-bullets* → rejected: blurs steps and criteria.
  - *Alternative — a separate `## Phase criteria` table* → rejected: two edit sites per phase, so
    it rots.
- **Dependency edges declared in the plan, mirrored into `todo.md`.** `**Depends:** Phase N` is
  the design record; `(needs: Pn)` on the checkbox is what an orchestrator resuming after
  compaction actually reads.
  - *Alternative — plan only* → rejected: `todo.md` is what gets read on resume.
  - *Alternative — todo only* → rejected: the design artifact loses the rationale.
- **Rename `skills/brainstorming/` → `skills/design-brainstorm/`.** Removes the collision with
  `superpowers:brainstorming` by construction rather than by a rule that competes with the
  SessionStart `using-superpowers` injection.
  - *Alternative — a disambiguation rule in `orchestrator.md`* → rejected: loses to an injection
    marked EXTREMELY_IMPORTANT.
  - *Alternative — disable `superpowers:brainstorming`* → rejected: a plugin update silently
    re-registers it.

**Verification loop for this repo** is `scripts/run-tests.sh` + `scripts/lint-memory.sh` — not a
TDD step cycle. Phases are sized to one executor delegation each.

## Decisions (locked)

- No external skill is installed. Neither `planning-and-task-breakdown` nor `to-tickets` is
  adopted; the useful findings are extracted into existing files.
- No new artifact type. Plans, todos, investigations, and tasks remain the only four.
- Nothing is published into the task provider beyond the existing single task record.
- **Commit route: branch + PR.** This touches `commands/`, `skills/`, `docs/`, and
  `scripts/tests/` — all shipped surface — so it is a system change regardless of diff size. The
  `projects/ai-memory/**` bookkeeping in Phase 6 is housekeeping and may go straight to `main`.
- **No worktree.** This meta-project forks its own memory tree under a worktree while
  `MEMORY_DIR` stays pinned to the main checkout; the change spans engine code *and* memory
  bookkeeping, so it stays in the main checkout.
- Phases 4 and 5 are independent of 1–3 and of each other — safe to parallelize across executors.

## Phases

### Phase 1 — Per-phase criteria in the Task Contract
- Extend the Task Contract section of `identity.md`: plan-tier work carries per-phase checkable
  criteria in addition to the plan-level set; the Validator may be invoked per phase.
- Extend the `commands/new-plan.md` Step 3 scaffold so each `### Phase N` emits a `**Verify:**`
  line, with template guidance that a criterion must be checkable by reading output, running a
  command, or inspecting state.

**Depends:** none
**Verify:** `scripts/lint-memory.sh` passes; `identity.md` contains the per-phase wording; a
freshly scaffolded plan file contains a `**Verify:**` line under its phase heading.

### Phase 2 — Decomposition rule as `/new-plan` Step 3.5
- Insert Step 3.5 into `commands/new-plan.md`, between the scaffold write and the user prompt.
- Content: the sizing bar (one phase = one executor delegation; split when it spans two
  independent subsystems, when the title needs an "and", or when its criteria exceed ~3 bullets),
  dependency ordering (foundations first, high-risk early), and checkpoint placement at the
  human/CI gates `orchestrator.md` already names — PR merges and `terraform`/`kubectl` applies.
- Renumber the existing Step 4 / Step 5 prose and any cross-references to them.

**Depends:** Phase 1
**Verify:** `commands/new-plan.md` contains Step 3.5 with all three rules and no duplicated or
skipped step numbers; the step sequence is read end-to-end once to confirm no step is orphaned
(the `/plan-archive` "skip to Step 8" defect is the failure mode being guarded against here).

### Phase 3 — Declared dependency edges
- Add a `**Depends:**` line to the `### Phase N` scaffold in `commands/new-plan.md`.
- Update `commands/start.md` Step 4 so the `todo.md` items it appends carry `(needs: Pn)` mirrored
  from the plan's `**Depends:**` lines.
- Update `projects/_template/todo.md` guidance to document the `(needs: Pn)` convention.

**Depends:** Phase 1
**Verify:** a scaffolded plan emits both `**Verify:**` and `**Depends:**` per phase; `start.md`
documents the mirror; `_template/todo.md` documents the annotation.

### Phase 4 — Rename `brainstorming` → `design-brainstorm`
- `git mv skills/brainstorming skills/design-brainstorm` (preserving `self-rating.md`).
- Update invocation references in: `orchestrator.template.md`, the live `orchestrator.md`,
  `commands/new-plan.md`, `commands/start.md`, `README.md`, `docs/workflow.md`,
  `docs/harnesses/claude.md`, `docs/install.md`, `docs/knowledge-lifecycle.md`,
  `docs/showcase.md`, `docs/task-provider.md`, and `projects/ai-memory/memory.md`.
- Rename `scripts/tests/test_brainstorming_skill_tracking.sh` and update the skill name inside it
  and inside `scripts/tests/test_skill_ratings.sh`.
- **Confirm the renamed test file is still reached by the runner's glob** before trusting a green
  run — a test the glob misses is silently ungated.
- Re-run `scripts/link-skills.sh` and confirm the old symlink in `~/.claude/skills/` is pruned,
  not left dangling.
- Do **not** touch `CHANGELOG.md` (history) or anything under `projects/*/archive/`.

**Depends:** none
**Verify:** `grep -rn 'brainstorming' --include='*.md' --include='*.sh'` over the tree returns
hits only in `CHANGELOG.md`, `archive/`, `.skill-cache/`, and the
`planning-decomposition-seam` investigation; `run-tests.sh` passes with its file count reconciled
against `tests: N passed`; `ls -l ~/.claude/skills/` shows `design-brainstorm` and no dangling
`brainstorming` link (corroborated with `find`, not a bare `ls`).

### Phase 5 — Record expand–contract sequencing
- Add an expand–contract entry (add new form alongside old → migrate call sites in batches →
  delete old; each phase green independently) to `domain/terraform.md`, cross-referenced from
  `domain/helm.md`.

**Depends:** none
**Verify:** `scripts/lint-memory.sh` passes; `/reindex` leaves `index.md` unchanged (no new
domain file was created).

### Checkpoint — before shipping
- [ ] Full `scripts/run-tests.sh` run, file count reconciled against the summary counter
- [ ] `scripts/lint-memory.sh` clean
- [ ] A scaffolded throwaway plan exercised end-to-end through `/new-plan` on its **default**
      path — prose commands are not covered by any executable test
- [ ] Human review before the PR opens

### Phase 6 — Ship
- Write the `changelog.d/<id>.<kind>.md` fragment (`feature`) while the reasoning is live.
- `git-cli ship` for the system change (branch + PR). **Do not merge.**
- Housekeeping — tick `todo.md`, `/plan-done`, `/plan-archive` (which also archives the linked
  investigation), `taskctl set-status <ref> done` — goes straight to `main` via
  `git-cli commit --all` + `git push`.

**Depends:** Phases 1, 2, 3, 4, 5
**Verify:** the fragment exists and names the right kind; the PR is open with CI green; the task
ref reports `done`; `plans/plan-decomposition-seam.md` has moved to `archive/plans/`.

## Risks / open questions

- **Phase 4's blast radius was under-estimated at decision time.** The rename was chosen on an
  estimate of ~3 files; the real surface is 12 markdown files plus 2 test files. The decision
  still holds — the churn is mechanical and entirely in-tree — but if it proves noisier than
  expected, the documented fallback is the `orchestrator.md` disambiguation rule, accepting that
  it competes with the SessionStart injection.
- **Nothing executable gates a prose command.** Phases 2 and 3 change `/new-plan` and `/start`,
  which no test in `scripts/tests/` runs. The checkpoint's live end-to-end exercise on the
  *default* path is the only real gate.
- **`superpowers:writing-plans` remains an unreferenced parallel answer** to Phase 2. Deliberately
  not wired in, per the Design rationale. Revisit only if the plugin is ever vendored.
- **Out of scope, capture separately:** the local task provider appears not to enforce the
  500-char `summary` cap — the existing `author-dd-k8s-skill-…` backlog record carries a
  multi-thousand-character summary. Unverified; worth its own task.
