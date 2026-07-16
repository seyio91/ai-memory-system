Run the memory system's end-to-end test suite and report the result.

This runs every `scripts/tests/test_*.sh` plus the `lint-memory.sh` content check in a **hermetic** environment — `scripts/run-tests.sh` scrubs the developer-shell variables that would otherwise steer a test into a live backend or the real tree (`MEMORY_TASK_PROVIDER`, `NOTION_*`, `MEMORY_DIR`, `AI_MEMORY_PROJECTS_ROOT`, `AI_MEMORY_EXECUTOR*`). Each test owns its own sandbox and cleans up after itself; the runner just guarantees a clean baseline, so this never touches Notion or the live memory tree.

Argument: `$ARGUMENTS` — optional flags forwarded to the runner:
- `--no-lint` — run the tests only, skip the lint pass.
- `-v` — stream each test's full output (default: only failures are shown).

Step 1 — run:
```
bash ~/.claude-memory/scripts/run-tests.sh $ARGUMENTS
```
Capture stdout and the exit code. The runner exits `0` only when every test passes and lint has no `ERROR:` lines; lint `WARN:` lines (e.g. stale `working.md`) are advisory and do NOT fail the run.

Step 2 — report concisely:
- Lead with the verdict: `N passed, M failed` and the lint line (`clean (K warning(s))` or `K error(s)`).
- If anything failed: show the failing test name(s) and the relevant assertion lines from the runner output. Do not re-run individual tests unless diagnosing.
- If green: state it plainly (e.g. "13/13 green, lint clean") and stop. Surface any lint warnings as a one-line nudge (`/promote-memory` or `/checkpoint`), not as a failure.

Do not modify code or tests from this command — it is read/verify only. If a failure looks like a test-hermeticity issue (a test leaking host state) rather than a product bug, say so and suggest fixing the test, but make no edits here.
