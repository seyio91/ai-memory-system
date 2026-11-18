---
plan: initiative-now-view-per-env-targets
status: in_progress
created: 2026-11-17
owner: claude (orchestrator)
task_provider: local
task_ref: initiative-format-now-view-per-env-targets-one-line-status-current-rules-index-progress-log
---

# Plan — Initiative format: Now view, per-env Targets, one-line status, current-rules index, progress log

## Goal
Make an initiative file answer "what's next" on its own while keeping the binding record. To do that, add generated Now, environment-matrix and current-rules blocks, `@env` Targets, a one-line `state · next · blocked_by` status with a separate `scope:` line, `topic:`/`AMENDS` decision metadata, and a progress log in its own folder. This ships as a breaking release (3.0.0) whose migration rewrites existing initiatives, followed by a hand pass on vault-eks.

**Before:** `vault-eks.md` is 396 lines and 126 KB. 18 of its 29 statuses are over 300 chars (max 1,992) and mix state, progress and scope. "What's next" needs a script plus greps plus synthesis. Multi-environment Targets block dependants that only need staging. Amendment chains can't be walked forwards.
**After:** the top of an initiative carries a generated `## Now`, `## Environment matrix` and `## Current rules`. Every Target status is one line naming the next action, with scope on its own line. Per-environment work is modelled as `@env` Targets. Progress history lives in `initiatives/logs/<slug>.md`. The old format is a lint ERROR, and the 3.0.0 migration has converted every live initiative.

## Non-goals
- Archiving decisions. They bind every session and stay in the main file.
- A closeable-Jira line in Now, or tooling that opens a later environment's `@env` Targets.
- A migration that authors judgement content: real `next:` actions, topic tags, `@env` splits, `AMENDS` lines, trimmed scope.
- Migrating archived initiatives under `initiatives/archive/`. Nothing lints or parses them.

## Success criteria
- R1 [acceptance] `initiative-render.sh <slug> --write` then `--check` exits 0. On the fixture, `## Now` lists Ready Targets with their `next:` action. It lists Blocked Targets with derived unsatisfied edges merged with the authored `blocked_by:`, and shows open proposals. No fence contains a date or timestamp.
- R2 [acceptance] `@env` edges resolve per environment. In a fixture where Target X depends on `Y@staging`, X shows satisfied when `Y@staging` is done and `Y@non-prod` is open (test in `test_initiative_status.sh`).
- R3 [acceptance] `### Closed` table rows (`| <id> | <closed date> | <jira> | <outcome> |`) count as terminal Targets: `initiative-status.sh` short-circuits them, and lint resolves `depends_on` edges to them. Under `## Targets`, `### Closed` is the only non-Target heading. Any other `### ` heading that is not `<project>/<name>[@<env>]` is a lint ERROR.
- R4 [acceptance] `## Current rules` groups confirmed and proposed decisions by the frontmatter `topics:` enum, in enum order. Superseded, rejected and retired entries drop out. An `AMENDS Dn` target renders as `(as amended by Dm)`. Lint flags an off-enum `topic:` and a missing `→ Dm` forward pointer.
- R5 [acceptance] `lint-memory.sh` ERRORs on `next_actor:` and on a status that does not match `<state> · next: … · blocked_by: …` (terminal states exempt from `next:`). It WARNs on a status over 300 chars, on an open Target whose `next:` has no ` — ` action part, and on a stale fence. `initiative-status.sh` on an old-format file exits non-zero and names the migration. Files under `initiatives/logs/` are never scanned as initiatives. Covered in `test_lint_memory.sh` and `test_initiative_status.sh`.
- R6 [acceptance] `migrations/3.0.0-initiative-format.sh` on an old-format fixture:
  - saves a byte-identical copy to `initiatives/.state/<slug>.pre-3.0.0.md` before any write;
  - moves each status's prose to a `- scope:` line, verbatim, minus `Progress:`/`Was:` segments, which go to `initiatives/logs/<slug>.md` as entries tagged with the Target id;
  - rewrites the status to `<state> · next: <old next_actor value> · blocked_by: none` and removes `next_actor:`;
  - collapses `done` Targets into `### Closed` rows, carrying the date and `jira:` value, with the old block moved to the log; an abandoned (`closed`) Target keeps its heading with `- status: closed` and never satisfies a dependency (amended 2026-11-18 after the final validation pass);
  - inserts the three fences and an empty `topics:`, and adds `→ Dn` pointers from `SUPERSEDES` keywords;
  - reports, without editing, every prose "Amends Dn" / "amended by Dn" candidate and every line it could not fully match;
  - is a no-op on a second run.
  The migrated fixture has no lint ERROR. `test_migration_runner.sh` and `test_upgrading_doc.sh` pass.
- R7 [acceptance] The session hooks still work on the new format. `_initiative_targets_project` in `scripts/hooks/lib.sh` matches an `@env` Target by project prefix, and a project whose Targets are all Closed rows yields no alert. Covered by a test; no change to the function is expected.
- R8 [acceptance] `bash scripts/run-tests.sh` passes in full (signing off), run in the worktree, where the un-migrated live `vault-eks.md` is absent. Touched suites also pass under `PATH="/usr/bin:/bin:$PATH" /bin/bash`, and `/bin/bash -n` is clean on every changed script.
- R9 [acceptance] `docs/initiatives.md` documents the status grammar, `scope:`, the `envs:` frontmatter, `@env`, Closed rows, `topics:`/`topic:`/`AMENDS`, the amendment rule, the log folder and a hand-edit equivalent for each fence (Two-Path). `/plan-done` and the shared task-linking step (so `/start` and `/new-plan`) run `initiative-render.sh <slug> --write` for a linked initiative. No doc, command or template references `next_actor` outside the upgrade note. `check-docs.sh` and the partial drift gate are green.
- R10 [acceptance] After migration and the hand pass, `vault-eks.md` has no lint ERROR and none of the new WARNs, and `## Now` names a next action for every open Target. Line and byte counts are recorded before and after.

## Design
- **New `scripts/initiative-render.sh <slug> [--write|--check]`** owns three AUTOGEN fences: `## Now`, `## Environment matrix` and `## Current rules`. `--write` rewrites the fences in place (temp file + mv). `--check` exits non-zero when a fence differs from a fresh render. Fences carry no date, so a fence only goes stale when its inputs change. It reads derived stages from a new machine-readable `initiative-status.sh --tsv`, so derivation logic lives in one place.
- **New `scripts/lib/initiative-targets.awk`** is the shared Target parser for status, render, lint and migration, mirroring how `decision-stream.awk` is shared. It handles `### <project>/<name>[@<env>]` headings and `### Closed` table rows as terminal Targets. Targets are never grouped under hand-written headings such as `### Ready`; Now does that grouping.
- **Status grammar, new format only:** `- status: <state> · next: <session — action> · blocked_by: <…|none>`. Terminal states (`done`, `closed`) need no `next:`. `- status:` is required on `interactive` Targets and stays optional on `software_adw` Targets, whose stage is derived; Now shows the derived stage as the next step when no status is authored. The Target's description lives on a separate `- scope:` line. The old shape (`next_actor:`, `<state> — prose`) is no longer parsed: lint ERRORs and `initiative-status.sh` refuses the file and names the migration.
- **`@env` Targets are plain ids**, so edges need no new semantics. The matrix groups rows by base name, with columns from frontmatter `envs:`. A cell shows the derived stage only, or `not opened` when an env has no Target. Evidence stays in the log.
- **`blocked_by:` holds only non-edge blockers** (decisions, external facts). Now merges these with unsatisfied `depends_on` edges, so an edge is never written twice.
- **Closed rows keep the Jira key.** The row is `| <id> | <closed date> | <jira> | <outcome> |`, so the ticket-to-Target mapping survives the collapse. The migration writes `see log` as the outcome.
- **Decision metadata.** A frontmatter `topics:` enum fixes the order and vocabulary of Current rules. Each entry gets a `topic:` continuation line. A new `AMENDS <id>` keyword joins `SUPERSEDES`. The `→ Dn` forward pointer on an older entry's status line counts as the allowed status-line edit, and lint checks it is complete. Grammar goes in `decision-stream.awk`.
- **Amendment rule.** From this release an amendment is always a new entry carrying `AMENDS <id>`. Historical in-place amendments ("Amended 2026-10-21 (user)") stay as written and are not modelled. Existing prose amendments ("Amends D10.") become `AMENDS` lines only by hand; the migration lists them as candidates.
- **Progress log `initiatives/logs/<slug>.md`** sits in its own subdirectory and is found by naming convention, with no frontmatter field. It is append-only, with dated entries tagged by Target id. It is live, not archived. Every existing `initiatives/*.md` glob is non-recursive, so lint, the hooks and the 1.7.0 migration skip it with no change, as they already skip `archive/` and `.state/`. When an initiative closes, its log moves with it to `initiatives/archive/logs/<slug>.md`.
- **Freshness.** Now changes whenever a linked plan changes status, so every command that changes one regenerates the fences: `/plan-done`, and the shared task-linking step that `/start` and `/new-plan` both carry. `/start` Step 1.5's "never edit the initiative" becomes "never hand-edit; regenerating fences is allowed". Lint WARNs on a fence that is still stale. No hook mutates files.
- **Migration `3.0.0`** rewrites every live initiative as R6 describes. It follows the 1.7.0 conventions (idempotent, temp file + mv, symlinks skipped, unmatched lines left byte-identical and reported) and adds a pre-migration backup. Reader and migration ship in the same release: a breaking release is exempt from the N/N+1 compatibility rule, and `UPGRADING.md` says so.
- **The hook-side parser stays separate.** `_initiative_targets_project` is a deliberately cheap prefix match that `check-memory-size.sh` reuses. It already matches `@env` ids, and missing Closed rows is correct because a closed Target raises no alert. A test pins this.
- Alternative: reader in 2.1.0, migration in 2.2.0 → rejected by the user: one breaking release, old format dropped.
- Alternative: keep parsing the old format with lint WARNs → rejected by the user: two code paths.
- Alternative: move status prose to the log, or truncate it into `next:` → rejected by the user in favour of a lossless in-file `scope:` line.
- Alternative: a sibling `initiatives/<slug>.log.md` → rejected: every initiative glob would need a `*.log.md` exclusion, and one that is missed makes a log look like a kind-less initiative.
- Alternative: grow `initiative-status.sh` with `--now/--write` → rejected: an already 578-line script would mix deriving status with rewriting files.
- Alternative: a Python renderer → rejected: a second parser that drifts from the shared awk grammar, and it breaks the bash-3.2/awk convention.
- Alternative: an `envs:` sub-matrix inside one Target → rejected: edges would need `target@env` resolution into sub-fields, and it gives no smaller file.
- Alternative: free-text topics → rejected: near-duplicate strings silently split a Current-rules row.
- Alternative: print-only generated views → rejected: the file alone would not answer "what's next".

**Builds on:** investigation `initiative-now-view-per-env-targets`; the mock-up `projects/eks/drafts/vault-eks-initiative-format-proposal.md`; investigation `initiative-structure` (its `## State` was never wired, and `## Now` replaces it); `scripts/initiative-status.sh`; `scripts/lib/decision-stream.awk`; `migrations/1.7.0-decision-status-field.sh`; `scripts/partials/task-link.md`; `/plan-done` Step 5b.

## Security
Phase 6 is `Risk: high` because the migration rewrites user memory files unattended during `/sync-system`, and the old format stops parsing in the same release. The threat is silent loss or corruption of decision or Target history. Containment:
- It saves a byte-identical pre-migration copy under `initiatives/.state/` before the first write.
- It moves text (to `scope:` or the log) and never deletes it. The test asserts that every word of the old status prose is present in the main file or the log afterwards.
- It writes only lines it fully matches, through temp file + mv, and reports the rest.
- It never edits decision text; the only decision-stream edit is the `→ Dn` pointer on a status line.
- It is idempotent and skips symlinks. No network or credential surface.

## Decisions (locked)
- base: `2b25b67aef6e273179350cdb0a929ccad7adced8` (origin/main at plan time).
- Breaking release: a `breaking` changelog fragment, version 3.0.0, with an `UPGRADING.md` section headed exactly `## 3.0.0`.
- The old format is dropped: lint ERROR, and the parser reads the new grammar only (user, 2026-11-17).
- Status prose moves to a `scope:` line (user, 2026-11-17).
- Status length WARN threshold: 300 chars.
- One PR for Phases 1–6 (user, 2026-11-17): one branch, one commit series, opened only after Phase 6 validates. Phase 7 follows the release.

## Phases
### Phase 1 — Shared Target parser, new status grammar, @env, Closed rows, --tsv
- Move Target parsing from `initiative-status.sh` into `scripts/lib/initiative-targets.awk`: `<project>/<name>[@<env>]` headings, `### Closed` rows as terminal Targets, `scope:`, and the one-line status with `next:`/`blocked_by:`.
- Drop `next_actor` and old-shape status parsing. An old-format file exits non-zero with a message naming the 3.0.0 migration.
- Add `initiative-status.sh --tsv` (id, stage, deps-satisfied, next, blocked_by).
- Convert the test fixtures to the new format and add cases for `@env` edges, Closed rows and the old-format refusal.
- Add the hook test for R7. Keep `test_session_start_memory.sh` green unchanged: its `software_adw` fixture has no `- status:`, which stays valid.

**Files touched:** `scripts/initiative-status.sh`, `scripts/lib/initiative-targets.awk` (new), `scripts/tests/test_initiative_status.sh`, `scripts/tests/test_hooks_initiative_format.sh` (new)
**Risk:** medium
**Depends:** none
**Verify:** R2, R3, R7 — `test_initiative_status.sh` and `test_hooks_initiative_format.sh` pass, including the `@env`, Closed-row and old-format-refusal cases.

### Phase 2 — Decision-stream metadata: topics enum, topic:, AMENDS, forward pointers
- Extend `decision-stream.awk` with the `topic:` continuation, the `AMENDS <id>` keyword and the `→ Dn` status-line pointer. Also parse `SUPERSEDES <id>`, which exists only in prose at base and which the migration's pointer step reads.
- Add helpers: live set (confirmed + proposed), amended-by map, pointer completeness, and a detector for prose "Amends Dn" candidates (used by the migration report).

**Files touched:** `scripts/lib/decision-stream.awk`, `scripts/tests/test_decision_stream.sh` (new)
**Risk:** medium
**Depends:** none
**Verify:** R4 — `test_decision_stream.sh` shows the live set, the amended-by map, missing-pointer detection and candidate detection. The existing 1.7.0 migration and lint suites stay green.

### Phase 3 — initiative-render.sh (Now, matrix, Current rules)
- Render the three fences from `--tsv` plus the decision-stream helpers, with `--write` (temp + mv) and `--check`. No date in any fence.
- Add the `docs/scripts.md` rows for `initiative-render.sh` and `--tsv` in this phase, so `check-docs.sh` stays green between phases.
- Use a fixture initiative covering ready, blocked (edge + `blocked_by`), `@env` matrix with `not opened`, and topics with AMENDS.

**Files touched:** `scripts/initiative-render.sh` (new), `scripts/tests/test_initiative_render.sh` (new), `docs/scripts.md`
**Risk:** medium
**Depends:** Phase 1, Phase 2
**Verify:** R1, R4 — `test_initiative_render.sh` passes. `--write` then `--check` exits 0, a hand edit inside a fence makes `--check` exit non-zero, and two renders a day apart are identical.

### Phase 4 — Lint rules
- ERROR on `next_actor:`, on an old-shape or malformed status, and on a non-Target `### ` heading under `## Targets` other than `### Closed`.
- WARN on a status over 300 chars, an open Target whose `next:` has no action part, a stale fence, an off-enum `topic:` and a missing forward pointer.
- Resolve `@env` and Closed-row edges, and add a test proving a file in `initiatives/logs/` is not scanned.
- Convert the existing lint fixtures to the new format.
- Word the new decision-stream findings with the `decision-stream ` prefix, because `memory_write_guard.sh` only passes on lint lines containing it.

**Files touched:** `scripts/lint-memory.sh`, `scripts/tests/test_lint_memory.sh`
**Risk:** medium
**Depends:** Phase 1, Phase 2, Phase 3
**Verify:** R3, R4, R5 — `test_lint_memory.sh` passes with one case per new rule, plus a negative case showing an up-to-date new-format fixture is clean.

### Phase 5 — Docs, template, commands, changelog
- In `docs/initiatives.md`: the status grammar, `scope:`, `envs:`, `@env`, Closed rows, topics/AMENDS and the amendment rule, the log folder and its move on close, and the Two-Path hand-edit for each fence.
- Rewrite `initiatives/_template.md` in the new format, with `envs:` and `topics:`.
- Add the `--write` step to `/plan-done` and to `scripts/partials/task-link.md`, then re-apply the partial to `/start` and `/new-plan`. Reword `/start` Step 1.5 (no `next_actor`; regenerating fences is allowed; row selection matches the Phase 1 table columns).
- Add a `--write` step to `/new-initiative`, so a new initiative does not start with stale fences.
- Add the fragment `changelog.d/initiative-format.breaking.md`.

**Files touched:** `docs/initiatives.md`, `initiatives/_template.md`, `commands/plan-done.md`, `commands/start.md`, `commands/new-plan.md`, `commands/new-initiative.md`, `scripts/partials/task-link.md`, `changelog.d/initiative-format.breaking.md` (new)
**Risk:** low
**Depends:** Phase 3, Phase 4
**Verify:** R9 — `check-docs.sh` and the partial drift gate are green. `grep -rn next_actor docs commands initiatives/_template.md scripts/partials` returns nothing.

### Phase 6 — Migration 3.0.0
- Add `migrations/3.0.0-initiative-format.sh`, doing the rewrite in R6 with both awk libs, plus `changelog.d/initiative-format-migration.upgrade.md` and the `## 3.0.0` section in `UPGRADING.md` (what changes, the backup location, the hand pass that follows, the N/N+1 exemption).
- State the breaking-release exemption in `migrations/README.md`, whose N/N+1 rule has no exception today.
- Add a test with an old-format fixture modelled on real vault-eks shapes: a long prose status, `Progress:`/`Was:` segments, a `done <date> —` Target with a `jira:` line, a `SUPERSEDES` entry and prose "Amends Dn". Assert the backup, the no-word-lost check, the report, a lint-ERROR-free result and an idempotent second run.

**Files touched:** `migrations/3.0.0-initiative-format.sh` (new), `migrations/README.md`, `UPGRADING.md`, `changelog.d/initiative-format-migration.upgrade.md` (new), `scripts/tests/test_migration_3_0_0.sh` (new)
**Risk:** high
**Depends:** Phase 1, Phase 2, Phase 3, Phase 4
**Verify:** R6, R8 — `test_migration_3_0_0.sh`, `test_migration_runner.sh` and `test_upgrading_doc.sh` pass, and the full `run-tests.sh` plus the bash 3.2 runs are green.

### Phase 7 — vault-eks hand pass (personal memory, not shipped)
- After the release syncs, review the migration's diff and report against the backup.
- Then by hand:
  - add the `topics:` enum and a `topic:` tag on each of the 83 decisions;
  - add `AMENDS` lines for the reported candidates (about 25) and their forward pointers;
  - split the four multi-env Targets into `@env` Targets and add `envs:`;
  - write a real `next:` action for every open Target (27 of 29 carry a bare actor today) and trim each `scope:`;
  - fill in Closed-row outcomes.
- Run `--write`.

**Files touched:** `initiatives/vault-eks.md`, `initiatives/logs/vault-eks.md` (new)

These are gitignored personal memory, absent from the base commit. The feasibility path check is deliberately waived for this phase.
**Risk:** medium
**Depends:** Phase 5, Phase 6
**Verify:** R10 — `lint-memory.sh` shows no ERROR and none of the new WARNs for vault-eks, `## Now` names a next action for every open Target, and line and byte counts are recorded before and after.

## Risks / open questions
- Deferred: a closeable-Jira line in Now, which needs todo-key derivation.
- Deferred: opening a later env's `@env` Targets just in time remains a manual convention, with no tooling.
- Deferred: whether 300 chars is the right status cap gets tuned after the vault-eks pass.
- Between `/sync-system` to 3.0.0 and the hand pass, a migrated initiative is valid but thin: `next:` holds only the old actor and `scope:` is untrimmed. Lint WARNs mark every such Target.
- A line the migration cannot convert leaves the file failing lint and refused by `initiative-status.sh` until it is fixed by hand. The report names each one, and the backup allows a retry.
- Splitting `Progress:`/`Was:` out of free prose may match unevenly (7 of 29 vault-eks statuses contain one). Anything not cleanly matched stays in `scope:`.
- If a `software_adw` Target is collapsed into a Closed row, its line leaves the staleness snapshot. Phase 6 must check whether that raises a false alert and, if so, re-acknowledge in the migration.
- The branch must not be checked out in the main checkout: from Phase 1 on it refuses the un-migrated `vault-eks.md`, and this checkout is the live harness. Work in a worktree.
- Feasibility CAUTION (2026-11-17, revised plan): Phase 7's paths are absent at base by design. Its other findings are folded into Phases 1, 2, 4, 5 and 6 and R8.
- Lint calling render `--check` per initiative adds runtime. This is fine at one live initiative; revisit if the count grows.
