---
plan: doc-vs-code-consistency-test
status: active
created: 2026-07-10
owner: claude (orchestrator)
task_provider: notion
task_ref: 397f6850-c619-818c-a0ee-e17736b1bfe6
---

# Doc-vs-code consistency test

## Goal

Gate `run-tests.sh` on a mechanical check that every env var documented in the
`docs/scripts.md` table exists in code **and** appears in the script its `Used by` column
names — so documented-nonexistent and wrong-consumer drift fail the build instead of
surviving review.

## Why the captured rationale no longer holds

Re-measured 2026-07-10, per the repo's own rule that *a measurement taken to justify a task
is the one most likely to be motivated*. **Four of the six drift instances the task cites were
already fixed by hand.** The task is still worth doing — but the honest pitch has moved, and
the plan must not be justified on the stale list.

| Cited claim | Verdict today |
|---|---|
| 1. `README.md` roles sentence omits `validate` | **Already fixed** — `README.md:35` names it |
| 2. `docs/harnesses/antigravity.md` lacks `_VALIDATE` | **Already fixed** — documented at `:131`, `:174` |
| 3. 4 call-sites describe a removed mechanism | **Still true**, but misstated: it is the `memory_sessions` marker path, *not* `metadata.tier` |
| 4. "capability floor" describes no mechanism | **Already fixed / misstated** — prose now says "*nothing enforces* a capability floor", which is accurate |
| 5. `--dry-run` "mutates nothing" but fetches | **Still true** — `UPGRADING.md:91`, `commands/sync-system.md:14` vs `sync-system.sh:385-387` |
| 6. "27 test files" | **Still true** (actual 34 `test_*.sh` + 4 `test_*.py`) but lives in `docs/system-overview.md`, which `.gitignore:60` excludes from the published repo. The "release channel backlogged" half is misstated — the doc backlogs the *zip*, correctly. |

**The best live exemplar was on nobody's list:** `MEMORY_SESSIONS_DIR` is documented in
`docs/scripts.md:31,101` (as a table row with default `~/.claude/memory_sessions`) and in
`docs/harnesses/claude.md:25` (as an override "the hook honors"), and appears in **zero** code
files. The code reads `MEMORY_STATE_DIR`, defaulting to `$MEMORY_DIR/.sessions`
(`harnesses/claude/hooks/memory_common.sh:41`). The named consumer, `inject_memory.sh`, does not
contain the string. Both assertion axes catch it.

Ironically, `MEMORY_STATE_DIR` — the var that *replaced* it — is itself undocumented.

**Value is prospective.** That the rot was fixed by someone *remembering* is the argument for
the control, not against it. But this plan claims no retroactive save.

## Control-to-class pairing (measured, not assumed)

Per the repo rule: *state which control catches which bug class, and check that pairing
empirically; a linter, a type checker and a test are not interchangeable.*

| Axis | Catches | TP today | Noise |
|---|---|---|---|
| Forward (table var → exists in code) | the `MEMORY_SESSIONS_DIR` find; claims 3, 4 | 1 | 0 real; 1 shorthand-row parse artifact |
| Forward-strict (var → in the script `Used by` names) | above + wrong-consumer drift | 1 | 5/24 rows hold prose, not a script name |
| Reverse (code var → documented) | claims 1, 2 | ~9 | High — most are deliberately internal |

**Shipping forward + forward-strict. Reverse is rejected** (below).

## Decisions (locked)

- **Anchor on the `docs/scripts.md` env-var table**, not free prose. It is already a structured
  `Var | Default | Used by` single source, yielding two assertion axes from one parser.
- **Clean to floor, then hard-fail** — fix the tree to zero findings, then the gate fails on any
  finding. Mirrors the shellcheck-gate (#52) shape.
- **Fix the data, not the reader.** The shorthand row `AI_MEMORY_EXECUTOR_TASK / _EXPLORE` is
  expanded into two full-name rows rather than handled by a splitter. A parser you don't write
  cannot have a bug.
- **Curated exemptions with reasons** — `.docscheck-exempt` for rows whose `Used by` names no
  script (`MEMORY_DIR` → "All scripts"; the three `NOTION_*` → "NotionProvider"). A prose row
  that is *not* exempted **fails**, so prose cannot silently creep back into the column. This is
  the `.shellcheckrc` + inline-justification pattern.
- **Doc surfaces = published tracked docs only**: `docs/*.md`, `docs/harnesses/*.md`,
  `README.md`, `UPGRADING.md`, `harnesses/*/commands/*.md`, `harnesses/*/CLAUDE.md`.
  Excluded: `CHANGELOG.md` (must name vars from past releases that no longer exist — including it
  makes the check permanently red), and all gitignored per-instance files
  (`docs/system-overview.md`, `identity.md`, `projects/*/memory.md`) so the suite's result does
  not vary per machine. `archive/**` excluded as audit trail.
- **The strict axis follows `source` edges, transitively** (decided 2026-07-10, Phase 1). A var
  satisfies the strict check if it appears in the named script **or in any file that script sources,
  transitively**. "Used by" means *whose behavior the var affects*, not *which file holds the string* —
  the useful reading, and the one the table already uses. Verified: `AI_MEMORY_PROJECTS_ROOT` is read
  at `_lib.sh:255` and `AI_MEMORY_SKILL_CACHE` at `_lib.sh:52`, so both indirected rows validate
  honestly rather than needing an exemption.
  **One hop is NOT enough** — `inject_memory.sh` → `memory_common.sh` → `_lib.sh` (a *conditional*
  source at `memory_common.sh:102`) is a depth-2 chain. The closure needs a visited-set cycle guard.
  The source-line parser must also survive `source "$(dirname "$0")/memory_common.sh"`: a naive
  `\s+(\S+)` regex captures `"$(dirname` because of the space inside `$( )`. Match the trailing
  `/<basename>.sh` instead. *(Both facts cost a wrong assumption to find — the option chosen said
  "one level is enough today.")*
- **The two non-symbol survivors are fixed at source, not tested.** No mechanical control matches
  a semantic prose promise or a hand-written count.
- **`--dry-run` genuinely fetches; Phase 1 corrects the prose, not the code.** Making it truly
  side-effect-free is a behavior change to `sync-system.sh` and belongs to a separate task.

### Rejected alternatives

- **Reverse check (code → docs)** — would catch claims 1-2, but 9+ deliberately-internal vars
  (`AI_MEMORY_ROLE`, `MEMORY_STATE_DIR`, `AI_MEMORY_CWD`, …) need a hand-maintained allowlist: a
  second artifact that rots. Declined.
- **Scanning free prose across all docs** — the `_EXPLORE` shorthand and the
  `AI_MEMORY_EXECUTOR_CMD_<key>` placeholder show prose defeats naive parsing.
- **Mechanically testing the semantic/count claims** — no control matches the class. Asserting
  doc-stated counts was considered and dropped: a count in prose is drift-by-construction, so the
  count is deleted rather than pinned.
- **Including `CHANGELOG.md`** — permanently red, or one suppression per historical line.

## Success criteria

Each is checkable; the Validator verifies these and nothing beyond them.

1. `scripts/check-docs.sh` exists, runs under macOS `bash` 3.2 (no `mapfile`, no associative
   arrays), and needs no runtime dependency beyond coreutils + `grep`/`awk`/`find`.
2. On the **cleaned** tree it exits `0` and reports zero findings.
3. It exits **non-zero** on each of three fixture defects, driven by
   `scripts/tests/test_check_docs.sh`:
   a. a table row naming an env var absent from all code roots;
   b. a table row whose var exists in code but **not** in the script its `Used by` names;
   c. a table row whose `Used by` names no script and is **not** listed in `.docscheck-exempt`.
4. `run-tests.sh` has a `== doc-vs-code ==` stage that **gates the exit code** and prints a
   summary line beside `shellcheck`. Proven by temporarily breaking a row and observing the whole
   suite go red — not by inspection.
5. `scripts/tests/test_check_docs.sh` is reached by the runner's glob and **provably executes**
   (a named-file assertion, not a passing-count assertion — a count would not have caught the
   `taskprovider/tests` gap).
6. `MEMORY_SESSIONS_DIR` no longer appears anywhere outside `archive/`; `MEMORY_STATE_DIR` is
   documented in the table with default `$MEMORY_DIR/.sessions` and consumer `memory_common.sh`.
7. `MEMORY_SESSIONS_DIR` and `memory_sessions` return **zero hits across the declared doc surfaces and
   the code roots** (`docs/**`, `README.md`, `UPGRADING.md`, `harnesses/*/commands/*.md`,
   `harnesses/*/CLAUDE.md`; `scripts/**`, `harnesses/**`, `install.sh`).
   **Not** "zero hits in the tree" — `archive/`, `wikis/`, and this plan and its investigation all
   necessarily name the bug they document. A criterion that forbids naming the defect can never pass.
   *(Corrected 2026-07-10 during Phase 1: the original wording was exactly that unpassable form.)*
8. Neither `UPGRADING.md` nor `harnesses/claude/commands/sync-system.md` claims `--dry-run`
   mutates nothing.
9. `.docscheck-exempt` carries a one-line reason per entry.
10. The full suite is green.

## Phases

### Phase 1 — Clean to floor
Fix every finding so the gate can hard-fail from day one.
- Expand the shorthand table row into `AI_MEMORY_EXECUTOR_TASK` + `AI_MEMORY_EXECUTOR_EXPLORE`.
- Replace the `MEMORY_SESSIONS_DIR` row with `MEMORY_STATE_DIR` (default `$MEMORY_DIR/.sessions`,
  consumer `memory_common.sh`).
- Fix the stale `memory_sessions` call-sites: `docs/harnesses/claude.md:25`, `docs/scripts.md:31`,
  `docs/knowledge-lifecycle.md:48`, `docs/workflows.md:89`, and
  `projects/ai-memory/memory.md:29` (the project memory carries the drift it warns about).
- Correct the `--dry-run` prose: `UPGRADING.md:91`, `harnesses/claude/commands/sync-system.md:14`.
- ~~Drop the counts from `docs/system-overview.md:188-190`~~ — **superseded 2026-07-10: the file was
  removed entirely.** Claim 6 is closed by deletion rather than correction, which is the stronger
  outcome: a hand-written count is drift-by-construction, so the durable fix is for the count to have
  no home. The file was never tracked and has no generator, so no instance ever received it.

### Phase 2 — The checker
- `scripts/check-docs.sh`: parse the table, assert forward + forward-strict, honor
  `.docscheck-exempt`. Deterministic basename resolution across `harnesses/`; `archive/` excluded.
- `.docscheck-exempt` with a reason per row.
- Use `find`/`grep`, never `ls` (see Risks).

### Phase 3 — Prove it fires
- `scripts/tests/test_check_docs.sh` with the three fixture defects from criterion 3.
- Each fixture asserts a **non-zero exit** and the expected message. Red before green.

### Phase 4 — Wire the gate
- `== doc-vs-code ==` stage in `run-tests.sh`, gating the exit code, with a summary line.
- Prove it gates: break a row, observe the suite go red, restore.

### Phase 5 — Docs
- `docs/scripts.md` gate section; `CHANGELOG.md` `### Added`.

## Risks / open questions

- **RESOLVED — indirection.** Settled by the source-following decision above. The `Used by` cells still
  mix script names with *function* names (`resolve_repo_path`), which the parser must not mistake for
  files: match only tokens ending `.sh` / `.py`.
- **RESOLVED — the checker must exclude ITSELF from the code roots** (found in Phase 2 by fixture
  probe, not review). `check-docs.sh` lives in `scripts/`, and its header comments cite
  `MEMORY_SESSIONS_DIR`, `AI_MEMORY_PROJECTS_ROOT` and `AI_MEMORY_EXECUTOR_CMD_<key>` as worked
  examples. Before the fix, `MEMORY_SESSIONS_DIR` **passed the forward axis** — the only file in the
  tree containing it was the checker written to catch it. A deleted var could be re-documented and
  stay green forever. Fixed with `grep --exclude=check-docs.sh`. **This is the fail-open class the
  whole plan targets, reproduced inside the control itself.**
- **RESOLVED — `sed` delimiter collision silently disabled source-following.**
  `s|...(\.|source)...|` ends the pattern at the alternation's `|`; sed dies with "parentheses not
  balanced". A `2>/dev/null` on `sources_of` swallowed the error, so every strict check reported
  "not found in X (nor anything it sources)" — four false positives that *looked* like real drift.
  Delimiter is now `#` and stderr is deliberately unsuppressed. **Swallowing stderr converted a loud
  crash into a plausible wrong answer.**
- **A comment counts as a match, by design.** `AI_MEMORY_EXECUTOR_CMD_<key>` passes the forward axis
  *only* because `executor.sh:19` names the placeholder in a comment — the code builds the real name
  dynamically (`AI_MEMORY_EXECUTOR_CMD_${key//-/_}`). Stripping comments would make that row fail and
  need an exemption. Keeping comments means a var deleted from code but left in a comment would still
  pass. Chosen: **match anywhere**, because the true positive we care about (`MEMORY_SESSIONS_DIR`) had
  **zero** occurrences of any kind. Revisit only if a comment-only ghost actually appears.
- **A doc that documents drift contains the drift's name.** Any "grep finds zero occurrences" criterion
  must be scoped to the doc surfaces and code roots, never the whole tree — otherwise the plan and its
  investigation fail their own check. Cost one wrong success criterion to learn (criterion 7, corrected).
- **A placeholder row passes on a comment.** `AI_MEMORY_EXECUTOR_CMD_<key>` satisfies the forward axis
  only because `executor.sh` names the placeholder in a comment. Confirmed, not theoretical — the
  comment-only caveat below is load-bearing.
- **The table is not the only doc surface.** `AI_MEMORY_SKILL_DATA` is documented in
  `docs/harnesses/claude.md` but absent from the table, so a table-anchored check never sees it.
  Accepted consequence of declining the reverse axis.
- **Semantic prose promises stay structurally untested** (`"mutates nothing"`). Recorded as a
  **non-goal**, not an oversight — this is the control-to-class discipline, not a gap.
- A var appearing only in a **comment** inside the named script passes the strict axis. Low value
  to fix; noted so nobody mistakes the check for a usage analysis.
- **`ls` and `git status` are proxied through `rtk` in this environment and returned empty output
  for a populated directory** during this brainstorm. Anything load-bearing must use `find` /
  `/bin/ls` / porcelain-free git plumbing. A checker built on `ls` would silently pass on an empty
  file list — the exact fail-open class this plan exists to kill.
- ~~Deleting the count from `system-overview.md` fixes an instance in a gitignored file; other
  instances may carry their own stale copy.~~ **Retired 2026-07-10** — the file was removed, was never
  tracked, and has no generator, so it was never distributed. The `.gitignore` entry is kept
  deliberately: it now guards against a recreated personal doc being committed.
