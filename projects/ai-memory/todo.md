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

### opencode: deliver commands as native slash commands → [plan](archive/plans/opencode-native-commands.md)
- [x] P1 — Spike: opencode command loading
- [x] P2 — Manifest, frontmatter, tests, docs (needs: P1) — PR #154
- [x] P3 — Live verification (needs: P2)

### Initiative format: Now view, per-env Targets, one-line status, current-rules index, progress log → [plan](plans/initiative-now-view-per-env-targets.md)
- [x] P1 — Shared Target parser, new status grammar, @env, Closed rows, --tsv — e367e3f
- [x] P2 — Decision-stream metadata: topics enum, topic:, AMENDS, forward pointers — e284702
- [x] P3 — initiative-render.sh (Now, matrix, Current rules) (needs: P1, P2) — b2c4afb
- [x] P4 — Lint rules (needs: P1, P2, P3) — 8a4c7c4
- [x] P5 — Docs, template, commands, changelog (needs: P3, P4) — b59f4ea
- [x] P6 — Migration 3.0.0 (needs: P1, P2, P3, P4) — 0798c2e + fixes; PR #155 (Phases 1–6)
- [ ] P7 — vault-eks hand pass (needs: P5, P6)

## Done
_(checked items stay above until the file is rolled)_
