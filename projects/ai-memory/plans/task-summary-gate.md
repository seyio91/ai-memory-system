---
plan: task-summary-gate
status: active
created: 2026-07-09
owner: claude (orchestrator)
task_provider: notion
task_ref: 397f6850-c619-812b-a4a1-e996df808fbf
---

# Task summary: a hard gate, with long-form by pointer

## Goal

Make `summary` a structurally-enforced thin record. Cap it at 500 characters at the
contract boundary, so a design cannot be crammed into it; long-form content lives in the
memory tree as a brainstorm and is referenced by pointer. Document the rule where a user
will actually meet it — the error message first, then `docs/task-provider.md` and the
`/task` + `/start` command docs.

## Success criteria

- [x] `capture()` and `update()` reject a `summary` over 500 chars with a `ValueError`
      **at the contract boundary** — before any provider dispatch, for *every* provider
      including `local`. Verified by a test that never touches the network.
- [x] The rejection message names the actual length, the cap, and the remedy (write
      `projects/<project>/brainstorms/<slug>.md`, reference it from the summary).
- [x] `update(ref, title=...)` with no `summary` does **not** trigger the gate; `summary=None`
      is untouched, not treated as empty.
- [x] Reads are ungated: `get()` / `list()` still return the 9 existing tasks whose summaries
      exceed 500 chars. No migration, no rewrite.
- [x] `taskctl capture` / `taskctl update` surface the failure as a non-zero exit **and** a
      JSON `{"error": ...}` object carrying the message (the CLI contract).
- [x] `docs/task-provider.md` gains a "Summary is a gate" section; the contract table rows for
      `capture`/`update` state the cap; the `## The model` invariant is narrowed (below).
- [x] `/task` and `/start` command docs state the cap and the pointer convention. `/start`'s
      pushed-back Goal is explicitly required to fit.
- [x] `scripts/run-tests.sh` passes, with new cases in the taskprovider unittest suite and
      `scripts/tests/test_taskprovider_cli.sh`.
- [x] `scripts/run-tests.sh` **runs** the `scripts/taskprovider/tests/` Python suite (it did not
      before — the suite was outside the gate entirely) and gates the overall exit on it.
- [x] Every `providers/<name>.py` has a matching `tests/test_<name>.py`; a provider without one
      **fails** the suite. Verified by pointing the check at a fixture provider with no test.

## Design

**Chosen: a backend-neutral cap enforced at the ABC boundary, long-form by pointer.**

The gate is `validate_summary()` in `contract.py`, mirroring the existing
`validate_status()`. It is applied through `__init_subclass__`, wrapping `capture` and
`update` exactly as `set_status` is wrapped today (`contract.py:26-36`) — so a provider
author cannot forget it, and it fires before any HTTP request.

It lives in the contract, not in `notion.py`, because **the rule is architectural, not a
backend limit.** It derives from the projection model (`docs/task-provider.md:5-9`: the
backend owns intent + coarse status; the memory tree owns all detail). A `local`-only task
must obey it too — inheriting a constraint from a backend it never uses would be incoherent,
but inheriting one from the system's own model is the point.

**Cap = 500.** `/start` specifies a Goal of "one or two sentences" (~300 chars), plus a
pointer line (~80). Calibration: the pointer-style summary written for the system-review
task on 2026-07-09 came out at 409 chars. Of the 12 live tasks, 9 exceed 500 — that is the
forcing function, not a problem: the gate fires on **write only**, so legacy tasks stay
readable and are brought into compliance the next time anyone updates them.

**The error message is the primary documentation surface** — more people hit it than read
`docs/`. It must name the length, the cap, and the remedy.

**Narrowing the invariant.** `docs/task-provider.md:9` currently reads "Nothing is
materialized in the memory tree until `start`." Pointing a captured task at a brainstorm
contradicts it. The invariant is stated too broadly: what must not exist before `/start` is
a **plan file, a `todo.md` row, or an index entry** — the artifacts that make work *live*.
A brainstorm is a design input, not live work. This legalizes the precedent already set by
`brainstorms/release-automation.md`, which was written at capture time and pointed at.

### Alternatives rejected

- **Chunk `_text_value` into ≤2000-char elements** (Notion allows 100 per array;
  `_plain_text` already joins on read). Would have fixed the original 4824-char failure with
  ~5 lines. Rejected as the *primary* fix: it removes the symptom and preserves the disease —
  designs crammed into a property. Made **moot** by the cap: a ≤500-char summary always fits
  one element, so this work disappears entirely rather than being deferred.
- **Add a real `body` field, both directions** (the captured task's own proposal; notion →
  page children blocks, local → markdown after frontmatter, jira → `description`). Rejected:
  it builds a push path for long-form content into a store the architecture defines as a
  projection. Also drags in a lossy Notion block→markdown reader.
- **`body` read-only, populated on `get`** (my initial recommendation). Rejected with the
  above: it closes a real intake gap (a hand-written Notion page body is invisible to `get`),
  but that gap is not what this task is about, and a contract that reads a field it cannot
  write is a wart. Re-file separately if hand-intake bodies ever matter.
- **Keep the invariant, forbid pointers.** Purest reading — if a task needs a long design it
  isn't ready to capture. Rejected: the 4824-char design *already existed* at capture time;
  it has to live somewhere.

## Decisions (locked)

- Cap is **500 characters**, enforced on write, never on read. No migration of the 9 legacy
  over-cap tasks; they are corrected on next write.
- Enforcement is **backend-neutral**, at the `TaskProvider` ABC boundary, via the same
  `__init_subclass__` mechanism that already guards `set_status`.
- Long-form lives at `projects/<project>/brainstorms/<slug>.md` and is referenced from the
  summary by path.
- The `## The model` invariant is narrowed to "no plan, no `todo.md` row, no index entry",
  explicitly permitting a pre-`/start` brainstorm.
- **`add_progress` is not dead and is not touched.** `docs/task-provider.md:30` documents it
  as "Designed, not wired" — a deliberate non-abstract no-op reserved for `/checkpoint`
  wiring. It stays a no-op. Consequence: no Notion block writer is built by this plan.
- The captured task's title ("add a long-form `body` field distinct from `summary`") no longer
  describes the work. Retitle it at link time.

## Phases

- **Phase 1 — the gate.** `contract.py`: `SUMMARY_MAX_CHARS = 500`, `validate_summary()`,
  and `__init_subclass__` wrapping of `capture` + `update` (skip when `summary is None`).
  Actionable error text.
- **Phase 2 — CLI surface.** Confirm `__main__.py` maps the `ValueError` to a non-zero exit
  plus `{"error": ...}` (it already funnels exceptions; verify, don't assume). No `taskctl`
  change expected.
- **Phase 3 — tests.** Unittest: over-cap `capture` rejected offline for `local` *and*
  `notion` (monkeypatched HTTP, asserting no request was issued); `update(title=...)` alone
  passes; boundary at exactly 500 and 501; reads of a >500 legacy fixture still work.
  Bash: `test_taskprovider_cli.sh` asserts exit code + JSON `error`.
- **Phase 3b — wire the Python suite into the gate.** Discovered while executing Phase 3:
  `run-tests.sh:52` globs only `scripts/tests/test_*.sh`, so `scripts/taskprovider/tests/`
  has **never** run. The suite reported `32 passed` before and after a whole new test file was
  added. Add a `== taskprovider (python) ==` stage running `unittest discover` under the same
  `hermetic` env scrub, gate the overall exit on it, and enforce the provider↔test pairing:
  each `providers/<name>.py` must have `tests/test_<name>.py` or the suite fails. This is the
  same class of defect as the backlogged shellcheck and doc-vs-code tasks — a control everyone
  believes is enforced, silently isn't.
- **Phase 4 — docs.** `docs/task-provider.md`: new "Summary is a gate" section, contract-table
  rows for `capture`/`update`, narrowed `## The model` invariant. `harnesses/claude/commands/task.md`
  and `start.md`: the cap and the pointer convention. Add a `## [Unreleased]` CHANGELOG entry.

## Risks / open questions

- **`/start` pushes the brainstorm's clarified Goal back via `update`.** A verbose Goal now
  hard-fails the flip to `started`. The brainstorming skill already specifies "one or two
  sentences", so this should hold — but Phase 3 must cover it, and this plan's own push-back
  is the first live test.
- **9 of 12 live tasks are over cap.** Any future `update` on them fails until shortened.
  Intended, but it will surprise whoever hits it first; the error message carries the fix.
- **The intake gap stays open.** A task hand-written in Notion with a page body: `get()` still
  cannot see the body. Deliberately out of scope. File separately if it bites.
- **Enforcing the pointer's existence is not attempted.** Nothing checks that a referenced
  brainstorm path resolves. `lint-memory.sh` is the natural home if it ever matters; a dangling
  pointer is currently a silent lie.
