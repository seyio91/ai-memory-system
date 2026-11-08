---
plan: verification-contract
status: in_progress
created: 2026-11-08
owner: claude (orchestrator)
task_provider: notion
task_ref: 402f6850-c619-816e-88b1-f0649303e7d5
---

# Plan — Verification contract: plan template, criterion modes, evidence discipline

## Goal
Make a plan state what it must prove, and make every gate read that statement instead of guessing. `/new-plan` and `/start` scaffold R-id criteria tagged `[acceptance]`/`[parity]`, per-phase `Files touched` / `Risk` / `Verify`-cites-R, `## Non-goals` and a before/after block; lint, a drift script, a feasibility brief and the validator all consume the plan; doctrine carries the evidence rule and the executor `diverged:` line.

**Before:** criteria are free prose; nothing checks a Verify line names what it proves; drift from the plan surfaces at validation round 3 or never; parity is proven against baselines kept in a scratchpad that vanish; a PASS can be a sentence with no evidence behind it; the validator is told to check nothing beyond the criteria, so a plan whose criteria all pass while missing its Goal ships.
**After:** a plan scaffolded on or after the cutover passes rule 20; the feasibility brief rejects a plan naming a missing file before the first delegation; `check-plan-drift.sh` names any file outside `Files touched` at the pre-PR final pass; every `[parity]` criterion names a re-runnable reference (a git ref or a baseline dir on disk); the validator blocks a plan whose evidence misses its Goal, and no PASS stands on a bare assertion; every executor return ends with `diverged:`.

Seed: investigation `plan-template-and-authoring-checks` (merged tasks `40bf6850-c619-8188-9328-e930e646cf55` verification modes, `3dbf6850-c619-8197-addf-fc26738653ab` evidence discipline).

## Non-goals
- No new skill for evidence discipline (doctrine + `validator.md` instead).
- No lint of prose quality (before/after wording, risk justification, parity tolerance wording).
- No lint ERROR; no retro-fit of plans created before the cutover (18 pre-template `in_progress` plans across 12 projects stay unlinted).
- No drift check at `/plan-done` — it runs post-merge, where drift is unactionable and the default range is empty.
- No change to Part B defect classes or grading.
- No `depends_on:` on plans, no activity-type phases, no ✅ marks in criteria (rejected in the investigation).

## Success criteria
- R1 [acceptance] The plan scaffold lives once in `scripts/partials/plan-scaffold.md`, carried by `/new-plan` and `/start` (two-carrier literal assert in `test_apply_partial.sh`); `apply-partial.sh` re-syncs an existing block in place, so syncing partials in any order leaves a carrier byte-identical; it contains every token in the Grammar block.
- R2 [acceptance] Rule 20 emits a `plan-contract:`-tagged WARN for each of checks (a)–(j) on its dirty sandbox plan (one `draft`, one `in_progress`), nothing on the clean one, and nothing for a non-conforming plan whose `created:` predates the cutover; a mutation test shows each check is load-bearing; this plan produces zero `plan-contract:` lines from `lint-memory.sh`.
- R3 [acceptance] `scripts/check-plan-drift.sh` exits 1 and names the file when the diff touches a path outside the union of `Files touched`, 0 when clean, 3 for a pre-cutover plan, 2 on any other failure; `--phase N` narrows to one phase; `--repo` and `--range` are required (exit 2 without them); a worktree whose HEAD differs from the primary checkout is diffed at the worktree's HEAD; when `--repo` shares the memory root's object store it ignores the plan's own `projects/<project>/**`.
- R4 [acceptance] `agents/plan-feasibility.md` carries read-only frontmatter; run through the validate role with `base:` set to the main SHA recorded before Phase 1, on copies of this plan it returns `REVISE` naming the path when an unmarked existing path is replaced by `does/not/exist.sh`, `REVISE` when a `(new)` path already exists, and `REVISE: not drafted` on a placeholder scaffold; on this plan (with `(new)` markers) it returns `READY` or `CAUTION` — including when re-run after P1/P4 have created the `(new)` files.
- R5 [acceptance] `/plan-archive` on a plan with `plans/<slug>.baseline/` and **no** linked investigation moves the dir to `archive/plans/<slug>.baseline/`; the same with a linked investigation moves both; a pre-existing destination is reported and nothing is overwritten.
- R6 [acceptance] `agents/validator.md`, `doctrine/orchestrator.md` and `docs/workflow.md` agree: Part A checks the criteria plus, only when the brief carries `goal_check: yes` (last phase's final pass), the Goal (`VERDICT: BLOCKED (goal)`); the final pass runs `check-plan-drift.sh`, exits 1/2 block and exit 3 is reported N/A; evidence is a command with output or a `file:line`, never a bare assertion. Live scenarios on a scratch fixture plan, verdicts pasted: (i) all criteria PASS, After state not shown, last phase `scope: final` + `goal_check: yes` ⇒ `BLOCKED (goal)`; (ii) same fixture, earlier phase `scope: final` without `goal_check` ⇒ no goal block; (ii-b) same, `scope: fix-round` ⇒ no goal block; (v) a pre-cutover fixture plan at final pass ⇒ drift and Goal both N/A, not BLOCKED; (iii) a criterion whose only support is the executor's "done" claim ⇒ FAIL; (iv) drift script forced to exit 2 ⇒ BLOCKED. doctrine carries the evidence rule and the `diverged:` line; `executor.sh --run` prepends the `diverged:` return rule; `bash scripts/check-docs.sh` and the full `bash scripts/run-tests.sh` gate pass.
- R7 [parity] vs `origin/main`: on the same tree at the same moment, `lint-memory.sh` from `origin/main` and from the branch produce identical line sets once lines containing `plan-contract:` are removed.

## Design
Approach 1 — plan-side contract. The plan body is the single source; everything else reads it.

- **S1 template.** Goal gains `**Before:** / **After:**`; new `## Non-goals`; criteria lines follow the Grammar block; `## Security` required when any phase is `Risk: high`; `## Design` gains a `**Builds on:**` line (references, no `depends_on`). Each `### Phase N — <name>` carries `**Files touched:**`, `**Risk:**`, `**Depends:**`, `**Verify:**`. Scaffold body moves to `scripts/partials/plan-scaffold.md`. `apply-partial.sh` today strips a block and re-appends it at EOF (`apply-partial.sh:83-97`), so re-syncing one partial reorders it past the others; P1 changes it to replace an existing block **in place** (append at EOF only on first injection). Steps reference blocks by section name, as Step 4/L1 already does for *Task linking*: `/new-plan` Step 3 and `/start` Step 3 say "write the scaffold in *Plan scaffold* below".
- **S2 lint rule 20** (WARN, every line prefixed `plan-contract:`) inside the existing `plans/*.md` walk at `lint-memory.sh:306`. Scope: `status: draft|in_progress` (authoring-time feedback is the point; `draft` is where it lands) and `created:` ≥ the cutover literal `2026-11-08`. Checks: (a) ≥1 R line; (b) each R line tagged; (c) every `**Verify:**` cites ≥1 existing R-id; (d) every R-id cited by ≥1 Verify; (e) each `### Phase N` has `Files touched`, `Risk`, `Depends` matching the Grammar, and exactly one `**Verify:**` citing ≥1 R-id; (f) `## Non-goals` present; (g) each `[parity]` line names `vs \`<ref>\`` or `baseline \`plans/<slug>.baseline/…\``, and a `baseline` form requires a `### Phase N — Baseline`; (h) any `Risk: high` ⇒ `## Security`; (i) `**Before:**` and `**After:**` present under `## Goal` (the final-pass Goal check reads `After`); (j) a live plan with no `created:` or one not matching `YYYY-MM-DD` ⇒ WARN, never silently out of scope (fail-closed; pre-cutover is only a well-formed date before the literal).
- **S3 feasibility brief** `agents/plan-feasibility.md` (frontmatter: name, description, `tools: Read, Grep, Glob, Bash`, model — it is symlinked as a Claude subagent type and `executor.sh:207` rejects a frontmatter-less brief). Invoked via `executor.sh --role validate --brief plan-feasibility` or the Agent tool. Existence is checked **at a base commit**, never the working tree: brief input `base:` (default `git merge-base origin/<default> HEAD` in the plan's repo; the orchestrator records the main SHA in `## Decisions` before Phase 1 and passes it on every later run). Checks: every unmarked `Files touched` path (or glob) exists at `base` or is `(new)` in an earlier phase on its `Depends` chain; every `(new)`-marked path does not exist at `base` (no parent-dir requirement — a phase may create a new directory); Verify commands that invoke a `(new)` file are not dry-run; named symbols exist; Verify commands dry-run (`--help`, `-n`, stated no-op; none available ⇒ CAUTION); every pair of phases with no ordering between them (neither reachable from the other through the transitive `Depends` closure) has disjoint `Files touched`; every R-id covered. Placeholder phases (`<name>`, `<step>`) ⇒ `REVISE: not drafted`, never READY. Verdict `READY | CAUTION | REVISE`, one revision cycle, CAUTION proceeds with a Risks note. It is a pre-delegation gate, run once the Phases are drafted: shared partial `scripts/partials/plan-feasibility.md` in `/new-plan` after Step 4 (drafting) and in `/start` at Step 5 before offering Phase 1.
- **S4 drift script** `scripts/check-plan-drift.sh <plan> --repo <path> --range <a...b> [--phase N]`: union of `Files touched` globs (bash `case` patterns, path-anchored) vs `git -C <repo> diff --name-only <range>`. `--repo` and `--range` are **required, no defaults** — the caller passes the checkout it actually reviewed (feature worktree or validator scratch clone), so a primary checkout sitting on `main` can never be diffed by accident. When `--repo` shares the memory root's object store (`git rev-parse --git-common-dir` equal to `$MEMORY_DIR`'s), `projects/<plan-project>/**` is ignored (plan/todo/baseline bookkeeping rides the branch). Strips the `(new)` marker before matching. Bash 3.2, `--` before positionals. Exit 0 clean, 1 drift, 3 not applicable (plan `created:` before the cutover), 2 anything else (usage incl. missing `--repo`/`--range`, unreadable plan, unknown ref, any `git` failure, or a post-cutover plan with no `Files touched`) — never 0 on a failed diff. The cutover literal is single-sourced as `PLAN_CONTRACT_SINCE` in `scripts/_lib.sh`, read by both rule 20 and this script. Called only by the validator's final pass.
- **S5 baseline lifecycle.** `plans/<slug>.baseline/` on disk in the memory tree (committed where the project is tracked — ai-memory; elsewhere gitignored but survives sessions). `/plan-archive` moves it in a new step placed **before** the investigation steps (Step 5's no-investigation branch jumps to Step 7, so a step after it would be skipped); collision → report, never overwrite.
- **S6 validator Part A.** Rewrite (not append) the "nothing beyond the criteria" line in `agents/validator.md`, `doctrine/orchestrator.md:83` and `docs/workflow.md:21` to: criteria + phase Verify every pass; when the brief carries `goal_check: yes` — set by the orchestrator only on the last phase's `scope: final` pass, never inferred — also the Goal — all criteria PASS but evidence does not show the After state ⇒ `VERDICT: BLOCKED (goal)`, escalate — and `check-plan-drift.sh --repo <the checkout under review> --range <the brief's range>`: exit 1 ⇒ FAIL (drift), exit 3 ⇒ N/A (pre-cutover plan), any other nonzero ⇒ FAIL (check could not run); 1 and 2 block PR-READY. Pre-cutover plans: the drift exit 3 also marks the Goal check N/A (they carry no `**After:**`); the validator reports both as N/A, never BLOCKED. Parity proof = the re-run against the named ref, or the diff against the baseline dir, with output. Evidence = command + output excerpt, or `file:line` for static content; a PASS with neither is a FAIL. Phase `Risk:` is the orchestrator's default for the brief's `risk:`.
- **S7 doctrine and return contract.** Two bullets in `doctrine/orchestrator.md`: evidence rule (no completion claim without naming and running the proving command now; an executor's "done" is a claim, a diff or command output is evidence; three failed fixes on one finding ⇒ stop and question the design) and the `diverged: no | yes — <what>` return line (on `yes` the orchestrator updates the plan in a housekeeping commit before the next delegation). `executor.sh --run` prepends the return rule beside the deny-list **for `--role task` only** — explore and validate runs have nothing to diverge from (the deny-list stays role-blind); subagent task prompts paste it. `docs/workflow.md:119` mirrors it. Authoring prose: rationalization table + YAGNI pushback with a bad example in `/new-plan` 3.5; brainstorm round cap in `design-brainstorm`.

Rejected:
- Approach 2, validator-side contract → model-graded, nothing re-runnable, no authoring-time feedback.
- Approach 3, frontmatter YAML lists → duplicates the body every reader reads; worse to hand-edit.
- Template-only enforcement → the mechanism that produced the current gaps.
- Lint ERROR → `projects/**` never passes CI, so ERROR is a WARN with a scarier label.
- Opt-in `contract: v1` marker → deleting the line silences the rule (fail-open).
- Retro-fitting the 18 pre-template plans → cross-project churn for plans mid-flight.
- Stored baseline for every parity criterion → a stored lint/output snapshot drifts with the tree (memory.md: diff warning sets by running the previous script on the current tree); a git ref re-run is exact.
- `/start` describing the template in prose → a second copy that drifts.
- Drift check at `/plan-done` → post-merge, empty default range, unactionable.
- New skill for evidence discipline → probabilistic trigger with no eval gate; doctrine is injected deterministically.
- Plan-level `verification:` frontmatter → "mixed" doesn't say which criterion needs a reference.
- Baseline in the target repo, gitignored → lost on fresh clone, invisible to the validator's scratch worktree.
- Validator owns the divergence question → turns a read-only checker into a plan editor's prompt.

**Builds on:** `--brief` on the validate role (#129); managed partials (`scripts/apply-partial.sh`, task-link two-carrier assert at `test_apply_partial.sh:87`); the lint sandbox pattern in `test_lint_memory.sh`; `/plan-archive` investigation move (Steps 5–6).

## Decisions (locked)
- **Grammar** — the contract P1 writes and P2/P3/P4 parse; no phase changes it without a plan edit:
  - Criterion: `^- R[0-9]+ \[(acceptance|parity)\] ` at the start of a line under `## Success criteria`; one line per criterion.
  - Parity reference: ``vs `<git-ref>` `` or ``baseline `plans/<slug>.baseline/<path>` `` within the criterion line.
  - Phase heading: `^### Phase [0-9]+ — `; any other `###` (e.g. `### Checkpoint`) is not a phase.
  - Phase fields, each on its own line: `**Files touched:**` (comma-separated backticked paths or globs, repo-relative; a file the phase creates is suffixed ` (new)` after its closing backtick), `**Risk:** low|medium|high`, `**Depends:** none | Phase N[, Phase N…]` (phase numbers only, no names; what the feasibility brief's transitive closure and `todo.md`'s `(needs: Pn)` mirror read), `**Verify:** R<n>[, R<n>…] — <condition>` (R-ids before the em dash; single line).
  - Sections: `## Non-goals`, `## Security` exact headings; `**Before:**` / `**After:**` under `## Goal`.
  - Path patterns (accepted 2026-11-08, P3 validation): bash `case` semantics — `*` matches across `/` (`scripts/*` covers subdirectories); a path ending in `/` means the whole directory (`dir/` ≡ `dir/*`). `Files touched` lines inside fenced code blocks are not phase fields; a phase ends only at the next `### `/`## ` heading.
- Cutover literal `2026-11-08` as `PLAN_CONTRACT_SINCE` in `scripts/_lib.sh` — one definition read by rule 20 and the drift script (only this plan qualifies today).
- P1, P3, P5 are independent and run in parallel (disjoint `Files touched`); P2 needs P1 (`docs/file-formats.md` rule-20 paragraph) and P3 (`PLAN_CONTRACT_SINCE` in `_lib.sh`); P4 needs P1; P6 needs P3.
- Before Phase 1 starts, record here: `feasibility base: <main SHA>` — every feasibility run on this plan passes it as `base:`.
- feasibility base: `2f2cc3ffbf7486db7223b5f4333fc4c659055e86`
- P1 fix round touched `docs/scripts.md` (`apply-partial.sh` usage row, `[--partial <name>]`) — owned by P3; edit, not append; accepted divergence.
- Execution in worktree `~/Projects/claude/memory-verification` (branch `feat/verification-contract`) — parallel with `onboard-opencode-harness` in `memory-opencode`; only shared file is `docs/scripts.md` (append-only row, rebase on second merge). Primary checkout stays on `main` for bookkeeping.
- `docs/file-formats.md` is owned by P1 (template + rule-20 description); `docs/workflow.md` by P6; `docs/scripts.md` by P3; the changelog fragment by P6.
- Commit route: `git-cli ship` for the code/doc/doctrine changes; plan/todo bookkeeping `git-cli commit --all` to `main` (ignored by the drift script via the memory-root rule).
- Conventional-commit types: `feat(lint):`, `feat(scripts):`, `feat(validator):`, `docs(workflow):`.

## Phases

### Phase 1 — Template and scaffold partial
- `apply-partial.sh`: re-sync replaces an existing block in place; first injection still appends at EOF. Test: a carrier with two partials re-synced in either order keeps block order and leaves the file byte-identical.
- Create `scripts/partials/plan-scaffold.md` per S1 and the Grammar block; inject into `/new-plan` and `/start` (`apply-partial.sh --file … --partial plan-scaffold --force`); their Step 3 points at the *Plan scaffold* section; add the two-carrier literal assert.
- `/new-plan` 3.5: rationalization table + YAGNI pushback with a bad example; `design-brainstorm`: round cap.
- `docs/file-formats.md` plan section: template, Grammar, parity reference forms, baseline dir, rule 20 checks and cutover.

**Files touched:** `scripts/apply-partial.sh`, `scripts/partials/plan-scaffold.md` (new), `commands/new-plan.md`, `commands/start.md`, `skills/design-brainstorm/SKILL.md`, `docs/file-formats.md`, `scripts/tests/test_apply_partial.sh`
**Risk:** medium
**Depends:** none
**Verify:** R1 — `bash scripts/tests/test_apply_partial.sh` green with the plan-scaffold count at 2 and the in-place order test passing; `apply-partial.sh --all` for `task-link` then `plan-scaffold` (and the reverse) leaves `git diff` empty; `bash scripts/validate-skills.sh` passes.

### Phase 2 — Lint rule 20
- Implement S2 inside the `plans/*.md` walk, reading the cutover from `PLAN_CONTRACT_SINCE` (`_lib.sh`, added in P3); every line prefixed `plan-contract:`.
- Tests: one sandbox holding one plan per check plus a clean plan, a pre-cutover plan, a `draft` dirty plan (scope includes draft) and a `created:`-less plan (check j), a single lint run, per-check assertions; mutation per check (keeps the gate's lint-run count low — `test_lint_memory.sh` is the gate floor).
- If a check's shape changes during implementation, update the rule-20 paragraph P1 wrote in `docs/file-formats.md` in the same commit — no gate catches that drift.

**Files touched:** `scripts/lint-memory.sh`, `scripts/tests/test_lint_memory.sh`, `docs/file-formats.md`, `scripts/plan-fence.awk`
**Risk:** medium
**Depends:** Phase 1, Phase 3
**Verify:** R2, R7 — `bash scripts/tests/test_lint_memory.sh` green; R7 set-diff (origin/main's `lint-memory.sh` from a scratch worktree vs the branch's, same `MEMORY_DIR`, `grep -v plan-contract:`, `sort`) empty.

### Phase 3 — Drift script
- `scripts/check-plan-drift.sh` per S4.
- Hermetic tests in `scripts/tests/test_check_plan_drift.sh`: clean, out-of-set file, glob prefix trap (`scripts/` must not match `scripts-old/`), `(new)` marker stripped, `--phase`, memory-root exclusion (incl. from a linked worktree); a worktree with an out-of-plan change while the primary checkout is on `main` ⇒ exit 1; exit 3 on a pre-cutover plan; exit 2 on a post-cutover plan with no `Files touched`, missing `--repo`/`--range`, usage error, unknown ref and a non-git `--repo` (never 0). `docs/scripts.md` row.

**Files touched:** `scripts/check-plan-drift.sh` (new), `scripts/tests/test_check_plan_drift.sh` (new), `scripts/plan-fence.awk` (new), `scripts/_lib.sh`, `docs/scripts.md`
**Risk:** medium
**Depends:** none
**Verify:** R3 — `bash scripts/tests/test_check_plan_drift.sh` green; `--repo . --range origin/main...HEAD` on this plan's branch exits 0; `bash scripts/check-docs.sh` passes.

### Phase 4 — Feasibility brief
- `agents/plan-feasibility.md` per S3; `scripts/partials/plan-feasibility.md` injected into `/new-plan` and `/start` as a *Plan feasibility* section; `/new-plan` after Step 4 (drafting) and `/start` Step 5 before offering Phase 1 point at it by name; two-carrier literal assert.

**Files touched:** `agents/plan-feasibility.md` (new), `scripts/partials/plan-feasibility.md` (new), `commands/new-plan.md`, `commands/start.md`, `scripts/tests/test_apply_partial.sh`
**Risk:** low
**Depends:** Phase 1
**Verify:** R4 — `bash scripts/tests/test_apply_partial.sh` green; the three REVISE runs (missing path, pre-existing `(new)` path, placeholder scaffold) and the READY/CAUTION run on this plan, outputs pasted.

### Phase 5 — Baseline lifecycle
- `/plan-archive`: new baseline-move step placed before Step 5 so the no-investigation jump cannot skip it; collision → report, never overwrite; the plan still archives.

**Files touched:** `commands/plan-archive.md`
**Risk:** low
**Depends:** none
**Verify:** R5 — live exercise on a scratch project: archive with baseline and no investigation moves the dir; with baseline and investigation moves both; a seeded destination reports and leaves both.

### Phase 6 — Validator and doctrine
- `agents/validator.md` Part A per S6; `doctrine/orchestrator.md` validator bullet rewritten + two S7 bullets; `docs/workflow.md:21`, `:119` and Task Contract section; `executor.sh --run` prepends the `diverged:` rule for `--role task` only (test asserts present for task, absent for explore and validate); changelog fragment covering the whole plan.

**Files touched:** `agents/validator.md`, `doctrine/orchestrator.md`, `docs/workflow.md`, `scripts/executor.sh`, `scripts/tests/test_executor.sh`, `changelog.d/verification-contract.feature.md` (new)
**Risk:** medium
**Depends:** Phase 3
**Verify:** R6 — `grep -n 'BLOCKED (goal)\|check-plan-drift.sh\|diverged:'` hits in all three prose files; no remaining "nothing beyond"/"exactly those" in them; `bash scripts/tests/test_executor.sh` green; `bash scripts/check-docs.sh` passes; live scenarios (i), (ii), (ii-b), (iii), (iv), (v) verdicts pasted.

### Checkpoint — pre-ship
- Full `bash scripts/run-tests.sh` with signing off (memory.md env) green; R7 set-diff empty.
- Live exercise: `/new-plan scratch-plan --no-task` renders the partial; rule 20 on it reports only placeholder gaps; delete it.
- Drift: `check-plan-drift.sh <plan> --repo <this checkout> --range origin/main...HEAD` exits 0.
- Feasibility: this plan, with the recorded `base:`, returns READY or CAUTION.
- Validator `scope: final`, `risk: medium`, `goal_check: yes`, cross-model; threat model in the brief from round 1 (checkpoint 2026-11-08 lesson). Hypotheses: a partial re-sync reorders blocks; drift diffs a checkout other than `--repo`; feasibility checks the working tree instead of `base`; overlap check misses a non-root unordered pair; Goal check fires without `goal_check: yes`; exit 3 returned for a post-cutover plan; rule-20 regex drifts from the Grammar block; a phase with no Verify slips through (e); drift exit 2 read as pass; drift glob matches a prefix; a partial assert drops to dynamic count; Goal check fires on a non-final pass; rule 20 silent on a `draft` plan or a `created:`-less plan; `diverged:` rule prepended to a validate or explore run.
- `git-cli ship --intent`.

## Risks / open questions
- Parity tolerance ("modulo `updated:`") is prose in the criterion; nothing lints it — the validator reads it.
- Feasibility dry-run of Verify commands is best-effort; no safe dry form ⇒ CAUTION, never REVISE.
- Rule 20 adds to the hand-triaged WARN set; the `plan-contract:` tag keeps it filterable.
- The cutover literal is a hardcoded date — deliberate (same reasoning as the drift-gate carrier literal); never derive it.
- `design-brainstorm` round cap is unmeasured prose until trigger evals (task `3dbf6850-c619-81b9-b825-ebfa991445c3`).
- A Verify line citing an R-id it does not actually prove is invisible to lint — only the final-pass Goal check catches the aggregate miss.
- R6 live scenarios (i)–(iv) and R4's runs test model behaviour: one run each, pasted, not a regression suite — a later regression is the eval-suite task's job (`402f6850-c619-81bd-b67b-f3c49da741bc`).
- The validator must pass `--repo <reviewed checkout> --range <brief range>`; the brief already carries both, so S6 states it explicitly.
- Feasibility CAUTION (R4 run on this plan, base `2f2cc3f`): P1 `apply-partial.sh --all`, P5 live `/plan-archive`, P2 R7 scratch extract and P4/P6 model runs have no dry form — run in the worktree / scratch fixtures, `git diff` as proof.
- R4 evidence (2026-11-08, brief followed via general-purpose agent — `plan-feasibility` agent type not linked in-session): missing-path copy ⇒ REVISE naming `does/not/exist.sh`; pre-existing `(new)` copy ⇒ REVISE naming `scripts/_lib.sh`; unfenced placeholder scaffold ⇒ `REVISE: not drafted`; this plan ⇒ CAUTION. The this-plan run was at worktree HEAD `d62b69a` (P4 commit), i.e. after P1/P4 created the `(new)` files — the re-run condition is met.
- R6 live evidence (2026-11-08, worktree `agents/validator.md` followed via general-purpose agents; fixture `scratchpad/r6`, hello.sh prints `hello`, After = `hello world`): (i) last phase final + `goal_check: yes` ⇒ `BLOCKED (goal)`, drift exit 0; (ii) Phase 1 final, no goal_check ⇒ PR-READY, no goal/drift; (ii-b) fix-round ⇒ PR-READY, no goal block; (iii) staging-deploy criterion backed only by executor claim ⇒ FAIL, BLOCKED; (iv) `--range nosuchref...HEAD` ⇒ drift exit 2 reported FAIL (could not run), blocks (goal also blocked — fixture confound); (v) pre-cutover copy ⇒ drift exit 3 N/A, Goal N/A, PR-READY.
- Final pass round 1 (codex, decorrelated, 2026-11-08): BLOCKED — drift indented-fence bypass, rule-20 (g) bypass when a baseline line also names `vs`, R4 note read as missing evidence. Fixed in `fix(scripts): drift honours indented fences…`; R4 note corrected. Later validation Claude-only (user: codex limits) ⇒ final pass `decorrelated: no`.
- Final pass round 2 (Claude, 2026-11-08): BLOCKED — third fence-parsing divergence between drift and rule 20 (info string containing a backtick). Recurring class ⇒ design change: one shared fence/section parser `scripts/plan-fence.awk` used by both (`awk -f`); also rule 20 flags duplicate `Files touched` and `### Phase <non-digit>` near-miss headings, (d) counts only phase Verify lines. Accepted risk: `Files touched` inside an HTML comment still counts (author-controlled).
- Final pass round 3 (Claude, 2026-11-08, after bash-3.2 fix `aba7d06`): PR-READY. Accepted risks (follow-up candidates): drift unions every `Files touched` span rule 20 merely WARNs on (duplicate/malformed lines) — hardening = drift exit 2 on those; duplicate `### Phase N` numbers pass rule 20 silently; missing `plan-fence.awk` makes drift say "no Files touched" (still exit 2). Nit fixed: evidence rule says "stop and question the design".
