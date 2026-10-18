---
kind: initiative
slug: <slug>
status: active
created: YYYY-MM-DD
---

# <Initiative title>

## Objective

<The shared objective — what several projects are building together and why.
One paragraph. Link the originating decision (ADR, discussion) if one exists.>

## Normative contract

<Pointer(s) to the authoritative artifact(s) in-repo, never a copy:
`<project>:<path>`. The initiative holds the *why* and supersession order;
the repository holds the *what*.>

## Decision stream

<Append-only; supersede, never rewrite. Entry shape, one line per decision:
`- D<n> <proposed|confirmed|rejected|superseded|retired> <YYYY-MM-DD> — <decision>`.
Status is never part of the id; a `D<n>-proposed` reference means `D<n>`.
The date is bare (no brackets or parentheses) and is the date of the last
status change. Continuation lines, two-space indented: `evidence:`,
`unconfirmed:`, `binds:`, and supersession keywords (`SUPERSEDES <id>`).
`rejected` = never bound anything; `retired` = bound, then withdrawn.
No blank lines inside an entry: a blank line ends its continuation lines.

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
      evidence: <pointer to the absorbing artifact>
      binds: <what the decision constrains>
    - D2 proposed YYYY-MM-DD — <decision>
      unconfirmed: <what confirmation awaits>

## Targets

<One section per Target. Target id = `<project>/<slug>`, unique within this
initiative. `task:` names the Target's work as a full-UUID task-provider
pointer; the plan is derived by matching that ref against plan frontmatter
`task_ref`, never authored as a second pointer. `stages:` only for
`execution_mode: software_adw` — interactive Targets carry status assertions,
not stages. Status for ADW Targets is derived on demand, never authored here.
Keep every field value on ONE line — lint and derivation read the first line
only, so a wrapped value is silently truncated. The example below is indented
so lint and derivation ignore it; real Target sections start at column 0. When
authored, status grammar is `status: open|blocked|done|closed — <free prose>`.>

    ### <project>/<target-slug>
    - execution_mode: interactive | software_adw | runbook | automated
    - task: <full task UUID, optional>
    - stages: <ordered list, software_adw only>
    - depends_on: <target-id> (stage: <stage>) | <target-id> | none
    - next_actor: <orchestrator (project session) | human | external>
    - status: open|blocked|done|closed — <free prose>

## Closure

<Filled at close, by explicit user declaration only. Date, final state of each
Target, and where continuing work was re-homed. Move this file to
`initiatives/archive/` on close.>
