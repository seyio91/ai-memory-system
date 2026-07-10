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
7. `grep -rn "memory_sessions"` returns hits only under `archive/` and
   `projects/ai-memory/wikis/2026-07-09-system-review.md` (a historical record).
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
- Drop the counts from `docs/system-overview.md:188-190` (also stale on which stages
  `run-tests.sh` runs — it now also runs `shellcheck` + `taskprovider`).

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
- Deleting the count from `system-overview.md` fixes an instance in a **gitignored** file; other
  instances may carry their own stale copy. Unavoidable and out of scope.
