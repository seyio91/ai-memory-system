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

<Append-only; supersede, never rewrite. Each entry: id, one-line decision,
evidence, and `SUPERSEDES <id>` where applicable. A proposed decision from one
project awaiting another's confirmation is `<id>-proposed` until confirmed.>

- D1: <decision> — evidence: <pointer>.

## Targets

<One section per Target. Target id = `<project>/<slug>`, unique within this
initiative. `task:` is an optional full-UUID task-provider pointer. `stages:`
only for `execution_mode: software_adw` — interactive Targets carry status
assertions, not stages. Status for ADW Targets is derived on demand, never
authored here. Keep every field value on ONE line — lint and derivation read
the first line only, so a wrapped value is silently truncated. The example
below is indented so lint and derivation ignore it; real Target sections start
at column 0.>

    ### <project>/<target-slug>
    - execution_mode: interactive | software_adw | runbook | automated
    - task: <full task UUID, optional>
    - plan: projects/<project>/plans/<file>.md   (optional; <project> must match the id prefix)
    - stages: <ordered list, software_adw only>
    - depends_on: <target-id> (stage: <stage>) | <target-id> | none
    - next_actor: <orchestrator (project session) | human | external>
    - status: <interactive only: open | blocked | done (asserted by <who>, <date>)>

## Closure

<Filled at close, by explicit user declaration only. Date, final state of each
Target, and where continuing work was re-homed. Move this file to
`initiatives/archive/` on close.>
