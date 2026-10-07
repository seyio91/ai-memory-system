---
doc: memory-md-content-contract
kind: component
status: current — size + drift enforced; staleness, twice rule, prune cadence unbuilt
created: 2026-10-07
owner: claude (orchestrator)
---

# The project `memory.md` content contract

`projects/<name>/memory.md` is injected whole into every session for its project, so it plays
the role Anthropic's `CLAUDE.md` plays. This page states what belongs in it, the budgets it is
held to, and which parts of that are enforced. Source guidance: code.claude.com/docs/en/best-practices,
code.claude.com/docs/en/memory, code.claude.com/docs/en/large-codebases.

## The per-line test

For each line: **would removing this cause Claude to make a mistake?** If not, cut it.

| Include | Leave out |
|---|---|
| Commands Claude can't guess (build, test, lint, render, release) | Anything readable from the code (inventories, pins, defaults, layout trees) |
| Style rules that differ from defaults | Standard language conventions |
| Test instructions and the preferred runner | Detailed API/reference docs — link them |
| Branch naming, commit and PR conventions | Information that changes often — status, versions, counts, PR numbers, SHAs, dates |
| Project-specific architectural decisions (with the why) | File-by-file descriptions |
| Gotchas and non-obvious behaviour | Self-evident advice |

House corollary, already standing: **`memory.md` holds what stays true; `working.md` holds what
happened.** A "verified on <date>, PR #N" story is an event; keep the one-sentence rule it produced.

## Budgets

- **Bytes, not lines.** The 200-line guideline is defeated by paragraph-length bullets —
  `ai-memory/memory.md` measured 130 lines but 44.7 KB (2026-10-07). Target ≤ ~12–16 KB per file
  and ≤ ~400 B per bullet (the per-bullet figure is the operative one; see investigation
  `lint-memory-size-and-drift-gaps`).
- **Payload ceiling.** Claude delivers the session payload in `session_chunks` × 9,000 B
  (`harnesses/claude/manifest`, `scripts/hooks/lib.sh`), ≈ 108 KB. Base (identity + orchestrator +
  index) is ~24 KB before any project content. Anything past the ceiling is truncated from the
  tail — which is `working.md` — with no warning.

## Lifecycle rules

- **Twice.** A correction earns a line when Claude makes the same mistake a second time.
- **Each release.** Rules written around an older model's or harness's limits are re-checked and
  deleted when they no longer bind. A rule a hook already enforces is prose overhead.
- **One home per fact.** Cross-project → `domain/`; a procedure → a skill or command; reference
  material → repo docs or a wiki, linked. A repo with its own `CLAUDE.md`/README: memory holds only
  what that file lacks (cross-repo ordering, traps, decisions).

## Failure modes seen in the 2026-10-07 audit

- `## Current State` / `## Current Goal` were required by lint and invited exactly the
  frequently-changing content above; they were the dominant source of wrong entries (now retired).
- Facts copied between sibling projects without re-checking the target repo became false there.
- Stale workaround rules outlived their fix and contradicted `domain/` (rtk).
- Inline `[NEEDS REVIEW]` markers rot in both directions.

## What is enforced today

- Sections + frontmatter (`scripts/lint-memory.sh` rule 3): required What It Is, Architecture Decisions, Known Constraints / Gotchas; optional Commands, Conventions, Pointers, Related Projects. `## Current State` / `## Current Goal` are retired — lint WARNs on them naming the new home, and `/state` reads the goal from `todo.md`. The include/leave-out table ships in `docs/file-formats.md`; the template carries a one-line pointer to it.
- Size (`scripts/check-memory-size.sh`, lint rule 16): WARN when a project `memory.md` exceeds 16 KB, one
  WARN per file for lines over 400 B, ERROR when a project's rendered payload needs more chunks than a
  harness's `session_chunks` (claude/xml, codex/md). The payload check counts slices with the same code
  delivery uses (`scripts/payload-slices.py`) and pins the working file explicitly — shared `working.md`
  plus every `working.<key>.md` overlay — because cwd-based resolution inside a worktree silently drops
  the shared file. A byte pre-filter (75 % of capacity) skips the exact render for small projects.
- On write (`scripts/hooks/memory_write_guard.sh`, exit 2 on findings): `memory.md` → drift + size + payload;
  `working*.md` → payload only; `domain/*.md` → drift only. Still hand-wired in `settings.json`, not installed
  by `install.sh` (tracked as its own Target).
- Dated-log drift: bracketed and bulleted dated entries are flagged in project `memory.md`; domain
  `## Knowledge` stays dated by design, and `/promote-memory` no longer dates project decisions.
- Nothing yet checks staleness against the repo, the twice rule, or a prune cadence.

Closing those gaps is tracked by initiative `memory-md-hygiene`.
