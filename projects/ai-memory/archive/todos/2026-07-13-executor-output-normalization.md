# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

## Active

### Executor output normalization — uniform final-message output from cli: executors → [plan](plans/executor-output-normalization.md)
- [x] P1 — mechanism: `exec_last_message` manifest key + `executor.sh --run --clean` branch (codex tmpfile+cat+trap, agy pass-through, exit propagation)
- [x] P2 — tests: `test_executor.sh` assertions (stubbed cli), each mutation-verified
- [x] P3 — docs (`docs/scripts.md`) + doc-vs-code + full suite + validator pass

## Done
_(checked items stay above until the file is rolled)_
