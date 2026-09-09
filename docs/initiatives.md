# Initiatives

An initiative is a root-level, cross-project coordination artifact at
`initiatives/<slug>.md`. It holds an append/supersede **decision stream** and
the initiative's **Targets**. The stream is provenance: why the work is split
and which decision is current. Target readiness is derived visibility: it is
read from project plans and todos on demand rather than authored as another
status record.

Initiatives are intentionally not listed in `index.md`. The index is a durable
knowledge roster; active initiatives are mutable work state, client-specific,
and are loaded only when a task or breadcrumb points to one.

## File format

An initiative starts with this frontmatter contract:

```yaml
---
kind: initiative
slug: kebab-case-name
status: active # active | closed
created: YYYY-MM-DD
---
```

Its `## Targets` section contains one `### <project>/<slug>` heading per
Target. IDs are unique within the file. Common fields are `execution_mode:`,
optional full-UUID `task:`, optional `plan: projects/<project>/plans/<file>.md`,
`depends_on:`, and `next_actor:`. `software_adw` Targets additionally declare
an ordered `stages:` list (`discover -> design -> plan`, for example).
Interactive Targets carry an asserted `status:` instead and never declare
stages. `lint-memory.sh` checks these structural rules and that dependency IDs
resolve inside the same initiative.

The decision stream is append-only: append a new decision and mark an older
one `SUPERSEDES <id>`; do not rewrite history.

## Stream-first capture

Record a cross-repo decision in the initiative `## Decision stream` at decision
time as `D<n>-proposed`. Plan, runbook, and project-memory entries are
projections that carry the stream id; the stream is the record. Check at every
plan-phase completion and during `/checkpoint`, never at handover.

## Create and close

Use `/new-initiative <kebab-case-slug>` to scaffold an active instance from
`initiatives/_template.md`. It refuses an existing path. After creating it,
add a breadcrumb-only row to every affected project's `## Related Projects`
table; keep the status and decision stream in the initiative itself.

Opening and closing are explicit user actions. On close, fill `## Closure`
with the date, final Target states, and where follow-on work moved, then move
the file to `initiatives/archive/`. Derived output may identify a candidate for
closure but never closes an initiative itself.

## Readiness derivation

Run:

```sh
bash scripts/initiative-status.sh <slug>
```

It reads local markdown and local checkout paths only: no network, provider,
or GitHub calls. The result is a hand-derivable markdown table with Target
stage/status, evidence, dependency satisfaction, and next actor.

| Software ADW fact | Derived stage |
|---|---|
| no `plan:` pointer | `not-started` |
| live plan `status: draft` | `plan` |
| live plan `status: in_progress` | `implement` |
| live plan `status: done`, or matching plan in `archive/plans/` | `complete` |
| project memory, `repo_path` checkout, plan pointer, or plan cannot resolve | `unknown` |

Todo checkbox counts are evidence, not an independent status. Interactive
Targets echo their asserted `status:` (or `no status asserted`). A dependency
with `(stage: X)` is satisfied when its Target is complete, or has reached at
least X in its declared stages; an asserted-done interactive Target also
satisfies dependencies. Unknown facts fail closed. A requested stage not in
the depended Target's declared list produces a warning.

## Staleness detection

`initiative-status.sh` also detects a software ADW Target that advanced without
a corresponding decision-stream entry. Each normal run compares recomputed
derived stages and the `## Decision stream` entry count (every line matching
`^- D[0-9A-Za-z]*`, including `-proposed`) with
`initiatives/.state/<slug>.snapshot`. A Target is stale only when its stage
changed while that count did not; interactive Targets never participate.

The snapshot is plain text: one explanatory comment, one
`<target-id> <derived-stage>` line per software ADW Target, then
`stream-entries <count>`. It is intentionally hand-editable under the Two-Path
principle: update those lines to acknowledge the current state without running
the script. Otherwise, run `bash scripts/initiative-status.sh --ack <slug>`.

The warning persists across normal runs. The snapshot refreshes only on its
first creation, when a decision-stream entry is appended (implicit
acknowledgment), or with `--ack`; it never self-silences merely because the
script ran again.

The session-start full payload surfaces stale Targets as one exception-only
`<memory:initiative-alert>` block. It is never per-prompt and never a status
table. The hook guard fails open: a crashed checker is silent by design; the
checker is tested separately.

## Breadcrumb row template

Paste this row into an affected project's `## Related Projects` table:

```markdown
| *initiative:* `<slug>` | `<when this project's work touches a Target>`. Append `D<n>-proposed` to the stream at decision time; never hand-carry a cross-repo decision to handover; check readiness with `bash scripts/initiative-status.sh <slug>`. | `initiatives/<slug>.md` — decision stream + Targets (pointer only; no status duplicated here). |
```

## Deliberately deferred

Phase 1 does not build a transition guard, reusable Target templates, or
autonomous status progression. Those controls remain deferred until an
observed initiative run demonstrates the need.
