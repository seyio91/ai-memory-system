# Initiatives

An initiative is a root-level, cross-project coordination artifact at
`initiatives/<slug>.md`. It holds an append/supersede **decision stream**, the
initiative's **Targets**, and three generated views of them. The stream is provenance: why the work is split
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
envs: [staging, prod] # optional: environment columns for the matrix
topics: [auth, storage] # optional: enum for decision `topic:` lines
---
```

The body holds, in order: `## Objective`, `## Normative contract`, the
generated `## Now` and `## Environment matrix` (the latter only when `envs:`
is set), `## Targets`, the generated `## Current rules`, `## Decision stream`
and `## Closure` (see Generated sections below).

### Targets

`## Targets` contains one `### <project>/<name>[@<env>]` heading per Target.
Ids are unique within the file. An `@<env>` suffix splits one piece of work
across environments (`infra/db@staging`, `infra/db@prod`); the id is a plain
string, so `depends_on: infra/db@staging` resolves to exactly that Target, and
each `@env` should name an entry of frontmatter `envs:`. Fields, each on ONE
line (lint and derivation read the first line only):

| Field | Meaning |
|---|---|
| `- execution_mode:` | `interactive`, `software_adw`, `runbook` or `automated` |
| `- task:` | optional full-UUID task-provider pointer; the only pointer a Target carries. The plan that carries it out is found by matching it against plan frontmatter `task_ref`, never authored on the Target |
| `- scope:` | one line saying what the Target delivers |
| `- jira:` | optional ticket reference |
| `- stages:` | `software_adw` only: ordered list (`discover -> design -> plan`) |
| `- depends_on:` | `<target-id> [(stage: <stage>)]`, comma-separated, or `none` |
| `- status:` | the one-line status below |

The status line is
`- status: <open|blocked|done|closed> · next: <session — action> · blocked_by: <…|none>`
with single spaces around the middle dot. `next:` names the session that acts
and the action, separated by ` — `. `blocked_by:` is free text or `none`.

Three authoring rules keep the Now view and lint in agreement:

- `next:` starts with `user —` whenever the user acts first, chained as
  `user — …; then <session> — …`. The Now view groups on that first word.
- `blocked_by:` holds only blockers that are not Targets. Cite a decision by
  its D-id (`D12`); free text that names a decision without the id is not
  picked up. Targets that block this one go in `depends_on:`.
- A Target with unfinished `depends_on` is `status: blocked`. Plan-ahead work
  that may proceed goes in the `next:` text. Lint warns on an `open` Target
  whose dependencies are not satisfied.

Terminal states may stand alone (`- status: done`, `- status: closed`) or carry a full valid tail (`- status: done · next: … · blocked_by: none`). `status:`
is required for `interactive` Targets and optional for `software_adw` ones,
whose stage is derived from the plan. Keep it short (lint warns past 300
characters); put prose in `scope:` or the progress log.

A terminal status (`done` or `closed`, in any `execution_mode`) short-circuits
derivation entirely: no plan lookup, no checkout resolution. Once a Target is
finished (`done`), move it into the `### Closed` table, the only non-Target
heading allowed under `## Targets`. The table holds `done` Targets only:

```markdown
### Closed

| id | closed | jira | outcome |
|---|---|---|---|
| infra/db@staging | 2026-10-01 | ABC-1 | shipped |
```

A Closed row is a terminal `done` Target: `depends_on` can still name it and
it satisfies the dependency. An abandoned Target is not a Closed row: it keeps
its `### ` heading with `- status: closed`, and it never satisfies a
dependency, so its dependents stay blocked until they are re-planned. `lint-memory.sh` checks these structural rules and
that dependency ids resolve to a heading or a Closed row.

### Decision stream

The decision stream is append-only. Entry shape:
`- D<n> <status> <YYYY-MM-DD> — <decision>`. The id never changes and is
unique, except that `superseded` copies may repeat it; the date is bare and is
the date of the last status change. Status is one of:

| Status | Meaning |
|---|---|
| `proposed` | Recorded at decision time, not yet confirmed by the user; carries an `  unconfirmed:` line saying what is missing |
| `confirmed` | Confirmed by the user; carries an `  evidence:` line naming the artifact that absorbed it |
| `rejected` | Rejected by the user; kept on record, binds nothing |
| `superseded` | Replaced by a later entry (`SUPERSEDES <id>`) |
| `retired` | Bound something, then withdrawn; also an agreed decision no repo absorbed, set at initiative close with its `unconfirmed:` line kept |

Continuation lines are indented under the entry: `  topic: <name>` (one of
frontmatter `topics:`; lint warns when a live, i.e. confirmed or proposed,
entry lacks it while `topics:` is declared), `  evidence:`, `  unconfirmed:`, `  binds:`, and the keywords
`  SUPERSEDES <ids>` and `  AMENDS <ids>` (upper-case, optional colon). A
forward pointer `→ D<n>` (a list is `→ D75, D80`) sits on the head after the
date and before the ` — `:

```markdown
- D45 superseded 2026-10-05 → D75 — token format v1
  topic: auth
- D75 confirmed 2026-10-05 — token format v2
  topic: auth
  SUPERSEDES D45
  evidence: projects/x/plans/p.md
```

**Amendment rule.** From now on, changing a decision means appending a new
entry: `SUPERSEDES <id>` when it replaces the older one, `AMENDS <id>` when it
changes part of it and the older one stays live. The older head gets the
forward pointer `→ D<new>`; its decision text is never rewritten. Amendments
made in place before this rule stay as written. The only in-place edits to an
existing entry are its status and date, its forward pointer, and its
`evidence:` and `unconfirmed:` lines. Lint warns when a SUPERSEDES/AMENDS
target lacks the pointer, when a pointer names a missing entry, and when a
keyword line names no id.

Frontmatter `legacy_through: D<n>` marks entries that predate these rules:
plain ids (no letter; `D6b` is never legacy) at or below it are exempt from the
date, `evidence:` and `unconfirmed:` checks (derived, not authored per entry).
A `D<n>-proposed` reference in older prose means `D<n>`; references are never
rewritten.

Proposals are resolved at close-out. `/plan-done` on a plan whose `task_ref`
is an active initiative's Target lists every `proposed` entry in that
initiative and asks the user to confirm, reject or leave each one. A confirm
needs the absorbing artifact; without one the entry stays `proposed`. Initiative
close requires the same first (below). Only the user resolves a proposal.

## Generated sections

Three sections are generated from the Targets and the decision stream by
`scripts/initiative-render.sh`, each in a fence directly under its heading:

| Heading | Fence key | Contents |
|---|---|---|
| `## Now` | `now` | decisions needed, Targets waiting on you, Targets to start, Blocked Targets (unsatisfied `depends_on` plus authored `blocked_by`), open proposals |
| `## Environment matrix` | `matrix` | one row per base name of `@env` Targets, one column per `envs:` entry, each cell the derived stage of `<base>@<env>` (the `--tsv` stage: derived for `software_adw`, the asserted state otherwise) or `not opened` |
| `## Current rules` | `rules` | one row per `topics:` entry listing its live (confirmed and proposed) decisions |

```markdown
## Now
<!-- BEGIN AUTOGEN initiative-render:now -->
...
<!-- END AUTOGEN initiative-render:now -->
```

The markers are `<!-- BEGIN AUTOGEN initiative-render:<key> -->` and
`<!-- END AUTOGEN initiative-render:<key> -->`. Bodies carry no date, so a
render is deterministic. Everything outside a fence is hand-authored and never
touched by the script.

```sh
bash scripts/initiative-render.sh <slug>           # print the fences
bash scripts/initiative-render.sh <slug> --write   # rewrite fences in place
bash scripts/initiative-render.sh <slug> --check   # exit 1 if a fence is stale
```

`--write` inserts a missing section (`## Now` and `## Environment matrix`
before `## Targets`, `## Current rules` before `## Decision stream`). With no
`envs:` there is no matrix section; a leftover matrix fence is an orphan that
`--check` reports and `--write` removes. `lint-memory.sh` runs `--check` on
active initiatives that have at least one Target and no format ERROR, and warns when a fence is stale or missing. Run `--write`
after editing a Target status, `depends_on`, `envs:`, `topics:` or the stream.

**Two-Path hand edit.** The script is a convenience, not the only route: write
the same text by hand inside each fence. A hand render must equal the script's
byte for byte, so follow these exactly. In every table cell, an unescaped `|`
becomes `\|` (an already escaped `\|` stays).

- `now`: take the Targets whose state is not `done`/`closed` and whose stage
  is not `done`/`closed`/`complete` (so Closed rows drop out). Each is Ready or
  Blocked. The body has five sections, in this order: `Decisions needed`,
  `Waiting on you`, `Sessions to start`, `Blocked`, `Open proposals`.
  - Build the Blocked cell from up to three parts joined with `; `, in this
    order: `stage unknown` when the stage is `unknown`; the unsatisfied
    `depends_on` edges joined with `, `, each `<id> (<wording>)` (below); the
    authored `blocked_by` unless it is `none` or absent.
  - Edge wording, from the `--tsv` `unsatisfied` column (`--tsv` itself is
    unchanged): `(blocked)` when the dependency's state is `blocked`;
    `(closed)` when it is `closed` (abandoned, so the edge can never be
    satisfied and must be rewritten); `(needs <stage>)` for a stage-qualified
    edge whose dependency has not reached that stage; `(not found)` when the
    id resolves to no Target; `(stage unknown)` when the dependency's stage
    cannot be derived; `(not done)` otherwise.
  - A Target is Blocked when that cell is non-empty, or its state is
    `blocked`, or its dependencies are not all satisfied; an otherwise empty
    cell reads `blocked (no reason given)`. Every other Target is Ready.
  - Ready splits on the first actor of `next:`, the text before the first
    ` — `. Exactly `user` goes to Waiting on you; anything else, or no
    `next:`, goes to Sessions to start. `<next>` is the authored `next:`, or
    `(stage: <stage>)` when none is authored.
  - Waiting on you and Sessions to start are each `**<name>**`, a blank line,
    `| Target | Next |`, `|---|---|`, one `| <id> | <next> |` row per Target,
    then a blank line. With no rows write `**<name>:** none` and a blank line.
  - Blocked is the same with `| Target | Blocked by |`. Rows are sorted by how
    many non-terminal Targets each holds up, directly or transitively through
    `depends_on`, most first; ties stay in Target order. Hold-up does not pass
    through a `done`/`closed` Target, and a `(not found)` edge holds nothing
    up.
  - Decisions needed is the same with `| Decision | Blocks |`. It lists each
    `proposed` decision whose D-id (`D12`, or `D6b` with a lowercase letter)
    appears in the `blocked_by` of a non-terminal Target. Each row is
    `| <D-id> | <Targets> |`: the Targets that cite it plus every non-terminal
    Target they hold up, in Target order, joined with `, `. A D-id that is not
    `proposed` is not listed.
  - Last line: `**Open proposals:** <proposed ids, comma-space separated, once
    each>` or `none`. Ids listed under Decisions needed come first, each
    suffixed `(blocking)`; the rest follow in stream order.
- `matrix` (only when `envs:` is set): with no `@env` Targets the body is
  `_No per-environment Targets._`. Otherwise `| Target | <env1> | <env2> |`,
  `|---|---|---|` (one `---` per column), then one row per base name (the id
  minus `@<env>`, in Target order), each cell the derived stage of
  `<base>@<env>` or `not opened`. An `@env` that is not in `envs:` still
  gets a trailing column, in order of first appearance.
- `rules`: when the table would have no rows (no `topics:` and no live
  decisions) the body is `_No live decisions._`. Otherwise `| Topic | Live decisions |`, `|---|---|`, then one row per
  `topics:` entry in order (`none` when it has no live entry), listing its live
  entries comma-space separated in stream order: `D1`, `D1 (as amended by D2)`
  (live AMENDS entries only; several amenders as `(as amended by D2, D3)`),
  `D3 (proposed)`, and both together as `D4 (as amended by D9) (proposed)`. Then a final `| (untagged) |`
  row for live entries with no topic and a final `| (unknown topic) |` row for
  live entries whose topic is not in `topics:`; each is written only when it
  has entries. Superseded, rejected and retired entries never appear.

When unsure, run `--write` against a scratch copy and compare.

## Progress log

Each initiative may keep a progress log at `initiatives/logs/<slug>.md`:
append-only, one dated entry per update, each tagged with the Target id it
concerns: `## <YYYY-MM-DD> — <target-id>`, optionally followed by a trailing
note (the 3.0.0 migration writes `## 2026-11-17 — infra/db@staging (migrated by 3.0.0)`). It is live, not archived, work
state: it carries the narrative that no longer fits the one-line Target
status. It is not listed in `index.md` and carries no frontmatter contract.

## Stream-first capture

Record a cross-repo decision in the initiative `## Decision stream` at decision
time as `D<n> proposed <date>` with an `unconfirmed:` line. Plan, runbook, and project-memory entries are
projections that carry the stream id; the stream is the record. Check at every
plan-phase completion and during `/checkpoint`, never at handover.

`/start <ref>` first resolves the task, then read-only greps initiative files
for its exact full `- task: <ref>` line. No match is silent. On one match it
reads the initiative and reports the slug, Target id, `execution_mode`,
`depends_on`, and that Target's `initiative-status.sh` row, including its
`next`, `blocked_by` and whether dependencies are satisfied; an unsatisfied
dependency stops for user direction before planning. It reads
`## Decision stream` before the design gate, and any new cross-repo decision
settled during planning is appended as the next `D<n> proposed <date>` at
decision time. Multiple matches are an error: lint rule 15a forbids one task on
more than one Target. `/start` never hand-edits the initiative (regenerating
its fences with `initiative-render.sh` is allowed): the Target names the task
and the plan is derived by matching `task_ref`, so starting work requires no
Target update. `/plan-done` and the task-linking status flip regenerate the
fences when the plan's `task_ref` is an active initiative's Target.

## Create and close

Use `/new-initiative <kebab-case-slug>` to scaffold an active instance from
`initiatives/_template.md`, whose fences are pre-rendered for an initiative with
no Targets (the script refuses a file with none). Once the first Target is
added, run `initiative-render.sh <slug> --write` and again after later edits.
`/new-initiative` refuses an existing path. After creating it,
add a breadcrumb-only row to every affected project's `## Related Projects`
table; keep the status and decision stream in the initiative itself.

Opening and closing are explicit user actions. No `proposed` may remain at
close: resolve each with the user. Confirm needs an absorbing artifact;
`rejected` is only for never-adopted. An agreed decision no repo absorbed is
set to `retired <date>`, keeping its `unconfirmed:` line as the record of what
was never done. On close, fill `## Closure` with the date, final Target states,
and where follow-on work moved, then move the file to `initiatives/archive/`
and, if one exists, its progress log from `initiatives/logs/<slug>.md` to
`initiatives/archive/logs/<slug>.md`. Derived output may identify a candidate
for closure but never closes an initiative itself.

## Lint rules

`lint-memory.sh` checks initiatives with the same parser `initiative-status.sh`
uses, so the two cannot drift:

- ERROR: a `### ` heading under `## Targets` that is neither `### Closed` nor
  `<project>/<name>[@<env>]`; a duplicate id (heading or Closed row); a
  legacy actor field (the pre-3.0.0 format; see UPGRADING.md, 3.0.0) or a status that does not match the grammar (an
  old-format file; `initiative-status.sh` refuses it too and names
  `migrations/3.0.0-initiative-format.sh`); an interactive Target with no
  `status:`.
- WARN: `depends_on` naming no Target or Closed row; an `@env` not in `envs:`
  (or no `envs:` list); an open/blocked Target with no `task:`; a status over
  300 characters; `next:` with no ` — ` action; a `status: open` Target whose
  `depends_on` is unsatisfied (the status script decides: a `closed`
  dependency never satisfies; set `status: blocked`); stale or missing generated
  fences; decision-stream shape (malformed head, bad status, `proposed`
  without `unconfirmed:`, topic outside `topics:`, missing topic, missing
  forward pointer, dangling pointer, AMENDS/SUPERSEDES naming no id).

## Readiness derivation

Run:

```sh
bash scripts/initiative-status.sh <slug>
```

It reads local markdown and local checkout paths only: no network, provider,
or GitHub calls. The result is a hand-derivable markdown table with, per
Target: stage/status, evidence, dependency satisfaction, `next` and
`blocked_by` (both taken from the authored status line, `-` when absent). For
scripts, `initiative-status.sh --tsv <slug>` prints one tab-separated line per
Target and nothing else, with seven columns: `id`, `stage` (derived stage or
asserted state), `deps-satisfied` (`yes`/`no`), `next`, `blocked_by`,
`unsatisfied` (the unsatisfied `depends_on` edges with reasons, or `-`) and
`state` (the authored state token, `-` when none; a Closed row is `done`).
`initiative-render.sh` builds the Now section from it. It is read-only like
`--list-proposed`: no snapshot is read or written.

| Software ADW fact | Derived stage |
|---|---|
| terminal `status:` asserted (`done` or `closed`, any mode) | echoed as-is, no lookup |
| no `task:` | `not-started` |
| `task:` present but no plan's `task_ref` matches it, anywhere | `not-started` |
| `task:` matches exactly one live plan, `status: draft` | `plan` |
| `task:` matches exactly one live plan, `status: in_progress` | `implement` |
| `task:` matches exactly one live plan, `status: done` | `complete` |
| `task:` matches exactly one plan in `archive/plans/` (no live match) | `complete` |
| `task:` matches two or more **live** plans | `unknown`, every path named |
| no live match, two or more **archived** plans | `unknown`, every path named |
| project memory or `repo_path` checkout cannot resolve | `unknown` |

A live plan wins over an archived one carrying the same task: re-planned work
resolves to the plan in flight, not the one already filed away.

A plan's `task_ref: none` is never a match for any Target — it means that plan
was not born from a Target, and it stays invisible to this join by design.

Todo checkbox counts are evidence, not an independent status. Interactive
Targets echo their asserted `status:` (or `no status asserted`). A dependency
with `(stage: X)` is satisfied when its Target is complete, or has reached at
least X in its declared stages; a Target whose asserted state token is exactly `done` also satisfies a dependency — stage-qualified or not, since a frozen
Target has no derivable stage to compare. A state token of exactly `closed`
deliberately does *not* satisfy a dependency: an abandoned prerequisite must
not unblock its dependents. Unknown facts fail closed. A requested stage not
in the depended Target's declared list produces a warning.

## Staleness detection

`initiative-status.sh` also detects a software ADW Target that advanced without
a corresponding decision-stream entry. Each normal run compares recomputed
derived stages and the `## Decision stream` entry count (every line matching
`^- D[0-9A-Za-z]*`, including `proposed`) with
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
| *initiative:* `<slug>` | `<when this project's work touches a Target>`. Append `D<n> proposed <date>` to the stream at decision time; never hand-carry a cross-repo decision to handover; check readiness with `bash scripts/initiative-status.sh <slug>`. | `initiatives/<slug>.md` — decision stream + Targets (pointer only; no status duplicated here). |
```

## Deliberately deferred

Phase 1 does not build a transition guard, reusable Target templates, or
autonomous status progression. Those controls remain deferred until an
observed initiative run demonstrates the need.
