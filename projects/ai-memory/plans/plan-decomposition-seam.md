---
plan: plan-decomposition-seam
status: in_progress
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

### Phase 0 — Refresh this plan against `main` — DONE 2026-09-08
The plan was authored while the checkout was detached at `v1.4.0`, 7 commits behind `origin/main`.
Re-derived every file reference at `1b81abb`.

- `orchestrator.template.md` → `templates/orchestrator.template.md` (`a0084a4`); root seed
  templates all moved.
- Phase 4's real surface re-measured: 43 hits / 14 tracked files + the gitignored
  `orchestrator.md`. Two new files found that the original list missed — `skills.toml` and
  `docs/knowledge-lifecycle.md`.
- Established the **skill-name vs. concept** distinction; `harnesses/claude/CLAUDE.md` is
  concept-only and stays.
- `test_skill_ratings.sh` identified as fixture-coupled, not prose.
- `lint-memory.sh` drift checked — does not affect Phases 1 or 5 (see Risks).
- Runner glob confirmed as `"$TESTS"/test_*.sh`, so the test-file rename stays in-suite.

**Depends:** none
**Verify:** every file path named in this plan resolves at `git rev-parse HEAD`. ✅

### Phase 1 — Per-phase criteria in the Task Contract — DONE 2026-09-08
**Correction found during execution:** the Task Contract is **not** in `identity.md` (2040 bytes,
no such section) — it lives in `orchestrator.md` → `### Task Contract`, seeded from the tracked
`templates/orchestrator.template.md`. Both copies had to change: the template ships to consumers,
the live file is gitignored per-instance. `docs/workflow.md:34` already cited the right location;
`commands/new-plan.md` cited `identity.md` **twice** (lines 27, 46) — a third stale cross-reference
in the same family as the `status: active` bug, fixed here.

- Added four bullets to the Task Contract in `templates/orchestrator.template.md` **and** the live
  `orchestrator.md`: two-level criteria (plan + phase), validate-per-phase rather than only
  terminally, and the rule that a phase whose `**Verify:**` cannot be written is mis-drawn.
- `commands/new-plan.md`: scaffold now emits a `**Verify:**` line under `### Phase 1`; the
  `## Success criteria` guidance now says plan-wide and points per-phase criteria at the phase
  line; both `identity.md → Task Contract` references corrected to `orchestrator.md`.

**Depends:** Phase 0
**Verify:** `lint-memory.sh` clean for these files ✅; `Two levels: plan and phase` present in both
`orchestrator.md` and `templates/orchestrator.template.md` ✅; scaffold emits `**Verify:**` ✅;
zero remaining `identity.md → Task Contract` references ✅; full suite 50/50 green ✅ (under the
signing workaround below).

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
- **Bug fix, found 2026-09-08:** `commands/start.md` Step 3 instructs writing `status: active`
  into plan frontmatter, but `lint-memory.sh` rejects `active` (valid: `draft`, `in_progress`,
  `done`). Every plan `/start` has ever scaffolded is born lint-dirty —
  `platform-charts/automate-chart-docs-in-ci.md` and
  `platform-sandbox/platform-overview-dashboard.md` both carry it. Change Step 3 to
  `status: in_progress` and fix those two plans. Folded in here rather than shipped as its own
  PR because this phase already edits `start.md`.
  - **Executed:** three plans carried it, not two — `git-cli/cut-the-first-release.md` was below
    the `tail` cutoff when the list was first drawn. Exactly the truncation failure this project
    already records; the sweep must be a full grep, not a paged read. Lint 19 → 16 warnings.

**Depends:** Phase 1
**Verify:** a scaffolded plan emits both `**Verify:**` and `**Depends:**` per phase; `start.md`
documents the mirror; `_template/todo.md` documents the annotation.

### Phase 4 — Rename `brainstorming` → `design-brainstorm`

**Rename the skill, not the concept.** Two kinds of reference exist and only one moves:
the **skill name** (`skills/brainstorming/`, "invoke the **brainstorming** skill") renames; the
**concept** ("the brainstorm gate", "executors never brainstorm", "a brainstorm is an activity")
stays. A blind `sed` over-rewrites — `harnesses/claude/CLAUDE.md` is concept-only and must not
change.

- `git mv skills/brainstorming skills/design-brainstorm` (preserving `self-rating.md`).
- Update **skill-name** references in the 12 tracked files below (hit counts re-derived at
  `1b81abb`; treat as a floor, re-grep before editing):

  | File | Hits | Note |
  |---|---|---|
  | `scripts/tests/test_skill_ratings.sh` | 14 | **the hard one** — see below |
  | `commands/start.md` | 4 | also gets the `status: active` fix (Phase 3) |
  | `docs/harnesses/claude.md` | 3 | |
  | `docs/task-provider.md` | 3 | |
  | `templates/orchestrator.template.md` | 3 | **moved from repo root in `a0084a4`** |
  | `docs/workflow.md` | 2 | |
  | `skills/brainstorming/SKILL.md` | 2 | moves with the dir |
  | `skills.toml` | 2 | comments citing it as the authored-not-remote example |
  | `scripts/tests/test_brainstorming_skill_tracking.sh` | 5 | + rename the file itself |
  | `README.md` | 1 | |
  | `commands/new-plan.md` | 1 | |
  | `docs/install.md`, `docs/knowledge-lifecycle.md`, `docs/showcase.md` | 1 each | |

- **`scripts/tests/test_skill_ratings.sh` is not a text substitution.** It uses `brainstorming` as
  a *live fixture*: `seed_skill brainstorming`, then `cp`/`cmp`/`grep` against
  `$MEM/skills/brainstorming/SKILL.md` across 14 sites. The fixture identity changes with the
  rename; re-read the file and edit it deliberately rather than sedding it.
- **`test_brainstorming_skill_tracking.sh` asserts a negative** —
  `assert_not_contains templates/skills.toml.example "brainstorming"`. After the rename that
  assertion must test the *new* name, or it passes vacuously forever.
- Rename the test file to `test_design_brainstorm_skill_tracking.sh`. The runner globs
  `"$TESTS"/test_*.sh` (`run-tests.sh:87,167`), so the new name is still reached — **confirm this
  empirically** rather than trusting the glob read.
- Update the **gitignored per-instance `orchestrator.md`** (3 hits) alongside its tracked seed
  `templates/orchestrator.template.md`. `git grep` cannot see it; it will not show up in any
  tracked-file sweep.
- Re-run `scripts/link-skills.sh` and confirm the old `~/.claude/skills/brainstorming` symlink is
  pruned, not stranded — this tree's own gotcha is that a link whose source vanished is never
  revisited.
- Do **not** touch: `CHANGELOG.md` (history), `projects/*/archive/**`, `.skill-cache/`, or
  `projects/ai-memory/investigations/on-demand-project-load.md` (a historical record of what was
  true when written). `harnesses/claude/CLAUDE.md` is concept-only — leave it.

**Depends:** Phase 0
**Verify:** *(corrected during execution — the original said `grep brainstorming orchestrator.md`
must return nothing, which contradicts the skill-name-vs-concept rule decided in this same phase.
The activity is still called brainstorming, so prose hits are expected and correct.)*
- no **skill-name** references remain: `git grep '`brainstorming`'` (backticked) and
  `git grep 'invoke the \*\*brainstorming\*\*'` both empty; surviving bare-word hits are the
  activity ("skip brainstorming", "executors never brainstorm") and are intentional ✅
- `~/.claude/skills/` shows `design-brainstorm`, the old link pruned, nothing dangling ✅
- `run-tests.sh` full, green, file count reconciled ✅
- the `.gitignore` negation control is **mutation-tested in both directions** ✅

### Phase 5 — Record expand–contract sequencing
- Add an expand–contract entry (add new form alongside old → migrate call sites in batches →
  delete old; each phase green independently) to `domain/terraform.md`, cross-referenced from
  `domain/helm.md`.

**Depends:** none
**Verify:** `scripts/lint-memory.sh` passes; `/reindex` leaves `index.md` unchanged (no new
domain file was created).

### Checkpoint — before shipping

> **The suite cannot go green on this machine unmodified** (found in Phase 1). Fixtures inherit
> the developer's global git config, and `commit.gpgsign`/`tag.gpgsign=true` breaks 44 assertions
> across `test_release`, `test_sync_channels`, `test_assemble_changelog` with errors that read as
> release-logic bugs. Until task `isolate-test-fixtures-from-the-developer-s-global-git-config`
> lands, run the suite as:
> ```
> GIT_CONFIG_COUNT=2 \
>   GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false \
>   GIT_CONFIG_KEY_1=tag.gpgsign    GIT_CONFIG_VALUE_1=false \
>   ./scripts/run-tests.sh
> ```
> Reconciliation note: `run-tests.sh` prints **53** `PASS`/`FAIL` lines but reports
> `tests: 50 passed` — the extra 3 are the python `unittest`, `check-docs`, and `shellcheck`
> gates, which sit outside the bash-file counter. 53 vs 50 is correct, not a truncation.

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

- **Phase 4's blast radius was under-estimated twice, and it is not purely mechanical.** Chosen on
  an estimate of ~3 files; the first correction said 12 + 2 tests; Phase 0 measured **43 hits
  across 14 tracked files, plus 3 in the gitignored `orchestrator.md`** that no tracked-file sweep
  can see. More importantly, `test_skill_ratings.sh` (14 hits) uses `brainstorming` as a live
  *fixture*, not as prose — so the phase contains real editing, not find-and-replace. The decision
  still holds, but this is now the largest phase by some margin. Fallback if it turns noisy
  mid-flight: the `orchestrator.md` disambiguation rule, accepting that it competes with the
  SessionStart injection. **Three successive estimates were low — do not size this phase again
  without re-grepping.**
- **Checked and clear:** `f3bd068` changed `lint-memory.sh`, but only to narrow two false
  positives (skip `domain/_template.md` in the orphan check; skip placeholder-only `working.md` in
  the staleness check). Frontmatter validation is untouched, so the `lint-memory.sh`-based
  `**Verify:**` lines in Phases 1 and 5 stand as written.
- **Nothing executable gates a prose command.** Phases 2 and 3 change `/new-plan` and `/start`,
  which no test in `scripts/tests/` runs. The checkpoint's live end-to-end exercise on the
  *default* path is the only real gate.
- **`superpowers:writing-plans` remains an unreferenced parallel answer** to Phase 2. Deliberately
  not wired in, per the Design rationale. Revisit only if the plugin is ever vendored.
- **Out of scope, capture separately:** the local task provider appears not to enforce the
  500-char `summary` cap — the existing `author-dd-k8s-skill-…` backlog record carries a
  multi-thousand-character summary. Unverified; worth its own task.
