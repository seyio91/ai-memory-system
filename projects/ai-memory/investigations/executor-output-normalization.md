---
kind: investigation
status: open (design input)
created: 2026-07-13
---

# Executor output normalization

## Problem
When the orchestrator dispatches a `cli:` executor via `executor.sh --run` as a background
task, the `.output` file it reads back is **not uniform across harnesses**:
- `codex exec` streams a verbose transcript to stdout — header block (`workdir`, `model`,
  `sandbox`, reasoning effort), the reasoning, a `tokens used` line, and the final message
  **printed twice** (once in-transcript, once as the tail). To get the answer the caller must
  parse the tail.
- `agy -p` prints **only** the final response — already clean.

So consuming a background executor result requires per-harness knowledge. Goal: make the output
uniform (ideally: only the final agent message) regardless of which CLI ran.

## Confirmed mechanism (2026-07-13, probed live)
- `codex exec -o/--output-last-message <FILE>` writes **only** the final agent message to `<FILE>`
  — robust, no fragile text-parsing (respects the "never parse a verbose stream loosely" rule,
  [[domain:shell]] / [[domain:agent-tooling]]).
- `codex exec --json` emits JSONL events as an alternative structured channel.
- `agy -p` is already the final message on stdout — needs no flag.

## Sketch (pre-brainstorm)
- Optional manifest key, e.g. `exec_last_message = -o {file}` (codex declares it; agy omits it).
- A clean mode on `executor.sh`, e.g. `--run --clean`: if the resolved harness declares
  `exec_last_message`, allocate a temp file, thread the filled flag, run the CLI, then emit the
  temp file's contents to stdout and clean up; harnesses **without** the key pass their stdout
  through unchanged (agy already clean).
- `test_executor.sh` assertion + a `docs/scripts.md` note.

## Open forks (for the design gate)
1. **Opt-in vs default.** Is `--clean` an opt-in flag, or does `--run` emit clean output by
   default (verbose behind a `--raw`)? Default-clean is friendlier but changes existing behavior.
2. **Temp-file lifecycle.** Where does the last-message file live (scratch dir? `mktemp`?), and
   how is it cleaned up on success AND on failure/interrupt?
3. **Non-zero exit.** If the CLI exits non-zero, the last-message file may be empty/partial —
   do we surface stderr/transcript then, or emit whatever's in the file?
4. **Role scope.** Applies to `task`/`explore`/`validate` cli runs equally? (validate consumes
   output too.) Subagent plane has no `--run`, so it's out of scope.
5. **Also expose `--json`?** A structured channel (`--run --json`) may be worth it for callers
   that want events, or YAGNI for now.

## Provenance
Follow-up to the 2026-07-13 background-dispatch convention (the "Option A" the user deferred when
shipping Option B). Convention already documented in `CLAUDE.md`, `identity.md`, `docs/workflow.md`,
`executor.sh`; durable finding in `domain/agent-tooling.md`.
