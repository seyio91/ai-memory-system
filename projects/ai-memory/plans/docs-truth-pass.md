---
plan: docs-truth-pass
status: in_progress
created: 2026-11-07
owner: claude (orchestrator)
task_provider: notion
task_ref: 411f6850-c619-8169-b8e5-fc0570e88aed
---

# Docs truth pass: Codex AGENTS.md drift and guard wording

## Goal
Make shipped docs match the implementation: Codex reads memory via live hook injection over a hand-owned static `AGENTS.md`, and the write guard is described as a drift report, not a gate.

## Success criteria
- `rtk proxy grep -rn 'generated .*AGENTS.md\|AGENTS.md.*generated' README.md docs/` returns only lines describing `build-context-md.sh` as an unused generic builder (or nothing).
- `docs/knowledge-lifecycle.md`, `docs/showcase.md`, `docs/demo-runbook.md` describe Codex delivery consistently with `harnesses/codex/manifest` and `docs/harnesses/codex.md`.
- `README.md` "Enforcement & safety gates" no longer calls the write guard a gate; it states it reports drift after the write.
- Ride-along domain edits from 2026-11-07 (`domain/agent-tooling.md` knowledge entry, trimmed `triggers:` in `domain/agent-tooling.md` + `domain/codex.md`) ship in the same PR.
- `bash scripts/run-tests.sh` passes (full run, signing off locally).
- PR opened via `git-cli ship`; not merged.

## Design
Hand-edit the cited lines; source of truth is `harnesses/codex/manifest` + `docs/harnesses/codex.md`. Showcase/demo-runbook are narrative — rewrite the Codex sentence/diagram node, don't restructure. No changelog fragment: docs + domain content only, no behavior change (CONTRIBUTING: fragments are for user-visible behavior).
Rejected: a `check-docs.sh` axis pinning harness claims to manifests — not built until this drift class recurs (user, 2026-11-07).

## Decisions (locked)
- Ships the pending `domain/` edits from the 2026-11-07 maintenance pass (user, 2026-11-07).
- No manifest-claims check in `check-docs.sh` until Codex/harness doc drift recurs (user, 2026-11-07).
- `projects/ai-memory/**` housekeeping (memory.md `push: main` decision, `memory-maintenance` investigation, this plan) goes to `main` via `git-cli commit`, not in the PR.

## Phases

### Phase 1 — Fix the drift and wording; ship
Edit `docs/knowledge-lifecycle.md:24,61,67`, `docs/showcase.md:275,291,327`, `docs/demo-runbook.md:170`, `README.md:108`. Include the domain ride-alongs. Run the suite, then `git-cli ship`.
**Verify:** all success criteria hold on the branch; PR open.

## Risks / open questions
- Showcase line 327 references a demo step count ("27/27"); leave counts alone, change only the Codex claim.
- Other stale Codex claims may exist outside the cited lines — P1 greps the whole `docs/` + README, not only the cited lines.
