---
kind: initiative
slug: <slug>
status: active
created: YYYY-MM-DD
envs: [staging, prod]
topics: [topic-a, topic-b]
---

# <Initiative title>

## Objective

<The shared objective — what several projects are building together and why.
One paragraph. Link the originating decision (ADR, discussion) if one exists.>

## Normative contract

<Pointer(s) to the authoritative artifact(s) in-repo, never a copy:
`<project>:<path>`. The initiative holds the *why* and supersession order;
the repository holds the *what*.>

## Now
<!-- BEGIN AUTOGEN initiative-render:now -->
**Ready:** none

**Blocked:** none

**Open proposals:** none
<!-- END AUTOGEN initiative-render:now -->

## Environment matrix
<!-- BEGIN AUTOGEN initiative-render:matrix -->
_No per-environment Targets._
<!-- END AUTOGEN initiative-render:matrix -->

## Targets

<One `### <project>/<name>[@<env>]` section per Target, unique within this
initiative; use `@<env>` (an env listed in frontmatter `envs:`) to split one
piece of work across environments. Keep every field on ONE line — lint and
derivation read the first line only. `task:` is a full-UUID task-provider
pointer; the plan is derived by matching it against plan frontmatter
`task_ref`, never authored as a second pointer. `scope:` is the one-line
meaning of the Target. `stages:` only for `execution_mode: software_adw`.
`status:` is required for interactive Targets and optional for software_adw
(stage derived). Grammar:
`status: <open|blocked|done|closed> · next: <session — action> · blocked_by: <…|none>`
(`done`/`closed` stand alone). Finished (`done`) Targets move to the
`### Closed` table below, the only non-Target heading allowed; an abandoned
Target keeps its heading with `status: closed` and never satisfies a dependency. Regenerate the `## Now` /
`## Environment matrix` / `## Current rules` fences with
`initiative-render.sh <slug> --write`, or edit them by hand following the
Two-Path rules in `docs/initiatives.md`. The example is indented so lint ignores
it; real Target sections start at column 0.>

    ### <project>/<target-slug>@<env>
    - execution_mode: interactive | software_adw | runbook | automated
    - task: <full task UUID>
    - scope: <one line: what this Target delivers>
    - stages: <ordered list, software_adw only>
    - depends_on: <target-id> (stage: <stage>) | <target-id> | none
    - status: open · next: <session> — <action> · blocked_by: none

Finished Targets (terminal `done`, never abandoned `closed` ones) go in a `### Closed` table at the end of this
section. The example is fenced so lint ignores it; a real table is not fenced.

```markdown
### Closed

| id | closed | jira | outcome |
|---|---|---|---|
| <project>/<target-slug> | YYYY-MM-DD | <JIRA-123 or -> | <one-line outcome> |
```

## Current rules
<!-- BEGIN AUTOGEN initiative-render:rules -->
| Topic | Live decisions |
|---|---|
| topic-a | none |
| topic-b | none |
<!-- END AUTOGEN initiative-render:rules -->

## Decision stream

<Append-only; supersede, never rewrite. Entry shape, one line per decision:
`- D<n> <proposed|confirmed|rejected|superseded|retired> <YYYY-MM-DD> — <decision>`.
Status is never part of the id; a `D<n>-proposed` reference means `D<n>`. Ids are unique, except that `superseded` copies may repeat an id.
The date is bare (no brackets or parentheses) and is the date of the last
status change. Continuation lines, two-space indented: `topic:` (one of
frontmatter `topics:`), `evidence:`, `unconfirmed:`, `binds:`, and the
keywords `SUPERSEDES <ids>` / `AMENDS <ids>`.
`rejected` = never bound anything; `retired` = bound, then withdrawn.
No blank lines inside an entry: a blank line ends its continuation lines.

To change a decision, append a NEW entry. A replacement says `SUPERSEDES <id>`;
a partial change says `AMENDS <id>`. The older head then gets a forward pointer
after its date, before the dash: `- D1 superseded 2026-11-02 → D2 — text`
(a list is `→ D2, D3`). Never rewrite an older entry's text; amendments made in
place before this rule stay as written.

Only the user confirms. A confirm carries the date plus an `evidence:` line
naming the absorbing artifact; a `proposed` entry carries an `unconfirmed:` line
saying what confirmation awaits. A proposal from one project awaiting another's
confirmation stays `proposed`. Plain ids (no letter) at or below frontmatter
`legacy_through: D<n>` (stamped by migration, absent on a new initiative)
predate these rules and are exempt from the date, `evidence:` and `unconfirmed:`
checks; lettered ids (`D6b`) are never exempt. At initiative close no `proposed`
may remain: an agreed decision no repo absorbed becomes `retired <date>`.

The example is indented so lint ignores it; real entries start at column 0.>

    - D1 confirmed YYYY-MM-DD — <decision>
      topic: topic-a
      evidence: <pointer to the absorbing artifact>
      binds: <what the decision constrains>
    - D2 proposed YYYY-MM-DD — <decision>
      topic: topic-b
      unconfirmed: <what confirmation awaits>

## Closure

<Filled at close, by explicit user declaration only. Date, final state of each
Target, and where continuing work was re-homed. Move this file to
`initiatives/archive/` and its progress log (if any) to
`initiatives/archive/logs/` on close.>
