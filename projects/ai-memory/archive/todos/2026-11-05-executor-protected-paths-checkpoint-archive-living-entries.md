# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Executor-protected paths: guard config and plans → [plan](archive/plans/executor-protected-paths.md)
- [x] P1 — path-match.sh: protected set, Claude file tools, Bash obvious writes
- [x] P2 — Codex apply_patch extraction (needs: P1)
- [x] P3 — Wiring, doctrine, docs (needs: P1, P2)
- [x] P4 — Post-merge live probe (needs: P3, merge)

### checkpoint-archive should roll only closed and superseded checkpoints → [plan](archive/plans/checkpoint-archive-selective-roll.md)
- [x] P1 — script: --list, --keep, fence parity
- [x] P2 — command text, docs, changelog (needs: P1)
- [x] P3 — validate and ship (needs: P1, P2) — merged as #147 (`08226e0`)

### Checkpoints record changes and carry open items forward → [plan](archive/plans/checkpoints-record-changes-and-carry-open-items-forward.md)
- [x] P1 — window default 5 and warning threshold
- [x] P2 — /checkpoint living entries (needs: P1)
- [x] P3 — archive check, docs, /threads, changelog (needs: P2)
- [x] P4 — validate and ship (needs: P1, P2, P3) — PR #148 open, awaiting merge

## Done
_(checked items stay above until the file is rolled)_
