---
investigation: lint-memory-size-and-drift-gaps
project: ai-memory
status: open
created: 2026-08-27
owner: seyi
task_ref: 3c9f6850-c619-812d-876b-c8a005cb1af7
---

# lint-memory.sh — no size check, and the changelog-drift regex is too narrow

Found while reducing `projects/fiter-argo-apps/memory.md` from **55,912 → 15,984 B** (2026-08-27).
The reduction was a five-phase plan done by hand. The linter contributed nothing to detecting the
problem, and would not detect a recurrence.

## Finding 1 — there is no size check

```
grep -E 'wc -c|size|bytes|MAX_' scripts/lint-memory.sh   # zero hits
```

`projects/<name>/memory.md` is auto-injected into every session for its project, so its byte count
is a tax paid on **every prompt in every session** against that repo — not a one-off cost. The
fiter-argo-apps file reached 55,912 B: roughly **2× the next-largest** (`ai-memory`, ~28 KB) and
**~5× the fleet median** (~11 KB across 20 projects). Nothing ever said so. It was found by hand.

Related distribution fact from the same survey: only **3 of 20** projects have a `## Decisions Log`
at all, and fiter-argo-apps' was **8× the next largest by bytes**. A per-file size WARN would have
surfaced this years earlier than a human noticing.

## Finding 2 — `CHANGELOG_RE` is set so tight that an append-only log passes clean

`scripts/lint-memory.sh:177`:

```sh
CHANGELOG_RE='merged via PR|PRs #[0-9]|PR #[0-9]+ merged|complete as of'
```

It fired on **2 of ~73** Decisions Log entries in that file, both via `PRs #[0-9]`. Phrasings
present in the file, all pure event, all unmatched:

| phrasing | why it slips |
|---|---|
| `pinned here by PR #208` | single PR + preposition — not `PR #N merged` |
| `closed 2026-08-04`, `Fully closed 2026-08-07`, `track closed` | no PR token at all |
| `SHIPPED and MEASURED (PR #206, 2026-08-06)` | PR is parenthetical |
| `Recovered by hand the same day (20:45Z)` | narrative with a timestamp |
| `**[2026-08-06]**` entry prefixes | **the strongest single signal** of an append-only log — entirely unmatched |

The comment at `:174-176` states the narrowness is deliberate, to spare legitimate single-anchor
gotchas like `"fixed in PR #83 via ..."`. That trade-off is sound in principle. It is currently
calibrated such that a 24 KB changelog scores clean, which is the wrong end of the range.

## Suggested shape — not prescriptive

- **Size.** WARN above a threshold on `projects/*/memory.md`. **25 KB** is the figure the
  fiter-argo-apps plan used as its exit criterion and hit with margin (final 15,984 B).
- **Per-bullet budget.** More useful than the file total. That plan found **max ≤ 400 B, median
  ≤ 250 B** across `## Known Constraints / Gotchas` + `## Architecture Decisions` to be the
  operative mechanism — it is checkable on every future write, whereas total file size is a lagging
  outcome that drifts. Baseline before the work: Known Constraints averaged **501 B** across 33
  bullets against Architecture Decisions' **225 B** across 9, in the same file — the spread itself
  was the tell.
- **Drift patterns.** Add the dated-entry prefix (`^\*\*\[\d{4}-\d{2}-\d{2}\]\*\*`) and the
  `closed <date>` / `shipped` / `<verb> in PR #N` family. Keep at WARN, never ERROR — a false
  positive on a legitimate anchor must not block.

## Why it matters

Without a gate, that file regrows. Its rewritten `## Current State` still carries live
fleet-inventory claims — WAL-guard coverage across 7 workload + 3 addon clusters, per-tenant
monitoring enablement — as present-tense facts with **no verification pointer and nothing detecting
when the fleet moves**. That is the most likely re-drift vector and exactly the class a
staleness/size gate would catch. See `projects/fiter-argo-apps/archive/plans/memory-md-decisions-log-reduction.md`
for the full method and its Phase 5 verification.

## Related gaps, same owner — split out if preferred

- **`wikis/` is undocumented system-wide.** Absent from `docs/file-formats.md` and
  `projects/_template/`. The 5 pre-existing pages in fiter-argo-apps used **3 incompatible
  frontmatter shapes**; the reduction plan had to pick one arbitrarily for new pages.
- **"Never read `archive/`" is prompt-enforced only.** A broad grep bypassed it during this work
  and surfaced only because the executor volunteered that it had done so. A hard rule with no
  mechanical backing is a convention, not a rule.
