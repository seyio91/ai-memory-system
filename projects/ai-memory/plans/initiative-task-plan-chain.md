---
plan: initiative-task-plan-chain
status: in_progress
created: 2026-09-20
owner: claude (orchestrator)
task_provider: notion
task_ref: 3e1f6850-c619-81c0-8818-e0841d127408
---

# Plan — Initiative → task → plan, joined on the task

## Goal
Make the initiative layer express the decomposition it is meant to: an initiative spans many
Targets, each Target is exactly one task in exactly one project, and a plan is 1:1 with its task.
Today the Target names a task *or* a plan — never both, split by `execution_mode` — so the chain
never composes and an initiative-born plan has no task to record, which forces `task_ref: none`
to mean something it does not. Replace the two disjoint pointers with one: the Target names the
task, and the plan is found by matching `task_ref`.

## Success criteria
- `plan:` appears in no initiative file and not in `initiatives/_template.md`.
- Every `- status:` line across the four live initiatives begins with `open`, `blocked`, `done`
  or `closed`. `status (historical):` lines are byte-unchanged and produce no WARN.
- Derived **classification** for all 25 Targets matches the pre-change baseline, target for
  target, with exactly two admissible differences: interactive prose gains its leading token,
  and the six frozen dispatch Targets move from derived `complete` to asserted `done`. Any other
  moved row is a regression.
- A non-terminal Target with no `task:` produces a lint WARN; mutation-tested in both directions.
- A task appearing on two Targets, or two live plans carrying one `task_ref`, derives `unknown`
  with both locations named in the evidence. Covered by a test.
- `/start` on a task that sits on a Target prints the initiative slug, Target id and
  `depends_on`; on a task that does not, output is unchanged. Both paths live-exercised.
- Suite green under `/bin/bash` 3.2, shellcheck clean, `docs/initiatives.md` updated, changelog
  fragment present.

## Design
- **Chosen: one pointer, joined on the task.** The Target carries `task:`; derivation finds the
  plan by searching `projects/<project>/plans/*.md` then `archive/plans/*.md` for a matching
  `task_ref`. No match = `not-started` (declared, not yet planned). Two matches = `unknown`,
  failing closed. Missing checkout = `unknown`, unchanged.
- **Terminal assertions short-circuit, in any mode.** `status:` becomes valid on every Target and
  its first word is load-bearing. `done`/`closed` are echoed and stop the lookup; derivation only
  ever resolves live work. This is what removes the circularity — a finished ADW Target would
  otherwise need a task to prove it did not need one.
- **Status token vocabulary over a second machine field.** `open | blocked | done | closed`,
  free prose after. One field stays one field, and it fixes real ambiguity already in the tree
  (`**M0/M1 DONE 2026-09-20; target still open for M2.**` reads as finished to any first-word
  parser, and is the one Target the new rule must catch).
- **`/start` reads, never writes.** It greps `initiatives/*.md` for `- task: <ref>` and reports
  the initiative, Target and `depends_on`. Dropping `plan:` is what makes this possible: nothing
  on the Target needs updating when work starts.
- Alternative — generated task→plan index under `initiatives/.state/` → rejected: new state that
  rots, and that directory already carries the staleness snapshot.
- Alternative — `initiative:` back-pointer in plan frontmatter → rejected: a third hand-typed
  pointer, which is what this change exists to remove. Upward lookup stays a grep over four files.
- Alternative — keep both `task:` and `plan:` and lint that they agree → rejected: two hand-typed
  pointers kept in step by a rule, where one derivable pointer needs no rule at all.
- Alternative — back-fill tasks for all 14 pointer-less Targets → rejected by the user: board
  noise for finished work. Only non-terminal Targets need a task.

## Decisions (locked)
- Matching is plain string equality on the full ref. A short-prefix UUID silently fails to match,
  so the standing "always the full Notion UUID" rule becomes load-bearing, not advisory.
- A plan carrying `task_ref: none` can never join a Target. Correct by design; stated in the docs.
- Freezing the six complete dispatch Targets trades automatic archive-detection for a hand-written
  terminal line. One-way door, accepted for work that is done forever.
- `status (historical):` and any future `status (...)` variant are out of scope for the token rule;
  derivation already matches `^- status: ` exactly.
- The four initiative files are gitignored (`.gitignore:39`); only `_template.md` ships. Their
  migration is local-only and rides no commit. Everything else here is a system change → PR.
- Phases 1 and 4 touch `lint-memory.sh`; phase 4 depends on phase 1 only for the token vocabulary,
  not for its own rule. Phases 2 and 4 are otherwise independent and can be fanned out.

## Phases

### Phase 1 — Status token: vocabulary, lint rule, migration
- Capture the pre-change baseline first: `initiative-status.sh` output for all four initiatives,
  saved outside the tree. It is the regression oracle for every later phase.
- Add the token grammar to `initiatives/_template.md`.
- Lint rule: a `- status:` line must begin with `open|blocked|done|closed`; `status (historical):`
  and other parenthesised variants are ignored.
- Migrate the live `- status:` lines across the four initiatives to carry a leading token.

**Depends:** none
**Verify:** every `- status:` line in the four initiatives begins with a vocabulary token;
`status (historical):` lines are byte-identical to baseline (`git diff` is not available for
gitignored files — compare against the saved copy); the rule WARNs on a tokenless status and
stops WARNing when fixed, mutation-tested in both directions; derived classification for all 25
Targets is unchanged against the baseline except for the token text itself.

### Phase 2 — Task-keyed derivation
- Replace the `plan:` pointer lookup in `initiative-status.sh` with a task→plan search over
  `projects/<project>/plans/*.md`, then `projects/<project>/archive/plans/*.md`.
- Terminal status token short-circuits before any lookup, in every mode.
- No match → `not-started`. Two or more matches → `unknown`, evidence naming each path. Missing
  checkout → `unknown`, unchanged. `todo.md` counts key on the matched plan's filename.

**Depends:** Phase 1
**Verify:** tests cover five cases — live plan by task, archived plan by task, no match,
duplicate match, missing checkout; a real-tree run over all four initiatives reproduces the
baseline classification; an archived plan renamed on disk still resolves (the case filename
matching loses today).

### Phase 3 — Retire `plan:`
- Remove `plan:` from `_template.md`, from `docs/initiatives.md`, and from the seven live Targets
  that carry it.
- Freeze the six complete dispatch Targets with a terminal `status: done — <evidence>`, carrying
  over the completion detail already written in their `next_actor` lines.

**Depends:** Phase 2
**Verify:** `grep -rn '^- plan:' initiatives/` returns nothing; the six frozen Targets derive
`done` from their assertion with no filesystem lookup; the dispatch initiative's full table is
otherwise identical to baseline.

### Phase 4 — `task:` requirement and uniqueness
- Lint rule: a Target whose status token is non-terminal must carry `task:`.
- Lint rule: a task may appear on at most one Target; at most one live plan may carry a given
  `task_ref`.
- Mint the one task the new rule demands — `platform-agent/repo-bootstrap`, for the remaining M2
  scope (kagent Agent CR, eval runner, gates), not for the shipped walking skeleton. It is a
  capture only: M2 has had no design pass, so the brainstorm gate still stands between it and a plan.

**Depends:** Phase 1
**Verify:** before minting, the real tree produces exactly one WARN, naming `repo-bootstrap`;
after minting, zero; both rules mutation-tested in both directions; a fixture with one task on
two Targets WARNs.

### Phase 5 — `/start` lookup, docs, changelog
- `/start` greps `initiatives/*.md` for `- task: <ref>` after resolving the ref, and reports the
  initiative slug, Target id and `depends_on`. It writes nothing.
- Update `docs/initiatives.md`: the new Target shape, the derivation table, the token vocabulary,
  and the `task_ref: none` consequence.
- Changelog fragment.

**Depends:** Phase 2
**Verify:** live-exercise `/start` on a task that sits on a Target and on one that does not —
no executable test covers a prose command; the docs' derivation table matches the implemented
mapping line for line.

### Checkpoint — pre-ship
- Full suite under `/bin/bash` 3.2, file count reconciled against the `tests: N passed` counter.
- Lint warning **sets** diffed before and after, not counts; attribute any move before accepting it.
- `shellcheck` on every touched script.
- Live exercise of `/start` on both paths, and of `/new-initiative` (it scaffolds the Target shape
  this plan changes).
- Human review, then PR. Initiative-file migrations stay local and ride nothing.

## Risks / open questions
- The token migration rewrites 19+ interactive status lines by hand. A mechanical edit at that
  volume is where a stray character lands in prose nobody re-reads — the baseline comparison is
  the only thing that would catch it, and it only covers the token, not the prose after it.
- Freezing six Targets removes their live link to archived plans. If one is ever reopened, it has
  no task and no plan pointer, and would have to be re-linked by hand.
- The duplicate-match rule assumes a task maps to at most one plan. If a task ever legitimately
  spawns two plans, the rule blocks it rather than expressing it; no such case exists today.
- `/start`'s lookup is a grep over four files. If initiatives ever reach the scale where that is
  slow, it becomes an index — the rejected alternative returns on a real measurement, not before.
