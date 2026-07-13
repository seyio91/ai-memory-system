---
plan: executor-output-normalization
status: active
created: 2026-07-13
owner: claude (orchestrator)
task_provider: notion
task_ref: 39cf6850-c619-819b-88b0-d590bf5931cc
---

# Executor output normalization

## Goal
Give `executor.sh --run` an opt-in `--clean` mode that emits ONLY the final agent message,
uniform across `cli:` harnesses, so a backgrounded `.output` file is directly consumable no matter
which CLI ran. Follow-up (Option A) to the 2026-07-13 background-dispatch convention.

## Success criteria
1. `executor.sh --role <r> --run --clean "<prompt>"` for a **codex** cli executor emits only the
   final agent message to stdout — no header/reasoning/`tokens used`/duplicated tail — via
   `codex exec … -o <tmpfile>` then `cat <tmpfile>`.
2. `--run --clean` for an **agy** cli executor emits the final response unchanged (agy `-p` is
   already bare → pass-through; the harness declares no `exec_last_message`).
3. `--run` **without** `--clean` is byte-for-byte unchanged (verbose transcript; still `exec`s the CLI).
4. Clean mode **propagates the CLI's exit code**; on a non-zero exit it still cats whatever the
   last-message file holds (never swallows a failure).
5. The temp file is **always** removed — success, non-zero exit, and interrupt (`trap … EXIT`).
6. Clean mode applies to **all cli roles** (`task`/`explore`/`validate`). The subagent plane still
   prints `EXECUTOR_USE_SUBAGENT` (exit 3); `--clean` is a no-op there.
7. A harness declaring no `exec_last_message` falls back to **raw stdout pass-through** under
   `--clean` (documented: `--clean` guarantees clean only for harnesses that declare the key).
8. `test_executor.sh` covers, each mutation-verified: codex clean path (stubbed CLI), pass-through
   path, `--run`-unchanged, exit-code propagation, temp-file cleanup.
9. `docs/scripts.md` documents `--run --clean` + the `exec_last_message` manifest key; `doc-vs-code`
   gate green; full suite green (bash + python + shellcheck + doc-vs-code + lint).

## Design
- **Manifest key `exec_last_message`** (optional; `{file}` placeholder, threaded exactly like
  `exec_model_flag`). `harnesses/codex/manifest`: `exec_last_message = -o {file}`. `antigravity`:
  absent. `resolve_value` reads it into a new `R_LASTMSG` (or appends when in clean mode).
- **`--clean` flag** parsed in the `--run` handler. Behavior:
  - subagent plane → unchanged (`EXECUTOR_USE_SUBAGENT`, exit 3); `--clean` ignored.
  - cli plane **with** `exec_last_message`: `tmp="$(mktemp)"`; `trap 'rm -f "$tmp"' EXIT`;
    substitute `{file}`→`$tmp` into the flag and append to the command; **run (not `exec`)**
    `eval "${cmd} </dev/null"`; `rc=$?`; `cat "$tmp"`; `exit "$rc"`.
  - cli plane **without** `exec_last_message`: pass-through — the existing `exec` path (its stdout is
    already the final message; agy).
  - Without `--clean`: the current `eval "exec ${cmd} </dev/null"` path, untouched.
- **Crux:** the clean branch must drop `exec` (process replacement leaves no room to post-process);
  isolated to that branch so the default path keeps zero-overhead `exec`.

Alternatives considered:
- **Default-clean + `--raw` opt-out** — rejected: changes behavior for every existing `--run` caller
  (incl. the just-shipped background-dispatch convention) and hides the debugging transcript.
- **Parse codex's verbose stdout** to extract the final message — rejected: fragile; `-o` is the
  robust structured channel (respects the never-parse-a-verbose-stream-loosely rule,
  `domain/shell.md` / `domain/agent-tooling.md`).
- **Expose `--json` now** — rejected for now: no consumer (YAGNI); see Risks.

## Decisions (locked)
- Opt-in `--run --clean`; `--run` alone unchanged.
- On non-zero CLI exit: cat the last-message file (whatever it holds) + propagate the exit code.
- `--json` deferred (last-message only this round).
- Temp file via `mktemp` + `trap … EXIT` cleanup.
- Applies to all cli roles; subagent plane exempt (no `--run` process).

## Phases
- **P1 — mechanism:** add `exec_last_message` to the manifest schema resolution + the codex manifest;
  implement the `--clean` branch in `executor.sh` (codex tmpfile+cat+trap, agy pass-through, exit
  propagation). Verify `codex exec` accepts `-o <file>` appended after the positional prompt.
- **P2 — tests:** `test_executor.sh` assertions (stubbed cli) for all of criteria 1-7; mutation-verify
  each load-bearing assertion.
- **P3 — docs + gate:** `docs/scripts.md` (`--run --clean` + `exec_last_message`); re-run doc-vs-code +
  full suite; validator pass against these success criteria.

## Risks / open questions
- **`--json` extension point deferred** — later add an `exec_json` key + `--run --json` if a consumer
  appears. Cheap to graft onto the same clean-branch machinery.
- **Flag ordering** — `-o <tmp>` lands after `{prompt}` in codex's command; codex `exec` (clap) should
  accept interspersed options, but validate empirically in P1 (put it before the prompt if not).
- **Pass-through safety** — a no-`exec_last_message` harness emits raw stdout under `--clean`; only safe
  because agy is already clean. Document the guarantee boundary.
- **Testing without real codex** — stub the cli in `test_executor.sh` (confirm the suite's existing
  executor-stub pattern) so the clean path is exercised hermetically.
