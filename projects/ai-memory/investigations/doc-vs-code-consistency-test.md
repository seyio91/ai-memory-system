---
doc: doc-vs-code-consistency-test
kind: investigation
status: consumed — seeded the doc-vs-code-consistency-test plan
created: 2026-07-10
owner: claude (orchestrator)
task_ref: 397f6850-c619-818c-a0ee-e17736b1bfe6
---

# Investigation — doc-vs-code consistency test

Findings from re-measuring the captured task's rationale on 2026-07-10, before its plan hardened.

**Scope note.** This file holds *evidence*: what was measured, and what each proposed control actually
catches. The **decisions** those findings led to — chosen approach, rejected alternatives, success
criteria — live in the `doc-vs-code-consistency-test` plan, and are deliberately not repeated here.
One fact, one home.

---

## 1. The captured rationale was 4/6 stale

The task was filed 2026-07-08 citing six drift instances from the 2026-07-09 four-agent system review.
Re-measured before planning, per the repo's own rule: *a measurement taken to justify a task is the one
most likely to be motivated — re-derive it before the plan hardens around it.* The same discipline that
collapsed the `shellcheck-gate` premise.

### Claim 1 — README omits the `validate` role → **ALREADY FIXED**
`README.md:35` names all three roles and the cross-model default.

### Claim 2 — `docs/harnesses/antigravity.md` lacks `_VALIDATE` → **ALREADY FIXED**
`:131` "Read-only (explore/validate roles)."; `:174` names `AI_MEMORY_EXECUTOR_TASK` / `_EXPLORE` / `_VALIDATE`.

### Claim 3 — four call-sites describe a removed mechanism → **STILL TRUE, MISSTATED**
The task guessed `metadata.tier` / the skill write-boundary. Wrong. The only live mention of
`metadata.tier` is `projects/ai-memory/memory.md:42`, which correctly narrates its **removal** in past
tense — a legitimate historical reference, and a false positive any naive checker must not flag.

The actually-stale mechanism is the **`~/.claude/memory_sessions` marker path**:

| File | Text |
|---|---|
| `docs/harnesses/claude.md:25` | "per-session marker file at `~/.claude/memory_sessions/<session_id>`" |
| `docs/scripts.md:31` | "(and, for the hook, `MEMORY_SESSIONS_DIR`)" |
| `docs/scripts.md:101` | table row: `MEMORY_SESSIONS_DIR` \| `~/.claude/memory_sessions` \| `inject_memory.sh` |
| `docs/knowledge-lifecycle.md:48` | "Per-session injection markers… under `memory_sessions/`" |
| `docs/workflows.md:89` | "Confirm `~/.claude/memory_sessions/` is writable" |

Code instead: `harnesses/claude/hooks/memory_common.sh:41` →
`STATE_DIR="${MEMORY_STATE_DIR:-$MEMORY_DIR/.sessions}"`

`projects/ai-memory/memory.md:29` carries the same stale path — **the project memory contains the drift
it warns about.**

### Claim 4 — "capability floor" describes no mechanism → **ALREADY FIXED / MISSTATED**
`docs/workflow.md:27` says "*nothing enforces* a capability floor" — an accurate disclaimer of a
deliberately-absent mechanism, not a description of a phantom one. Same at `harnesses/claude/CLAUDE.md:75`
and `memory.md:34`. `config.local.sh.example` no longer mentions it at all.

### Claim 5 — `--dry-run` "mutates nothing" but fetches → **STILL TRUE**
- `UPGRADING.md:91` — "`sync-system.sh --dry-run` # reports channel + target tag, mutates nothing"
- `harnesses/claude/commands/sync-system.md:14` — "`--dry-run` — report … ; mutate nothing."
- `scripts/sync-system.sh:385-387` — under `DRY_RUN=1`, runs `git fetch --quiet --tags origin`.

`git fetch --tags` **is** a mutation of local git state. Two doc surfaces, one code truth. Exactly what
`memory.md` warned: *"nothing tests a command doc against the script it invokes."*

### Claim 6 — "27 test files" → **PARTLY TRUE, PARTLY MISSTATED**
`docs/system-overview.md:188-190` says "27 hermetic bash test files … Currently **27/27 green**", and that
`run-tests.sh` "also runs `lint-memory` + `validate-skills`". Actual: **34** `test_*.sh` + **4**
`test_*.py`, and the runner also runs `shellcheck` + `taskprovider`. Stale three ways.

**But** `.gitignore:60` excludes `/docs/system-overview.md` — a per-instance, unpublished doc. And the
"calls the shipped release channel backlogged" half is **misstated**: `:184` backlogs the *zip packaging*,
which remains accurate.

### The best exemplar was on nobody's list

`MEMORY_SESSIONS_DIR` is documented in two files as an env override "the hook honors", and appears in
**zero** code files under `scripts/`, `harnesses/`, `install.sh`. Its named consumer, `inject_memory.sh`,
does not contain the string at all.

Ironically, `MEMORY_STATE_DIR` — the var that **replaced** it — is itself undocumented.

**Consequence for the pitch.** The rot was caught by someone *remembering*, which is precisely the
reliance the control removes — so the task survives. But its value is **prospective**. It must not be sold
on a retroactive save. Same correction the `shellcheck-gate` plan had to make.

---

## 2. Control-to-class pairing, measured

The rule: *state which control catches which bug class, and check that pairing empirically; a linter, a
type checker and a test are not interchangeable, and picking the wrong one ships a gate that proves nothing.*

Each axis was prototyped against the real 24-row env-var table in `docs/scripts.md` before any choice was made.

| Axis | Catches | True positives | Noise measured |
|---|---|---|---|
| **Forward** — table var exists in code | `MEMORY_SESSIONS_DIR`; claims 3, 4 | 1 | 0 semantic FPs; 1 parse artifact |
| **Forward-strict** — var appears in the script `Used by` names | above + wrong-consumer drift | 1 | 5/24 rows hold prose, not a script name |
| **Reverse** — code var is documented | claims 1, 2 | ~9 | High: most are deliberately internal |

The parse artifact: the shorthand row `AI_MEMORY_EXECUTOR_TASK / _EXPLORE`, plus the placeholder
`AI_MEMORY_EXECUTOR_CMD_<key>`.

The 5 prose rows: `MEMORY_DIR` → "All scripts"; `MEMORY_TASK_PROVIDER` → "task-provider factory";
`NOTION_TOKEN` / `NOTION_DATA_SOURCE_ID` / `NOTION_STATUS_KIND` → "NotionProvider" (a class, not a file).

The ~9 undocumented-in-table code vars: `AI_MEMORY_CWD`, `AI_MEMORY_HARNESSES_DIR`, `AI_MEMORY_PROJECT`,
`AI_MEMORY_ROLE`, `AI_MEMORY_SKILL_DATA`, `MEMORY_STATE_DIR`, `MEMORY_RELOAD_TRIGGER`, `MEMORY_ROOT`,
`NOTION_TEST_DATA_SOURCE_ID`.

**The finding that killed the reverse axis:** `AI_MEMORY_SKILL_DATA` *is* documented — in
`docs/harnesses/claude.md`, not the table. So the table is **not** a complete single source, and a reverse
check anchored on it false-positives on a correctly-documented var.

**Neither live survivor is a symbol.** Claim 5 names a flag that genuinely *exists* — the rot is in the
prose's semantic promise. Claim 6 is a hand-written count. A symbol-existence check is structurally blind
to both. This is why the plan records them as a **non-goal** and fixes them at source instead.

---

## 3. Traps this investigation surfaced

- **A gate nobody proved fires.** From `memory.md`: *"a test file the runner's glob doesn't reach is
  silently ungated — the suite reports green and proves nothing."* Any gate shipped here must prove **red
  before green**. A passing-*count* assertion would not have caught the `taskprovider/tests` gap; only
  asserting that a **named file ran** would.

- **`ls` lies in this environment.** `ls` and `git status` are proxied through `rtk`. During this
  investigation `ls docs/` returned **empty output for a populated directory**, nearly producing the
  conclusion that `docs/` did not exist; `grep -c` and `git status --porcelain` were likewise reformatted,
  and a `grep -oE` fell over inside rtk's `ugrep` shim. `find`, `/bin/ls`, and `git ls-files` were correct.
  **A checker built on `ls` would silently pass on an empty file list** — the exact fail-open class this
  work exists to kill. Use `find`/`grep`, never `ls`.

- **A narrowing fix creates the opposite defect.** From the deny-list rounds: *a fix that narrows a matcher
  to kill a false positive is the likeliest place to create a false negative.* Every future exemption must
  be paired with "what does this now fail to catch?"

- **Verify by probing, not reasoning.** Every claim in §1 was checked by running the grep, not by reading
  the review. Four of six did not survive contact. The delegated `explore` executor (codex) corrected the
  orchestrator's own guess on Claim 3 — cross-checking beat a single reading.

---

## 4. Deferred / follow-on threads

- **Make `--dry-run` genuinely side-effect-free** in `sync-system.sh` (drop or gate the `git fetch --tags`).
  A behavior change, not a doc fix. Own task.
- **Decide which env vars are public API vs internal.** `AI_MEMORY_CWD`, `AI_MEMORY_HARNESSES_DIR`,
  `AI_MEMORY_PROJECT`, `AI_MEMORY_ROLE`, `MEMORY_RELOAD_TRIGGER`, `MEMORY_ROOT`, `MEMORY_STATE_DIR` are read
  by code and absent from the table. This decision is the precondition for ever enabling the reverse axis.
- **Single-source the env-var table.** `AI_MEMORY_SKILL_DATA` living only in `docs/harnesses/claude.md` is
  the drift-by-copies problem from `domain/preventing-drift.md`. Fewer copies ⇒ fewer targets for this test.
- **The doc-vs-code gate cannot see across a repo boundary.** The `brainstorming` skill is remote-referenced
  from `agent-skills`; its `SKILL.md` contradicted this tree's `memory.md` for weeks and no in-tree check
  could ever have caught it. See the `agent-skills` row in `## Related Projects`.
