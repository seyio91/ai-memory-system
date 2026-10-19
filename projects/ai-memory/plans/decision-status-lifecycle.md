---
plan: decision-status-lifecycle
status: in_progress
created: 2026-10-04
owner: claude (orchestrator)
task_provider: notion
task_ref: 3e4f6850-c619-81fc-8fc3-d2478b7bedbf
---

# Decision status lifecycle

> Redesigned 2026-10-18 after #135 (proposal resolution at `/plan-done` + initiative close,
> suffix-based) landed on `main` unreleased; reviewed same day against the live initiative data.
> Supersedes the 2026-10-04 design.

## Goal

Make an initiative decision's status a dated field from a closed set (`proposed | confirmed |
rejected | superseded | retired`) instead of an id suffix, so the id never changes. Resolution
stays at close-out (#135), rewritten to edit the field. Structural lint, the write guard and a
derived count keep `proposed` from being written and never cleared.

## Success criteria

1. `initiatives/_template.md` documents the entry shape
   `- D<n> <proposed|confirmed|rejected|superseded|retired> <YYYY-MM-DD> — <decision>` with
   continuation lines (`  evidence:`, `  unconfirmed:`, `  binds:`, supersession keywords) and a
   frontmatter `legacy_through: D<n>` field. It says: status is never part of the id; a
   `D<n>-proposed` reference means `D<n>`; the date is bare (no brackets or parentheses) and is
   the date of the last status change; ids at or below `legacy_through:` predate the rules and
   are exempt from the date/`evidence:`/`unconfirmed:` checks; only the user confirms, and a
   confirm carries the date plus an `evidence:` continuation line naming the absorbing artifact.
   The example entry uses the continuation-line form, not inline `— evidence:`.
2. `lint-memory.sh` reports each of these as a WARN, scoped to `## Decision stream` of
   `kind: initiative` files:
   - a status outside the five-value set;
   - a non-legacy entry with no bare date in the date position (a bracketed or parenthesised
     date counts as missing);
   - a non-legacy `confirmed` with no `evidence:` continuation line;
   - a non-legacy `proposed` with no `unconfirmed:` continuation line;
   - an unmigrated old-shape entry (`- D<n>-proposed`, `- D<n>-rejected`, `- D<n>:`), reported
     as unmigrated and not as malformed;
   - any other line starting `- D` that is not exactly `- D<n>[a-z]? <status> <date> — …` with
     single spaces (double space, tab, missing `—`, double date, a date that is not a real calendar day (incl. `02-31`, non-leap `02-29`), `- Dx`, `- D5`
     alone) — one "malformed head" WARN;
   - a `legacy_through:` field that is present but not `D<n>` (including empty) — one WARN naming
     the field;
   - an id that appears on more than one entry head, unless every copy but one is
     `superseded` — one WARN naming the id.

   "Legacy" = a plain `D<n>` id (no letter suffix) with n ≤ the file's `legacy_through:`; no
   such field → nothing is legacy; lettered ids are never legacy. Continuation lines end at a
   blank line, the next entry head, or any column-0 line; fenced code blocks (``` or ~~~, any
   length ≥ 3, closed only by the same character at ≥ the opening length) are skipped and a `##`
   inside a fence does not end the stream. The fence, head and date grammar lives in one shared awk
   library loaded by lint, `initiative-status.sh` and the migration — no consumer re-implements it. CRLF is stripped. The stream
   heading matches case-insensitively. Each rule has
   a seeded-defect test in `test_lint_memory.sh`, mutation-proven. A clean template-shaped fixture
   passes; a fixture with legacy entries lacking date/evidence/unconfirmed passes; a scoping
   fixture with a bad entry in a section *after* the stream passes.
3. `memory_write_guard.sh` fires after a Write/Edit to `initiatives/*.md` (excluding
   `_template.md` and `.state/`). It reports the item-2 findings for that file in the same turn
   and stays silent on a clean file. Its header comment lists the new scope. Tests cover fire,
   silence and the exclusions.
4. `initiative-status.sh <slug>` prints `Decisions: N proposed (K legacy), oldest M days`. Age
   comes from dated non-legacy proposed entries; the oldest-age clause is omitted when there are
   none. The `advanced … with no new decision-stream entry` warning asks for
   `D<n> proposed <date>` with an `unconfirmed:` line. No new session-start output: the
   `test_session_start_memory.sh` payload differs only in that remedy string (its assertion
   updated to the new text). The existing stream-entry count regex
   (`^- D[0-9A-Za-z]*`) is unchanged and matches both shapes.
5. `commands/plan-done.md` Step 5b uses the field shape:
   - lists the matched initiative's proposed entries, legacy included, by running the read-only
     `initiative-status.sh <slug> --list-proposed` (shared grammar; fenced examples and malformed
     heads excluded; writes no snapshot) — no grep of its own;
   - **Confirm** asks for the absorbing artifact, then sets `confirmed <today>` and writes
     `  evidence: <artifact>` in place of `unconfirmed:`. No artifact named → entry stays
     `proposed`, `unconfirmed:` updated to say what is missing;
   - **Reject** sets `rejected <today>` and drops the `unconfirmed:` line;
   - a status change replaces the entry's existing date, never adds a second one;
   - **Leave** changes nothing;
   - edits only the status line and the `evidence:`/`unconfirmed:` lines, never the decision text.
6. Doctrine and docs use the new shape:
   - `doctrine/orchestrator.md` stream-first and phase-completion bullets; size test
     (`test_orchestrator_core_overlay.sh`, ≤ 14,336 B) passes — 705 B headroom today.
   - `docs/initiatives.md` states table rewritten for the five values and the date field;
     close rule: no `proposed` may remain; an agreed decision no repo absorbed is set to
     `retired <date>` at close, keeping its `unconfirmed:` line as the record of what was never
     done.
   - `commands/checkpoint.md` Step 3a and `commands/start.md` Step 1.5.
   - Changelog: `changelog.d/decision-status-lifecycle.feature.md` added, and #135's
     `resolve-decision-proposals.feature.md` reworded so 1.7.0 never announces the suffix rules.
   - `grep -rn -- '-proposed\|-rejected' doctrine/ commands/ docs/ initiatives/_template.md | grep -v -- '--list-proposed'`
     matches only lines explaining the legacy reference form.
7. `migrations/1.7.0-decision-status-field.sh`:
   - rewrites every suffix-shape head found in the live tree — `D<n>:`, `D<n>-proposed:`,
     `D<n>-proposed (<date>):`, `D<n>-proposed *(<qualifier>)*:`, `D<n> (<qualifier>)`, and
     lettered ids (`D<n>a:`) — to the field shape: `-proposed` → `proposed`, `-rejected` →
     `rejected`, bare `D<n>:` → `confirmed`, except a `-proposed` whose id also has a bare
     `D<n>:` entry in the same stream (the "original" of a later confirmation) → `superseded`;
     a parenthesised date is carried as the bare date;
     a prose qualifier moves to the start of the decision text, after the dash;
   - on already-field-shaped entries normalises the date token only: `[<date>]` → `<date>`;
     `[<date>; <text>]` / `[<date>, <text>]` → `<date>` with the text moved after the dash;
     `shipped` → `confirmed`;
   - sets `legacy_through: D<max id present>` in frontmatter only when it rewrote at least one
     head (an unrecognised line alone never stamps; a file it did not rewrite stays unmarked and
     `UPGRADING.md` says to mark it by hand);
   - leaves decision text, continuation lines and all references outside entry lines untouched;
   - is idempotent: a second run produces no diff;
   - has one fixture per head form above, is sandbox-tested, and has a matching `UPGRADING.md`
     section (`test_upgrading_doc.sh` green).
8. Local data: the migration has run on the four live initiatives. By hand,
   (`D12` checked and left `proposed`: it is a real open proposal; `D12a` is unrelated, not its
   confirmation); each choice
   recorded in the stream: `k8s-platform-agent`'s two mixed values (`D15 confirmed/proposed`,
   `D24 confirmed 2026-09-21 / proposed`) resolved to one status; `fineract-provisioning-dispatch`
   `D12a` (lettered, so never legacy) given a date and its `Evidence:` line lowercased.
   `lint-memory.sh` reports **no** decision-stream WARN on the migrated tree. Before/after WARN sets diffed, every change attributed.
9. Full suite green with file count reconciled against `tests: N passed`; `shellcheck` clean;
   `bash -n` passes under `/bin/bash` 3.2. No release is cut from `main` until this merges.

## Design

**Shape.** `- D<n> <status> <date> — <decision>`, continuation lines `binds:`, `evidence:`,
`unconfirmed:` and supersession keywords. The date is bare: 19 live `k8s-platform-agent` entries
already use it; the 20 bracketed and 7 parenthesised (eks) dates are normalised by the migration.
The other three initiatives use the suffix and get migrated. A `D<n>-proposed` reference anywhere
in the tree reads as `D<n>`; nothing rewrites references.

**Vocabulary.** Five values. `rejected` = never bound anything; `retired` = bound, then
withdrawn. `shipped` normalises to `confirmed`. Mixed values are rejected; a partial
confirmation is split with `QUALIFIED BY`.

**Confirm rule.** Only the user confirms (#135). A confirm needs an artifact: date +
`evidence:`. No artifact → stays `proposed`. `rejected` needs a date only.

**Trigger.** Close-out only: `/plan-done` Step 5b and initiative close, as #135 shipped. Step 5b
reads the field shape only, through `initiative-status.sh --list-proposed` — migrations run inside sync before `install.sh`, so upgraded
instances never pair new prose with old data.

**Consumer.** Structural rules in `lint-memory.sh`; `memory_write_guard.sh` runs them per file on
initiative edits. No prose matching.

**Count.** Derived by `initiative-status.sh`, never authored (the hand count in
`k8s-platform-agent` reads 20 against a real 22). Not surfaced at session start.

**Legacy.** Derived, not authored: the migration stamps `legacy_through: D<max>` per file and
lint exempts plain ids at or below it (lettered ids never — a split added later under an old
number would otherwise skip the checks) from the date/`evidence:`/`unconfirmed:` rules. No per-entry
marker — the migration cannot author dates or `unconfirmed:` lines (a judgment per entry), and an
authored marker is one more token to keep consistent. Legacy entries are counted; resolving one at
close-out writes a date and `evidence:` anyway, so it passes the rules it is exempt from. Trade-off
accepted: a legacy entry hand-edited to `confirmed` without evidence is not flagged; Step 5b
requiring the artifact is the control.

**Close.** No `proposed` survives close. Agreed but never absorbed → `retired <date>`, its
`unconfirmed:` line kept as the record; `rejected` stays reserved for "never adopted".

**Release.** 1.7.0 is held so #135's suffix rules never ship; this lands in the same release and
the migration is `1.7.0-*`.

Rejected:
- Keep #135's suffix shape: confirming still renames the id, and `k8s-platform-agent` would need
  migrating the other way.
- Accept both shapes permanently: every reader parses two grammars forever; Step 5b already
  misses k8s's proposals today.
- Bracketed date `[<date>]`: 20 vs 19 live entries, no parsing advantage, and the bracket is
  already used ad hoc for trailing text (`[2026-10-01; …]`).
- Authored `[legacy]` marker (on undated entries only, or on all pre-migration entries): the
  undated-only variant leaves ~22 `proposed`-without-`unconfirmed:` WARNs on first run; both
  variants add a token and an above-the-mark rule that id derivation makes unnecessary.
- At close, let `proposed` survive into the archive: `proposed` would mean nothing there.
- At close, reject as the only exit: records an agreed decision as never adopted.
- Lettered ids compared by number: a later `D6b` under `legacy_through: D32` skips every check.
- Map rejected → `retired`: loses "never adopted" vs "withdrawn".
- Evidence optional, or a close-out stamp as evidence: `confirmed` stops being checkable.
- Absorption-alone confirm: contradicts #135's "only the user resolves".
- Drain-on-append second trigger: a second doctrine rule for marginal gain.
- `reason:` line on rejected: an extra prompt; the decision text already says what was proposed.
- Cut 1.7.0 first, migrate in 1.8.0: consumers adopt `-rejected` for one release then convert.
- Confirm command rewriting references, a separate ledger, prose heuristics, an authored count,
  a diff-aware guard: unchanged reasons from the 2026-10-04 design.

## Decisions (locked)

- Scope is the status lifecycle only. `binds:`, the Binding index and `## State` belong to
  `initiative-structure` (task `3e4f6850-c619-81b4-bb8e-ee5009443544`).
- Field shape canonical; five-value closed set; bare date.
- Legacy is derived from `legacy_through:`; no per-entry marker; lettered ids never legacy.
- At initiative close, an agreed-but-unabsorbed proposal becomes `retired`.
- An old `-proposed` with a same-number confirmed twin migrates to `superseded`; duplicate ids
  are allowed only when all copies but one are `superseded`.
- User confirms; confirm requires an evidence artifact, else stays proposed; rejected = date only.
- Resolution at close-out only (`/plan-done` Step 5b, initiative close).
- Structural checks only, lint + write guard. Derived count, no session-start alert.
- Migration mechanical only, `1.7.0-*`; 1.7.0 held until this merges.

## Phases

### Phase 1 — shape + lint rules
`initiatives/_template.md` (stream section, example entry, `legacy_through:` in frontmatter),
`scripts/lint-memory.sh` (entry-line parser, decision-stream rules, `legacy_through:` read; the
initiative loop starting at `for f in "$MEMORY_DIR"/initiatives/*.md`), `scripts/tests/test_lint_memory.sh`.
**Verify:** criteria 1–2. `/bin/bash scripts/tests/test_lint_memory.sh` green. Each new rule's
mutation fails its own case (`cmp` confirms the mutation landed). Real-tree lint before/after:
every added WARN comes from pre-migration data (unmigrated heads in the three suffix-shape files;
k8s field-shaped entries without `legacy_through:`); P6 clears them.

### Phase 2 — write guard on initiatives
**Depends:** P1
`scripts/hooks/memory_write_guard.sh` (new path branch + header scope list), its test, harness
wiring. Change a matcher only if the current one misses `initiatives/`.
**Verify:** criterion 3. Guard test green. A real Edit on a scratch initiative with a seeded bad
status produces the report; a clean edit produces none. Latency measured on the 822-line
`k8s-platform-agent.md`.

### Phase 3 — derived count
**Depends:** P1
`scripts/initiative-status.sh` (reuses P1's grammar, not its code — lint is not sourced),
`scripts/tests/test_initiative_status.sh`.
**Verify:** criterion 4. Tests green with new/old/mixed-shape fixtures and a `legacy_through:`
fixture. `test_session_start_memory.sh` payload unchanged. Real-tree run on all four initiatives
prints the line.

### Phase 4 — close-out, doctrine, docs, changelog
`commands/plan-done.md` (Step 5b), `doctrine/orchestrator.md`, `docs/initiatives.md`,
`commands/checkpoint.md`, `commands/start.md`, `changelog.d/decision-status-lifecycle.feature.md`,
`changelog.d/resolve-decision-proposals.feature.md`.
**Verify:** criteria 5–6. The criterion-6 grep holds; the doctrine size test passes; live-exercise
Step 5b on a scratch initiative: confirm with artifact, confirm without artifact, reject, leave.

### Phase 5 — migration
**Depends:** P1
`migrations/1.7.0-decision-status-field.sh`, `UPGRADING.md` section, sandbox test with one
fixture per head form in criterion 7.
**Verify:** criterion 7. On a sandbox copy of all four live initiatives the first run changes only
entry lines and frontmatter; the second run's diff is empty; every eks date survives
(`grep -c '2026-' before == after`). `test_upgrading_doc.sh` green. P1 lint on the migrated
sandbox reports only the hand-resolve set (`D12a`, `D15`, `D24`).

### Phase 6 — migrate local initiatives
**Depends:** P5
Run the migration on the live `initiatives/` tree (local, gitignored, no commit). Resolve by
hand: `k8s-platform-agent` `D15` and `D24` (mixed values), `fineract-provisioning-dispatch`
`D12a` (date + lowercase `evidence:`).
**Verify:** criterion 8. Diff WARN sets before/after, attribute every line.
`initiative-status.sh` on each slug prints its count.

### Pre-PR checkpoint
**Depends:** P1, P2, P3, P4, P5, P6
Criterion 9: full suite, shellcheck, lint diff. Cross-model `scope: final` validator pass at
`risk: medium` (`risk: high` for P2 — the guard runs on every write — and P5 — it rewrites user
data). Live-exercise `/checkpoint` Step 3a on its default path. Then branch and PR.

## Risks / open questions

- **Count visibility.** Seen only via `initiative-status.sh`; close-out prompts partly cover it.
  Revisit a session-start alert if `proposed` keeps growing after migration.
- **Legacy backlog.** 39 legacy `proposed` entries (aws 1, eks 7, fineract 9, k8s 22) need a
  per-entry judgment; they drain through future close-outs, outside this plan. Because legacy is
  derived, nothing nags about them — the derived count is the only signal.
- **Migration grammar.** The seven head forms are what the live tree has today; a consumer's
  initiative may hold an eighth. The unmigrated-shape lint rule catches what the migration
  misses, and the migration must never alter a line it does not fully match.
- **Release hold.** Anything else merging to `main` meanwhile also waits for 1.7.0. If the hold
  must break, re-derive the migration version and keep #135's fragment from shipping as written.
- **Guard cost.** Lint logic on every initiative write; largest file is 822 lines. Measure in P2;
  if noticeable, scope the guard to decision-stream rules only.
- **Doctrine headroom.** 705 B under the size cap; P4 edits the bullet #135 just lengthened.
- **Replay can exempt newer entries (accepted 2026-10-19).** If `.applied-version` is lost and the
  migration replays, a post-1.7.0 initiative containing even one hand-typed old-format head (e.g.
  `- D3: oops`) is stamped `legacy_through:` and its real entries skip the date/`evidence:`/
  `unconfirmed:` checks. Needs a lost marker plus a stray old-format line; documented in
  `UPGRADING.md`. Rejected fixes: stamp only files with no field-shape heads (forces hand-marking
  mixed pre-1.7 files); per-entry `[legacy]` marker (reverses the derived-legacy decision).
- **Stray tooling reference.** `k8s-platform-agent`'s Binding index fence names
  `scripts/regenerate-bindings.sh`, which does not exist. Belongs to `initiative-structure`.
