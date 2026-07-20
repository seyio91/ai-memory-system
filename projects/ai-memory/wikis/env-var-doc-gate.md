---
doc: env-var-doc-gate
kind: component
status: current — two axes shipped, reverse axis unbuilt
created: 2026-07-20
owner: claude (orchestrator)
---

# The environment-variable doc gate

Documents `scripts/check-docs.sh` and the **Environment overrides** table in `docs/scripts.md`
that it checks — what the control proves, what it structurally cannot see, and the one
unbuilt axis that would close the remaining hole.

## What exists

`docs/scripts.md` carries a table of environment overrides (`Var | Default | Used by`).
`check-docs.sh` parses that table and runs two assertions (`docs/scripts.md:117-121`):

| Axis | Assertion | Catches |
|------|-----------|---------|
| **forward** | every documented var appears somewhere in the code roots | a var renamed or deleted but left documented |
| **strict** | every documented var appears in the script its `Used by` names — **or in any file that script sources, transitively** | a var documented against the wrong consumer |

Source-following is load-bearing, not a nicety: `lint-memory.sh` never names
`AI_MEMORY_PROJECTS_ROOT`, it calls `projects_root()` in `_lib.sh`. "Used by" means *whose
behaviour the var affects*, not *which file holds the string*. One hop is also not enough —
`hooks/inject.sh` → `hooks/lib.sh` → `_lib.sh` is depth 2. The closure carries a visited-set
cycle guard and aborts (`CLOSURE_MAX`, exit 2) rather than returning a verdict from a
traversal that never terminated.

A `Used by` cell naming no script **fails**, unless listed in `.docscheck-exempt` with a
reason (5 entries: `MEMORY_DIR`, `MEMORY_TASK_PROVIDER`, three `NOTION_*`). That stops prose
creeping back into a machine-checked column.

The checker excludes **itself** from the code roots — its own comments cite real var names as
worked examples, and without the exclusion a deleted var could be re-documented and pass
forever on the strength of a comment inside the control written to catch it.

## The structural hole: both axes start from the table

Forward and strict both iterate **table rows**. A var that was never added to the table is
invisible to the gate — it cannot fail a check that never enumerates it. So the control
proves the docs aren't *stale about what they already mention*, and nothing more.

The missing third assertion is the **reverse axis** — *code → docs*: every user-facing var in
the code has a row.

## Why the reverse axis was never built — and why that reason is wrong

The backlog recorded the blocker as *"needs a hand-maintained allowlist of internal vars,
which rots."* A rotting allowlist fails **open**, which is the right thing to fear. But the
premise is false: **the public/internal split is derivable from write sites.**

- Production code **exports** it → internal IPC between our own components. A user setting it
  is meaningless. No row.
- Production code only **reads** it with a default (`${VAR:-fallback}`), never writes it →
  user-facing knob. Must have a row.

Computable from a grep. Nothing to hand-maintain, nothing to rot. *(This reasoning was
written up only in PR #83 and survives nowhere else — hence this page.)*

## Applying the rule: the count was 3, the real number is 10

Working memory recorded three undocumented vars (`AI_MEMORY_CWD`, `AI_MEMORY_HARNESSES_DIR`,
`AI_MEMORY_PROJECT`). Re-derived 2026-07-20 — all `AI_MEMORY_*`/`MEMORY_*` symbols in
`scripts/`, `harnesses/`, `install.sh`, excluding `*/tests/*`, minus table rows — it is **ten**.

**Internal IPC — correctly absent, no decision needed (7):**

| Var | Written at |
|---|---|
| `AI_MEMORY_CWD` | `hooks/inject.sh:40`, `hooks/session_start_memory.sh:36`, `agy.sh:28` |
| `AI_MEMORY_PROJECT` | `agy.sh:27` (`detect_active_project`) |
| `AI_MEMORY_CHUNK_INDEX` / `AI_MEMORY_CHUNK_TOTAL` | `hooks/lib.sh:173` |
| `AI_MEMORY_HOOK_CHUNK` / `AI_MEMORY_HOOK_EVENT` / `AI_MEMORY_HOOK_FORMAT` | generated into hook registrations by `drivers/hook.sh:303,351,364` |

**Read-only with a default — genuinely user-facing, and undocumented (3):**

- **`AI_MEMORY_SKIP_INJECT`** (`hooks/inject.sh:12`, `hooks/session_start_memory.sh:26`) — a
  kill switch for *all* memory injection, base and breadcrumb. An undiscoverable escape
  hatch; the highest-value gap of the three.
- **`AI_MEMORY_HARNESSES_DIR`** (`executor.sh:38`) — read-only in production, written only by
  tests. Fits the existing *"Test seam, not for production use"* row pattern
  (`AI_MEMORY_TEST_NO_SORT_V`, `AI_MEMORY_UPGRADING_DOC`).
- **`AI_MEMORY_ROLE`** — exported by `executor.sh:223`, read by `release.sh:33` as a guard: a
  release cut **refuses** when it is set. A safety control with no checked row.

`MEMORY_SESSIONS_DIR` appears only inside `check-docs.sh` comments as a historical example,
and the checker excludes itself — so it is not in the code for gate purposes.

### Documented ≠ checked

`AI_MEMORY_ROLE` *is* mentioned at `docs/scripts.md:21` — in prose. The parser reads table
rows only. Working memory counted it as "now present", which conflates the two. Any future
tally must count **rows**, not occurrences of the string in the file.

## Doc rot inside the doc-rot control

`docs/scripts.md:145-146`, in the *"What it does not catch"* list, still reads:

> `AI_MEMORY_SKILL_DATA` is documented in Claude harness but has no row here, so it is unchecked.

It has had a row since #83 (`docs/scripts.md:189`). The control's own worked example is stale
— precisely the defect class it exists to catch, sitting in the one section no axis reads.
A control that documents its own limits in prose grows a blind spot exactly where it explains
itself.

## Outstanding

1. Add the three user-facing rows (`AI_MEMORY_SKIP_INJECT`, `AI_MEMORY_HARNESSES_DIR`,
   `AI_MEMORY_ROLE`).
2. Fix the stale `AI_MEMORY_SKILL_DATA` bullet at `docs/scripts.md:145`.
3. Implement the reverse axis with the write-site rule as its classifier — at which point the
   3-vs-10 drift becomes structurally impossible instead of something re-derived by hand each
   session. **Deferred 2026-07-20; needs a design pass before `/new-plan`** — see below.

### Reverse axis — prototype result, and why it is not ready

The naive classifier (a var is internal if `VAR=` appears anywhere in production code) was
prototyped against all ten vars on 2026-07-20. It misclassifies two, in both directions:

- **`AI_MEMORY_SKIP_INJECT` → wrongly INTERNAL. Fail-open.** Its only assignment-shaped hits
  are the *comments* documenting it for humans (`hooks/inject.sh:10`,
  `hooks/session_start_memory.sh:26`). The axis would wave through the single highest-value
  gap it exists to catch. Note the inversion: the forward axis deliberately *counts* comments
  (`AI_MEMORY_EXECUTOR_CMD_<key>` passes only because of one); the reverse axis must not.
  Comment-stripping before assignment-matching is therefore a hard requirement, not a polish
  item.
- **`AI_MEMORY_ROLE` → correctly INTERNAL,** which contradicts the "user-facing" framing used
  when this page was first written. `executor.sh:223` genuinely exports it and no user sets
  it. Its table row is a **courtesy** — so someone hitting "release refused" can find the
  cause — not something the axis would enforce.

Consequence: of the three rows added in the first pass, only `AI_MEMORY_SKIP_INJECT` is
motivated by the axis at all, and it is the one the naive classifier misses.

Open design questions before a plan: comment stripping; whether `tests/` and
`tests/fixtures/` are in classification scope (they are already in the forward axis's code
roots, which is a separate decision); dynamically-built names like
`AI_MEMORY_EXECUTOR_CMD_<key>`; and an exemption channel that does not simply recreate the
rotting allowlist the write-site rule was chosen to avoid.

System change (`scripts/` + `docs/`) → branch + PR, per the commit-route rule.

## What the gate still will not catch (by design)

- **Semantic prose promises.** `/sync-system --dry-run` documented "mutates nothing" while
  running `git fetch --tags`. The flag exists, so no symbol check can see it. (Still true:
  `sync-system.sh:387`, re-verified 2026-07-20.)
- **Counts.** A hand-written "27 test files" is drift by construction — delete the count.
- **Cross-repo contradictions.** A remote skill in `.skill-cache/` is referenced, not forked.
- **Comments count as matches.** `AI_MEMORY_EXECUTOR_CMD_<key>` passes the forward axis only
  because `executor.sh` names the placeholder in a comment; the code builds it dynamically.
