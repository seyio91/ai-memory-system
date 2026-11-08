---
plan: checkpoint-script-split
status: in_progress
created: 2026-11-08
owner: claude (orchestrator)
task_provider: notion
task_ref: 412f6850-c619-813d-8d20-cae3eb548392
---

# Plan — Split /checkpoint: model synthesizes, script does bookkeeping

## Goal
Move `/checkpoint`'s mechanical rules (match, rank, merge duplicates, lookups, reconcile enforcement, write, report) into a deterministic `scripts/checkpoint.py`, so the model only emits a small JSON digest (five fields + per-bullet dispositions) and duplicate entries stop arising from mis-applied rules or incomplete identifiers.

**Before:** the model applies ~70 lines of prose rules from `commands/checkpoint.md` and hand-edits `working.md`; mis-applied matching produced duplicates (#153), and a planning-time `task <ref>` entry and a later `plan <slug>` entry for the same work never match.
**After:** `/checkpoint` runs `checkpoint.sh prepare` → model writes a JSON digest → `checkpoint.sh apply`; identifiers are expanded from disk before matching, duplicates are merged mechanically, every prior Next/Blockers bullet must carry a disposition or `apply` fails closed; Codex `--for-codex` uses the same engine.

## Non-goals
- `/promote-memory`, `/checkpoint-archive`, `/plan-done` — follow-up tasks only if this pays off.
- Any cheap-model (Haiku) step.
- Step 3a (initiative decision-stream append) — stays in command prose.
- Changing the on-disk checkpoint entry format.
- A lint rule for identifier-sharing entries (deferred).

## Success criteria
- R1 [acceptance] `bash scripts/checkpoint.sh prepare --piece plan:<slug> --piece task:<ref> --piece pr:<n>` prints JSON: expanded identifiers per piece, matched target + duplicates per piece, numbered prior Next/Blockers bullets with lookup annotations, and a `would_create` warning when a new entry would share any identifier with an existing one.
- R2 [acceptance] Identifier expansion: `plan:<slug>` adds the plan's `task_ref:`; `task:<ref>` adds the slug of the plan whose `task_ref:` equals it; PRs already on an entry sharing those identifiers are added. Fixture: planning-time `task`-only entry + later `plan`-only session → one entry, not two.
- R3 [acceptance] `apply` reads the digest on stdin; exits non-zero with a named error when any prior bullet id lacks a disposition, an id is unknown, a `moved` disposition names no home, or a required field is missing — and leaves `working.md` byte-identical on failure.
- R4 [parity] Match/rank/merge/write behaviour equals the prose rules 1–13 and Step 4 — fixture cases built from `docs/file-formats.md` "Why the `/checkpoint` rules" worked examples plus the #153 duplicate-merge case, each asserting exact expected `working.md` output.
- R5 [parity] Entries not written or merged stay byte-identical; `## Cross-project learnings` untouched — vs `29c0ad0` fixture outputs.
- R6 [acceptance] Lookups (`gh pr view`, `taskctl get`, `todo.md` boxes, plan `status:`) run in `prepare`; a failing lookup yields `(state unknown)`, never an error exit; prior annotations are replaced, not stacked. Tests stub `gh`/`taskctl` on PATH (hermetic).
- R7 [acceptance] `apply` stdout carries the Step 5 report: per-entry path/heading/summary/merged duplicates, side items with no home, and the over-window `/checkpoint-archive` hint (`AI_MEMORY_CHECKPOINT_WINDOW`, default 5).
- R8 [acceptance] `commands/checkpoint.md` drops the Steps 2–4 rules in favour of prepare → digest → apply + digest schema + Step 3a; `codex-mem-checkpoint.sh --for-codex` emits `prepare` output and the apply instruction; interactive `$EDITOR` mode unchanged.
- R9 [acceptance] `bash scripts/run-tests.sh` green (full run); touched shell passes `/bin/bash -n` and runs under `PATH="/usr/bin:/bin:$PATH" /bin/bash`; `docs/scripts.md` lists the script and `check-docs.sh` passes; `changelog.d/<id>.feature.md` present.

## Design
- **Two-call flow.** `checkpoint.sh prepare --working <path> --piece <kind>:<id>…` → JSON context; model writes digest; `checkpoint.sh apply --working <path> < digest.json` → writes + report. Model never re-reads `working.md` itself. Thin bash wrapper over `scripts/checkpoint.py` (Python, stdlib only; matches the `taskprovider` precedent).
- **Digest schema (per piece):** `{pieces:[{ids:[…], task, done:[…], next:[…], blockers:[…], resume, dispositions:{"<bullet-id>": "done"|"restate"|{"moved":"<home>"}}}], side:{done:[…], next:[…]}}`. Script owns dates (from `--today`, passed by the command from the identity injection), headings, ordering, Done grouping, Task-paragraph identifier appends.
- **Identifier expansion before matching** — from plan frontmatter and existing entries on disk; replaces the prose "compare literally, never search" with a deterministic search over known stores only.
- **Fail closed.** No fallback to prose rules; model fixes the digest and re-runs `apply`. Atomic write (temp file + rename).
- **Entry parser** shares boundary rules with `checkpoint-archive.sh` (fence-depth-0 `### ` headings) — port its logic and pin both with one shared fixture.
- **Codex** `--for-codex` routes to `prepare`; interactive `$EDITOR` mode is the Two-Path hand route.
- Rejected: model rewrites Next/Blockers wholesale → "none dropped silently" stays trust-based.
- Rejected: markdown digest + bash parser → multi-line fields fragile under bash 3.2.
- Rejected: single `apply` call → model text-matches bullets, lookups stay with the model.
- Rejected: Haiku subagent for piece-split → loses session context, adds cost for a small judgment.
- Rejected: fallback to prose rules on reject → keeps both paths and the token cost.

**Builds on:** `commands/checkpoint.md`, `scripts/checkpoint-archive.sh` (parser), `scripts/taskctl`, `harnesses/codex/scripts/codex-mem-checkpoint.sh`, `docs/file-formats.md` "Why the `/checkpoint` rules", PR #153.

## Decisions (locked)
- Base: `29c0ad0d376d54ee0664d7f942f1e2ad3a278aaa` (origin/main at plan time).
- Dispositions by bullet id, enforced by `apply`.
- JSON on stdin, Python core, bash wrapper.
- Scope `/checkpoint` only; no Haiku; Step 3a stays prose; Codex routed.
- Identifier expansion from plan frontmatter + existing entries.

## Phases
### Phase 1 — Parser, prepare, identifier expansion
- `scripts/checkpoint.py` entry parser (port `checkpoint-archive.sh` boundaries), `prepare` subcommand: piece args, identifier expansion, match/rank (rules 1–9), numbered prior bullets, lookups with stubs-friendly invocation, `would_create` warning.
- `scripts/checkpoint.sh` wrapper.
- `scripts/tests/test_checkpoint.sh` + `scripts/tests/fixtures/checkpoint/` for prepare cases incl. the task-then-plan duplicate case.

**Files touched:** `scripts/checkpoint.py` (new), `scripts/checkpoint.sh` (new), `scripts/tests/test_checkpoint.sh` (new), `scripts/tests/fixtures/checkpoint/*` (new), `scripts/tests/test_checkpoint_archive.sh`
**Risk:** medium
**Depends:** none
**Verify:** R1, R2, R6 — `bash scripts/run-tests.sh --only checkpoint` passes prepare cases with stubbed `gh`/`taskctl`.

### Phase 2 — apply: validate, merge, write, report
- `apply` subcommand: digest validation (fail closed, byte-identical on failure), duplicate fold-in, Task-paragraph appends, Done groups, Next/Blockers/Resume replace, new-entry shape, ordering (rules 10–13), file bootstrap, Step 5 report, atomic write.
- Parity fixtures from `docs/file-formats.md` worked examples + #153 case.

**Files touched:** `scripts/checkpoint.py`, `scripts/tests/test_checkpoint.sh`, `scripts/tests/fixtures/checkpoint/*`
**Risk:** high
**Depends:** Phase 1
**Verify:** R3, R4, R5, R7 — fixture suite asserts exact `working.md` output per case and unchanged file on every rejection case.

### Phase 3 — Wire command, Codex, docs, changelog
- Rewrite `commands/checkpoint.md` to prepare → digest → apply (schema, Step 3a kept); point "Why the rules" rationale at the script.
- `codex-mem-checkpoint.sh --for-codex` → `prepare` output + apply instruction.
- `docs/scripts.md`, `docs/file-formats.md`, `docs/harnesses/codex.md`, `docs/harnesses/claude.md` as needed; `changelog.d/checkpoint-script-split.feature.md`.

**Files touched:** `commands/checkpoint.md`, `harnesses/codex/scripts/codex-mem-checkpoint.sh`, `docs/scripts.md`, `docs/file-formats.md`, `docs/harnesses/codex.md`, `docs/harnesses/claude.md`, `changelog.d/checkpoint-script-split.feature.md` (new)
**Risk:** medium
**Depends:** Phase 2
**Verify:** R8, R9 — full `bash scripts/run-tests.sh` green, `check-docs.sh` passes, bash 3.2 checks pass, and a live `/checkpoint` on a scratch working file writes via the script.

## Risks / open questions
- Saving unmeasured — settle by comparing `/checkpoint` output tokens on a real session before/after (post-merge).
- Notion-backed `taskctl get` latency in `prepare` with several prior bullets — measure in Phase 1; parallelise or cap if slow.
- Prose rules contain judgment the parity fixtures may not cover (e.g. mixed bullets "Phases 3–4; also bump CHANGELOG") — those stay model-side via `restate`/split bullets in the digest; document in the command.
- Lint rule for entries sharing identifiers — deferred.
- Python suite discovery in `run-tests.sh` targets `taskprovider/tests`; tests here are bash-driven to land in the tests stage without rewiring.
- [feasibility CAUTION] Phase 3's live `/checkpoint` Verify has no dry-run form; Step 3a can append to an active initiative's `## Decision stream` unasked. Run it with no active initiative touching ai-memory, or with an overridden working path + initiatives root.
- [feasibility note] Shared parser fixture pins `checkpoint-archive.sh` too — `scripts/tests/test_checkpoint_archive.sh` added to Phase 1 Files touched.
- [feasibility note] `check-docs.sh` follows `source` chains from the "Used by" script only — a `docs/scripts.md` row for `AI_MEMORY_CHECKPOINT_WINDOW` must name the file that actually reads it (`checkpoint.py`), or the wrapper reads it.
