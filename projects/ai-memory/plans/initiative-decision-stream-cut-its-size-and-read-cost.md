---
plan: initiative-decision-stream-cut-its-size-and-read-cost
status: draft
created: 2026-11-19
owner: claude (orchestrator)
task_provider: local
task_ref: initiative-decision-stream-cut-its-size-and-read-cost
---

# Plan — Initiative decision stream: narrow reads, pointer index, scripted append

## Goal
A session working an initiative Target loads the whole initiative file (about 40.6k tokens for vault-eks, 83% of it the decision stream) at `/start`, before delegating, and again for every decision append. Replace those whole-file reads with a reader that prints the Target's slice plus a one-line pointer for every other live decision, and a script that appends a decision without reading the file. The stream itself keeps its format and stays the record.

**Before:** `/start` Step 1.5, the doctrine's "consult the initiative file" and every decision append each read the whole file; an append costs about 40.9k tokens and two parallel sessions can take the same D-id.
**After:** `/start` loads one `initiative-read.sh --start` bundle of at most 36,000 bytes (10k tokens) for each of the three replay Targets on vault-eks, with every live decision either in full or visible as a pointer; a decision append is one `initiative-decide.sh` call that returns a unique D-id; no command or doctrine line tells a session to read the whole initiative file.

## Non-goals
- No archive file, no split of the stream into a second file, no migration of existing initiatives.
- No rewrite of existing decision heads; no wholesale short-heads conversion.
- No Read hook or other enforcement of the narrow read (instructions only).
- No topic-filter or citation-hop reader modes; the index plus fetch-by-id replaces them.
- No change to `## Current rules` (ids only), `initiative-render.sh` output or `initiative-status.sh` output.
- No required `depends:` line; citations stay prose plus `AMENDS`/`SUPERSEDES`.

## Success criteria
Token figures are bytes / 3.6. "vault-eks copy" is a copy in a temp memory tree with no `config.local.sh`.

- R1 [acceptance] `initiative-read.sh vault-eks --start <target-id>` prints, in order: the Target block, `## Now`, `## Current rules`, every decision the Target block cites in full with its live amenders and the live replacements of superseded entries, then one pointer line for every other live decision. The set of ids printed in full plus the set printed as pointers equals the set of live ids in the stream (checked by script for all three replay Targets: `tpe-stacks/vault-onboarding`, `k8s-addons/vault-estate-rollout@staging`, `inception/vault-audit-pipeline`).
- R2 [acceptance] The `--start` output is at most 36,000 bytes for each of the three replay Targets on the vault-eks copy.
- R3 [acceptance] The reader is read-only and verbatim: the initiative file's sha256 is unchanged after every mode, and every line printed in full exists byte-for-byte in the stream. A pointer line uses the entry's `rule:` text when present, else the head text cut at a space within the pointer length; it carries the id, status, topic, any "(as amended by …)" marker, and a flag when the entry's `binds:` names the Target's project.
- R4 [acceptance] `initiative-decide.sh` appends one decision without the caller reading the file and prints the new D-id; invalid input (no `unconfirmed:` on a proposed entry, confirmed without `evidence:`, unknown topic, impossible date, AMENDS of a missing id) exits 2 and leaves the file byte-identical; 8 simultaneous appends yield 8 distinct ids and 8 entries; a hand edit following the documented rule produces the same bytes as the script; `initiative-render.sh --check` exits 0 after the script's own render.
- R5 [acceptance] `lint-memory.sh` WARNs, for entries after `legacy_through` only, on: an entry with no `binds:` line (`binds: none` satisfies it); a head whose decision text exceeds 300 characters with no `rule:` line; a prose-only amendment using "narrows", "corrects", "refines", "replaces", "reverses" or "clears" with no `AMENDS` line. Legacy entries produce none of the three.
- R6 [acceptance] `commands/start.md`, `commands/checkpoint.md`, `commands/plan-done.md` and `doctrine/orchestrator.md` name `initiative-read.sh` / `initiative-decide.sh` for consulting and appending, and no longer contain an instruction to read the whole initiative file or the whole `## Decision stream`; `docs/initiatives.md` documents both scripts, the `rule:` and `binds:` lines and the hand equivalents.
- R7 [acceptance] A real `/start` replay (a fresh session following the new Step 1.5 on the vault-eks copy) for each of the three replay Targets loads at most 36,000 bytes from the initiative before the design gate, and D58, D93, D63 (for tpe-stacks) and D18, D81, D20 (for audit) each appear in full or as a pointer in what it loaded. Report the bytes of any follow-up fetch by id separately.
- R8 [parity] `initiative-render.sh <slug>` and `initiative-status.sh <slug>` (table, `--tsv`, `--list-proposed`) output on an unmodified initiative is identical — vs `30a3494` byte-for-byte.
- R9 [acceptance] `bash scripts/run-tests.sh` (full gate, signing off) is green, and the touched suites pass under `PATH="/usr/bin:/bin:$PATH" /bin/bash`; `/bin/bash -n` passes on every new or changed script.
- R10 [acceptance] After the vault-eks hand pass: every non-legacy entry has a `binds:` line, every prose-only amendment found by the widened lint check has an `AMENDS` line and its forward pointer, every title-only head has a `rule:` line; `initiative-render.sh vault-eks --check` exits 0, lint reports 0 ERRORs and none of the three R5 WARNs for vault-eks; a diff against the pre-pass copy shows only added continuation lines and added ` → D<n>` forward pointers, no changed decision text.

## Design
Chosen approach, from the six-agent exploration recorded in investigation `initiative-decision-stream-size` (section "Exploration results"):

- **`scripts/initiative-read.sh` (new, read-only), built on `lib/decision-stream.awk`.** Modes: `--target <id>` (one Target block), `--section now|rules|<heading>`, `--decisions <ids>` (full entries), `--index` (one pointer line per live decision), `--start <target-id>` (the `/start` bundle), `--next-id`. In full-entry output a non-live entry is never printed in full: the reader follows its `→ D<n>` pointer and `SUPERSEDES` lines to live replacements and prints one line for the dead entry; every entry printed in full brings every live entry whose `AMENDS` names it. Neither rule counts as a citation hop.
- **`--start` loads in full only what the Target block cites** (D-ids written in the block, ranges and letter sub-items resolved), plus amenders and replacements. Decisions whose `binds:` names the Target's project are flagged in the index, not auto-loaded: auto-loading would pull most of the stream for a project such as `k8s-addons`. The session fetches more with `--decisions`.
- **Pointer line:** `- D58 confirmed [postgres] (as amended by D60, D90) [binds] — <rule: text, else truncated head>`. `rule:` is a new optional continuation line holding one sentence; heads are not rewritten.
- **`binds:`** is the continuation line `docs/initiatives.md` already documents and the stream uses zero times. Value: comma-separated project names, or `none`.
- **`scripts/initiative-decide.sh` (new).** Computes the next D-id under a `mkdir` lock at `initiatives/.state/<slug>.lock`, validates input, writes the entry after the last non-blank stream line via temp file + `mv`, adds forward pointers for `AMENDS`/`SUPERSEDES`, runs `initiative-render.sh --write`, prints the id. The hand rule (highest head number plus one; continuation order `topic:`, `rule:`, `binds:`, `AMENDS`, `SUPERSEDES`, rest; pointers; render) is documented and yields the same bytes.
- **Lint:** three WARNs scoped to entries after `legacy_through` (R5); the prose-amendment verbs widen `ds_cand_scan`.
- **Instructions:** `/start` Step 1.5 runs `--start`; the doctrine's "consult the initiative file before delegating" names the reader; `/checkpoint` Step 3a, `/plan-done` Step 5b and the doctrine's stream-first lines use `initiative-decide.sh` or, for hand edits, a tail-only read.
- **vault-eks hand pass** after merge: `binds:` on non-legacy entries (51 already list repos in prose), `AMENDS` for the 18 prose-only amendments, `rule:` for title-only heads (estimated 25–30). Model drafts, user approves, applied after a live-hash check.

Rejected alternatives:
- Short heads for all 87 long heads → grows the file 16%, costs more than a reader alone, needs user review of 87 rewritten rules, and a head cannot be updated after an AMENDS.
- Topic-filtered reader with citation hops → topic choice is a blind judgement before the session has read anything; 20–25% saving on the wide Target; needed decisions (D63, D18, D81, D20) reachable by neither topic nor citation.
- Archive D1–D43 → 41 of 43 archived entries are live (44% of Current rules); every replay Target needs the archive, so nothing is saved; `--write` silently empties rule rows after the move.
- Split the stream into its own file → the same saving is a line-range read of the single file; unmodified readers fail silently; needs a migration and two-file appends.
- Narrow reads without the index → 2.2–3.4k tokens but omitted D58 and D93 for tpe-stacks.
- Required `depends:` line / load "real dependencies only" → real dependencies are about 28% of citations and not separable mechanically; the missed decisions were not cited anywhere.
- Read hook → deferred; Claude-only and bypassed by `cat`.

**Builds on:** investigation `initiative-decision-stream-size`; `scripts/lib/decision-stream.awk`; `scripts/initiative-render.sh`, `scripts/initiative-status.sh`; prototypes under `/tmp/ds-explore/a2-topic-reader/` (`initiative-decisions.sh`: prose id parsing, supersession and amendment rules, pointer lines) and `/tmp/ds-explore/a5-narrow-reads/` (`initiative-read.sh`, `initiative-decide.sh`, race tests) — reference only, temp files that may be gone; plans `initiative-now-view-per-env-targets` (PR #155) and `initiative-now-view-surface-user-actions-and-blocking-decisions` (PR #157).

## Decisions (locked)
- Base commit: `30a34941a5520443676dae7bcf73e0a75e631cb0` (main).
- Goal is token cost per session only; human readability of the stream is not a measure (user, 2026-11-19).
- Approach: narrow reads + pointer index + locked append script (user, 2026-11-19).
- `binds:` line: lint WARN on entries without it, plus backfill on vault-eks (user, 2026-11-19).
- Pointer quality: optional `rule:` continuation line; decision heads are never rewritten (user, 2026-11-19).
- Enforcement: instructions only, no hook (user, 2026-11-19).
- One PR for Phases 1–4 with a `feature` changelog fragment; no migration.
- Tokens are reported as bytes / 3.6.

## Phases
### Phase 1 — Reader: `initiative-read.sh`
- Add `scripts/initiative-read.sh` with the modes in Design; reuse `lib/decision-stream.awk` for parsing, add only what the pointer line needs (`rule:`, `binds:` capture) to the lib.
- Parse D-ids in a Target block: plain ids, ranges (`D36–D44`, `D36-44`), letter sub-items (`D15b` → D15).
- Implement supersession and amendment following, the pointer line, the `[binds]` flag (match on the Target id's project segment), and the first output line (entry count, highest id).
- Errors: unknown slug, Target or id exits 2 with a message on stderr; a symlinked initiative file is refused, as in `initiative-render.sh`.
- Add `scripts/tests/test_initiative_read.sh` with synthetic fixtures only (no vault-eks text): each mode, supersession chains, amenders, ranges, `rule:` vs truncated head, truncation under `LC_ALL=C`, verbatim and read-only checks, error exits.

**Files touched:** `scripts/initiative-read.sh` (new), `scripts/lib/decision-stream.awk`, `scripts/tests/test_initiative_read.sh` (new), `scripts/tests/test_decision_stream.sh`
**Risk:** medium
**Depends:** none
**Verify:** R1, R2, R3, R8 — on a vault-eks copy the three `--start` runs satisfy the full-plus-pointer = live-ids check and the 36,000-byte bound, the file sha256 is unchanged, `test_initiative_read.sh` and `test_decision_stream.sh` pass under `/bin/bash` 3.2, and render/status output on the copy is identical to `30a3494`.

### Phase 2 — Append: `initiative-decide.sh`
- Add `scripts/initiative-decide.sh`: arguments for status, date, topic, head text, `rule:`, `binds:`, `evidence:`/`unconfirmed:`, `--amends`, `--supersedes`, free continuation lines (text passed without shell interpretation), `--no-render`.
- Lock, validate, write via temp file + `mv` keeping the file mode, add forward pointers, self-check (exactly one more valid head), render, print the id.
- Add `scripts/tests/test_initiative_decide.sh`: validation failures leave the file byte-identical, plain/amending/superseding appends, 8-way race, no-lock control proving the race test can fail, hand-edit byte equality, stale-lock removal.

**Files touched:** `scripts/initiative-decide.sh` (new), `scripts/tests/test_initiative_decide.sh` (new)
**Risk:** medium
**Depends:** none
**Verify:** R4 — `test_initiative_decide.sh` passes under `/bin/bash` 3.2 with the 8-way race giving 8 distinct ids and 8 entries. Lock behaviour stated and tested: concurrency — a `mkdir` lock held across read, write and render, waiters retry; timeout — a waiter gives up after a fixed bound and exits non-zero without writing, a lock older than 2 minutes is treated as abandoned and removed; cancellation — a trap removes the lock and temp file on exit or signal, and an interrupted run leaves the initiative file either unchanged or fully written (`mv` is the only write); failure — a failed validation, self-check or render exits non-zero, releases the lock and is never cached, and a failed render after a successful write is reported with the new id so the caller can re-render.

### Phase 3 — Lint: `binds:`, `rule:`, prose amendments
- `lib/decision-stream.awk` / `lint-memory.sh`: the three WARNs of R5, scoped to entries after `legacy_through`; widen `ds_cand_scan` verbs; accept `rule:` and `binds:` as known continuation keywords, `binds: none` as explicit.
- Before changing anything, enumerate every rule and reader that consumes continuation lines or `ds_cand_scan` output (lint rules, `memory_write_guard.sh`, render, status, both migrations) and decide per consumer whether the new keywords or verbs change its behaviour; record the list in the phase return.
- Tests in `test_lint_memory.sh` and `test_decision_stream.sh`: each WARN fires, each is silent on legacy entries and on satisfied entries, and each test is mutation-checked (it fails when the rule is removed).

**Files touched:** `scripts/lib/decision-stream.awk`, `scripts/lint-memory.sh`, `scripts/tests/test_lint_memory.sh`, `scripts/tests/test_decision_stream.sh`, `scripts/tests/test_memory_write_guard.sh`
**Risk:** medium
**Depends:** none
**Verify:** R5, R8 — the new cases pass under `/bin/bash` 3.2; on the vault-eks copy the lint warning set differs from the `30a3494` script's set only by the three new WARN kinds, none of them on an entry at or before `legacy_through`; render/status output unchanged.

### Phase 4 — Commands, doctrine, docs, template, changelog
- `commands/start.md` Step 1.5: run `initiative-read.sh <slug> --start <target-id>` in place of the two reads; fetch more with `--decisions`; append with `initiative-decide.sh`.
- `commands/checkpoint.md` Step 3a, `commands/plan-done.md` Step 5b, `doctrine/orchestrator.md` (consult before delegating; decision stream at phase completion; stream-first capture): name the scripts; hand edits read only the stream tail.
- `docs/initiatives.md` (reader, append script, `rule:`, `binds:`, hand equivalents, lint rules), `docs/file-formats.md`, `docs/scripts.md` rows, `initiatives/_template.md` (authoring note for `rule:` and `binds:`), `changelog.d/initiative-narrow-reads.feature.md`.
- Run the doc and partial gates; live-exercise every command line written into prose against a temp tree.

**Files touched:** `commands/start.md`, `commands/checkpoint.md`, `commands/plan-done.md`, `doctrine/orchestrator.md`, `docs/initiatives.md`, `docs/file-formats.md`, `docs/scripts.md`, `initiatives/_template.md`, `changelog.d/initiative-narrow-reads.feature.md` (new), `scripts/tests/test_initiative_render.sh`
**Risk:** low
**Depends:** Phase 1, Phase 2, Phase 3
**Verify:** R6, R9 — a grep of the four instruction files finds no whole-file or whole-stream read instruction and finds both script names; every command line quoted in the changed prose runs as written against a temp tree; the full gate is green with signing off.

### Phase 5 — Replay `/start` for the three Targets
- On a vault-eks copy in a temp tree with the branch's engine, run a fresh session per replay Target that follows the new Step 1.5 only, and record every initiative byte it loads (bundle, follow-up fetches).
- Check the six known misses are in full or visible as pointers; note any decision the session fetched by id and why.
- Record the measured loads (ids and byte counts only, no vault-eks text) in the investigation and report against the 40.6k-token baseline. A miss or an over-bound load goes back to Phase 1 or Phase 4, not forward.

**Files touched:** `projects/ai-memory/investigations/initiative-decision-stream-size.md`
**Risk:** low
**Depends:** Phase 4
**Verify:** R7 — the three replay transcripts' initiative loads are each at most 36,000 bytes before the design gate, and D58, D93, D63, D18, D81, D20 are present in full or as pointers for their Target.

### Phase 6 — vault-eks hand pass
- After the PR merges and `/sync-system` runs: diff the live `initiatives/vault-eks.md` against the 2026-11-19 09:51 copy first (it changed at 10:24 from another session).
- Model drafts in a temp directory: `binds:` for every non-legacy entry, `AMENDS` plus forward pointers for the prose-only amendments lint now reports, `rule:` for title-only heads. User reviews the draft; apply only after approval and a live-hash check; re-render.
- Decide with the user whether `legacy_through` entries also get `rule:` lines where their pointer is title-only (lint does not ask for it).

**Files touched:** `initiatives/vault-eks.md`
**Risk:** medium
**Depends:** Phase 4, Phase 5
**Verify:** R10 — `initiative-render.sh vault-eks --check` exits 0, lint shows 0 ERRORs and none of the three new WARNs for vault-eks, and the diff against the pre-pass copy contains only added continuation lines and added forward pointers.

## Risks / open questions
- **`rule:` goes stale after an AMENDS.** The pointer carries "(as amended by D<n>)" but the sentence is not updated. Accepted; a session must fetch a decision before acting on a pointer, and Step 1.5 says so.
- **Lint WARNs on other instances.** The `binds:` and long-head WARNs fire on every non-legacy entry of every existing initiative after upgrade. Open: is that acceptable noise, or should the WARNs apply only to entries dated on or after the release? Settle before Phase 3 lands.
- **Wide Targets stay expensive.** tpe-stacks was estimated at about 17k tokens once follow-up fetches are counted (inferred from measured parts, not run). Phase 5 measures it.
- **No exploration agent replayed a real session.** Every "needed decision" in the investigation is one reader's judgement; Phase 5 is the first real test.
- **Nothing enforces the narrow read.** A session can still `Read` or `cat` the whole file; other harnesses get the same prose and no check. Read hook deferred.
- **A decision that binds a project but is uncited and has no `binds:` line** is visible only as an unflagged pointer. Legacy entries are exempt from the `binds:` WARN, and 41 of them are live.
- **Residual races in the append script:** a hand Edit or a bare `initiative-render.sh --write` does not take the lock; cross-machine file sync is not covered.
- **A scripted append is a Bash write,** so `memory_write_guard.sh` does not lint it; the script's own validation is the only check.
- **Prose id parsing is tuned on vault-eks** (foreign-id skip rules); another initiative may quote foreign decision ids differently.
- **The three replay Targets have no `- task:` line,** so `/start`'s initiative grep does not match them today; Phase 5 must drive Step 1.5 with the Target id directly.
- **The live vault-eks changed at 10:24 on 2026-11-19** (146,272 → 146,521 bytes), attributed to another session, unverified. All exploration figures are for the 09:51 copy.
