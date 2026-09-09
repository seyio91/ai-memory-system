---
investigation: lint-known-constraints-domain-rehoming
status: open
created: 2026-08-30
owner: claude (orchestrator)
task_ref: 3cbf6850-c619-8142-80c4-ca98ae158719
---

# Extend lint-memory to flag Known Constraints bullets that belong in a domain file

## Problem

`## Known Constraints / Gotchas` in a project `memory.md` accumulates cross-project knowledge that
nothing ever evicts. The section is **injected in full on every prompt**, so each misfiled bullet is
a permanent context tax on every session for that project — and simultaneously invisible on the
other repos where it actually applies.

Worked example, `fiter-argo-apps`, 2026-08-30: the section had grown to 57 bullets / 16.9 KB. A
manual pass removed or merged 9 and rehomed 4 to `domain/{k8s,argocd,helm}.md`, landing at 48
bullets / 15.5 KB. Every one of the four rehomed bullets was **fully generic** — a `kubectl -o
jsonpath` trap, ArgoCD `Synced/Healthy` being cached state, an SSA rollout rule for single-replica
RWO Deployments, and a chart-bump review checklist. None mentioned the repo, a cluster, or a
workload. All four now apply on Revving and Access work, where they had been unreachable.

The same pass also found a **contradiction** (two `enablePDB` bullets giving opposite-sounding
instructions, added months apart) and two **duplicates** (one restating the bullet directly above
it; one restating an `## Architecture Decisions` entry). None of this is detectable today.

## What the linter does now

`scripts/lint-memory.sh` (363 lines) checks section **presence** only:

```sh
REQUIRED_PROJECT_SECTIONS=( "## What It Is" "## Current State" … )
if ! grep -qxF "$section" "$f"; then emit "WARN: … missing section: $section"; fi
```

It never reads bullet content. There is also no size check on any section or file — already noted
as a gap in `fiter-argo-apps` working memory.

## Proposed checks

All advisory `WARN`, all fail-open. Each is independently shippable; the first is the one that
motivates the task.

1. **Rehoming candidate.** A bullet in `## Known Constraints / Gotchas` (or `## Architecture
   Decisions`) that contains **no project-scoped proper noun** is a candidate for a domain file.
   Cheap signal, and it correctly separates the worked example: the four rehomed bullets named
   nothing local, while the one that stayed named `FiterDevWorkloadPartiallyScaledUp`. Build the
   local-noun set per project from things already on disk — the project name, `repo`/`repo_path`
   frontmatter, sibling names in `## Related Projects`, and capitalised or hyphenated identifiers
   that appear nowhere in `domain/`.
2. **Suggest the destination.** Match the bullet against each `domain/*.md` `triggers:` list and
   name the best hit in the warning (`… looks cross-project; consider domain/argocd.md`). Falls
   back to "no domain matches — may need a new one", which is how `domain/scale-to-zero.md` came
   to exist in the same session.
3. **Near-duplicate within a project.** Two bullets in the same file sharing a high proportion of
   rare tokens. Catches both the verbatim restatement and the Known-Constraints-vs-Architecture-
   Decisions overlap.
4. **Section size.** Warn past a bullet count or byte budget for the injected sections, so growth
   surfaces before someone notices by eye.
5. **Event residue (present-tense test).** Flag a sentence in `## Current State` — and any bullet
   elsewhere — whose payload is an *event* rather than a standing fact. Memory keeps decisions and
   constraints; git keeps events. **Ship this first.** It is a different and easier problem than
   check 1: where "is this cross-project?" is a semantic judgement no regex can make, "is this
   written as history?" has strong surface markers, so it should have both a higher hit rate and a
   lower false-positive rate. Markers, all cheap: past-tense verbs against a work noun (`was
   removed`, `landed`, `merged`, `shipped`, `closed`, `resolved`, `fixed`); a PR/commit/issue
   reference (`PR #\d+`, a 7–40 char hex SHA); a bare date in prose; and the drift words `now`,
   `still`, `until`, `as of`, `no longer`, `already`, which almost always mark a sentence written
   relative to a moment rather than stated flatly.

   Worked examples, all from `fiter-argo-apps` `## Current State` on 2026-08-30 — one paragraph of
   four facts contained three defects, two of them event residue:

   | text | verdict |
   |---|---|
   | `` `oxygen` is fully removed; zero references remain `` | event — a completed deletion nothing acts on |
   | `` `provisioning-service-db` was the last multi-instance one until PR #235 (2026-08-30) `` | event — past tense + PR ref + date, and it was **8 hours old** when flagged |
   | `` The `access` setting is dead config because it is RDS-backed `` | not event residue — a *rule* duplicated from Known Constraints (check 3 territory) |
   | `` `max_slot_wal_keep_size` is set on all seven workload clusters `` | clean — present-tense standing fact |

   Note the second example's provenance: it was written **that same session** by the agent updating
   memory after shipping the change, then flagged and rewritten hours later. Event residue is not
   only legacy sediment — it is generated continuously, at the moment work lands, by the habit of
   recording what just happened. That is the argument for a mechanical check rather than periodic
   manual passes: the defect is produced faster than review catches it.

## Design constraints

- **Do not auto-move.** The linter must report, never edit. `projects/*` is gitignored, so there is
  **no git safety net** — a wrong move is unrecoverable without a manual `.bak`. Deciding whether a
  bullet is genuinely cross-project is a semantic judgement a regex cannot make; the linter's job is
  to surface candidates for an agent or human to act on. If a mutating mode is ever added it must be
  opt-in, print a diff, and take its own backup first.
- **Expect false positives, and make them cheap.** A generic-sounding bullet can still encode a
  local fact (`sync waves span -10 through 4` reads generic; the range is repo-specific). Warnings
  must be dismissible without editing the bullet.
- **Two-Path principle.** Whatever the check emits must correspond to something a human can do by
  hand — i.e. it points at a bullet and a destination file, nothing tool-only.
- **Shell portability.** macOS bash 3.2: no `mapfile`, no associative arrays. See [[shell]].

## Success criteria

- Running the linter against the pre-trim `fiter-argo-apps` `memory.md` — fixture at
  `projects/ai-memory/fixtures/fiter-argo-apps-memory-2026-08-30-pre-trim.md`, 16,873 B, 57 bullets
  — flags the bullets that were in fact rehomed, and does **not** flag the
  `FiterDevWorkloadPartiallyScaledUp` one that correctly stayed. The fixture's `README.md` carries
  the full label set: 8 true positives, 3 true negatives, 2 known duplicates, 1 contradiction.
- The duplicate check flags the two known duplicates in that same fixture.
- The event-residue check flags both known cases in `## Current State` (`oxygen` fully removed;
  `provisioning-service-db` … `until PR #235`) and does **not** flag the standing facts sitting in
  the same paragraph. Both are present in the fixture.
- No warning is emitted for any bullet that names a project-local identifier.
- Exit status unchanged for existing callers; new findings are `WARN`, never `ERROR`.

## Provenance

Arising from a manual Known Constraints trim on `fiter-argo-apps`, 2026-08-30. Related known gaps in
the same script, worth folding in if this is picked up: no size check anywhere, and the
changelog-drift regex misses some phrasings.
