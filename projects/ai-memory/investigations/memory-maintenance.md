---
kind: investigation
task_ref: 3dbf6850-c619-8110-9189-fae09ad5422c
slug: memory-maintenance
status: scoped; awaiting /start brainstorm gate
created: 2026-11-07
---

# One-stop memory maintenance (absorbs /doctor)

## Goal
One entry point to keep the system healthy, runnable on a schedule. Two halves:
- **Installation health** (the original `/doctor` scope) — is it wired correctly?
- **Content hygiene** — is memory lean, current and true?

## Origin (2026-11-07)
A hand-run pass after an external review cut the ai-memory startup payload 65.2KB → 44.4KB
(16.2k → 11.1k tokens, 8 → ~6 chunks). Every step was manual; this task makes it repeatable.

| Step done by hand | Saved |
|---|---|
| Archived CLOSED/CONCLUDED `## Open threads` entries | 6.2KB |
| `/promote-memory` of a stale learnings section | ~5.9KB |
| Re-scored live threads against evidence (git, `gh`, tasks) → task / decision / wiki / close | ~3KB |
| Trimmed identity Git section + orchestrator-local duplicate | ~2.8KB |
| Trimmed domain `triggers:` lists (index Domain table) | 2.6KB |

The re-score step also found facts that had silently gone false (CI banner: `main` has no
protection), so hygiene is a correctness check, not only a size one.

## Proposed shape (not settled)
- **`scripts/maintain.sh` — scheduled, read-only.** Doctor checks + `lint-memory.sh` + payload
  breakdown → one report. Never mutates.
- **`/maintain-memory` — interactive.** Reads the report, walks fixes with approval, prints
  before/after.
- **Schedule via local launchd/cron**, not a cloud `/schedule` agent — most of the tree is
  gitignored and exists only on this machine.

### Doctor checks (original task)
Hooks registered; skill/agent symlinks not dangling; configured channel matches memory's claim;
local branch vs origin; project marker resolvable; dependencies present.

### Hygiene checks / mechanisms
| Check | Mechanism |
|---|---|
| Payload size + per-block/section breakdown, chunk count | `check-memory-size.sh --payload <p> --breakdown` (renderer exists) |
| Closed open threads | lint rule; archive via `checkpoint-archive.sh --section "Open threads" --closed-only` |
| Stale/large pending learnings | lint rule (age/count) → `/promote-memory` |
| Finished checkpoints | `/checkpoint-archive` |
| Live threads vs reality | interactive re-score step |
| Trigger lists > ~12 terms | lint rule → proposed trim, approved |
| Wiki `reviewed:` stale | lint rule |
| identity/doctrine size + cross-file duplication | report only; edits stay manual |

## Open design questions
- Thresholds (payload KB, learnings age/count, trigger count, wiki staleness days).
- Nudge: session-start alert when the report is unhealthy (piggyback initiative-alert) vs lint only.
- Report location and retention; whether the scheduled run covers all projects or the active one.
- Command naming; whether `/doctor` survives as an alias for the read-only half.
- Two-Path: each mutating step needs a documented manual equivalent.
