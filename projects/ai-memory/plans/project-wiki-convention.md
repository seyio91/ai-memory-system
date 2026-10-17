---
plan: project-wiki-convention
status: in_progress
created: 2026-10-17
owner: claude (orchestrator)
task_provider: local
task_ref: split-project-memory-into-always-injected-core-and-on-demand-topic-files
---

# Project wiki convention

## Goal

Document `projects/<name>/wikis/` as the home for reference detail too large for `memory.md` — location, domain-style frontmatter, and a `## Pointers` link from `memory.md` — route writes to it from the doctrine and `/promote-memory`, and bring the 5 existing wiki pages into line. No new loading mechanism, no lint.

## Success criteria

- `docs/file-formats.md` defines `projects/<name>/wikis/*.md`: location, required frontmatter (`topic`, `scope`, `summary`, `reviewed`; optional `repo`, `category`), and the rule that each page is linked from its project's `memory.md` `## Pointers`.
- `projects/ai-memory/wikis/memory-md-content-contract.md` states that reference detail too big for `memory.md` belongs in a wiki page linked from Pointers.
- The doctrine's wiki-page offer (`doctrine/orchestrator.md`) names the `wikis/` location; `test_orchestrator_core_overlay.sh` still passes (≤ 14,336 B).
- `/promote-memory` lists a project wiki page as a promotion target alongside domain and `memory.md`.
- All 5 `projects/*/wikis/*.md` carry `topic`/`scope`/`summary`/`reviewed` frontmatter (`awk` frontmatter check over every file).
- Every wiki page is mentioned as `wikis/<file>.md` in its project's `memory.md` (`grep` per file returns a hit for all 5).
- `on-demand-project-load` investigation no longer carries this task's `task_ref`.
- `bash scripts/run-tests.sh` (signing off) passes in full; `changelog.d/` has a `feature` fragment; PR opened via `git-cli ship --intent`.

## Design

Documentation-only convention: `docs/file-formats.md` is the spec, the content contract states when to use it, and the two write-time paths (doctrine wiki-page offer, `/promote-memory`) point at it so it is used. Domain-style frontmatter because 3 of 5 pages and every `domain/*.md` already use it, and `reviewed` doubles as a staleness date.

Rejected:
- Topic files loaded on trigger words (original task scope) — trims brought every `memory.md` under 16 KB; wiki + Pointers link already covers the need.
- Lint for linkage or frontmatter — user chose review-only enforcement.
- Near-budget (~80%) warning — YAGNI; 16 KB WARN + write guard already report.
- `/new-wiki` scaffold command — too much surface for ~5 pages.

## Decisions (locked)

- Location `projects/<name>/wikis/*.md`; frontmatter `topic`, `scope`, `summary`, `reviewed` (+ optional `repo`, `category`).
- Linked from `memory.md` `## Pointers` as `wikis/<file>.md` — wikis are not archived, so a path is stable.
- No lint; no new loading mechanism.

## Phases

### Phase 1 — Document the convention
`docs/file-formats.md` wikis section; content contract rule; doctrine wiki-offer line names `wikis/`; `/promote-memory` third target; `changelog.d/project-wiki-convention.feature.md`.
**Verify:** criteria 1–4 hold by reading the diffs; `test_orchestrator_core_overlay.sh` and `check-docs.sh` pass.

### Phase 2 — Migrate existing pages
Rewrite frontmatter of ai-memory's `env-var-doc-gate` and `memory-md-content-contract` to domain-style; add `## Pointers` to `projects/ai-memory/memory.md` linking both; add a Pointers line for `kyverno-prod-audit-baseline` in `projects/k8s-addons/memory.md` (gitignored — local edit); drop `task_ref` from `on-demand-project-load`.
**Verify:** criteria 5–7 via the awk/grep checks; `check-memory-size.sh --file` clean for both `memory.md` files.

### Phase 3 — Ship
**Depends:** P1, P2
Full suite with signing off; `git-cli ship --intent`.
**Verify:** criterion 8 — suite green, PR URL returned.

## Risks / open questions

- Revisit lint only if wikis drift back to mixed frontmatter or go unlinked.
- On merge: close Target `ai-memory/topic-split` and the task; the trigger-loaded topic-file idea is dropped, not deferred.
- `on-demand-project-load` (project switching) is likely superseded by `/pin`; archiving it is a separate decision.
