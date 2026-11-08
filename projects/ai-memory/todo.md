# Todo — ai-memory

> Single source of truth for executable work on this project.
> Large items link to a plan under `plans/`.
> Tick boxes in place when done. When all items here are checked (or the orchestrator decides to roll), snapshot this file to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
> A phase that depends on another carries `(needs: Pn)`, mirrored from the plan's `**Depends:**` line — this file is what gets read on resume, so order must be legible here and not only in the plan. No annotation means independent and safe to run in parallel.

## Active

### Split /checkpoint: model synthesizes, script does bookkeeping → [plan](plans/checkpoint-script-split.md)
- [ ] P1 — Parser, prepare, identifier expansion
- [ ] P2 — apply: validate, merge, write, report (needs: P1)
- [ ] P3 — Wire command, Codex, docs, changelog (needs: P2)

### opencode: deliver commands as native slash commands → [plan](plans/opencode-native-commands.md)
- [x] P1 — Spike: opencode command loading
- [ ] P2 — Manifest, frontmatter, tests, docs (needs: P1)
- [ ] P3 — Live verification (needs: P2)

## Done
_(checked items stay above until the file is rolled)_
