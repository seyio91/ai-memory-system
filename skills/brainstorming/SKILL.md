---
name: brainstorming
description: Use before starting a large, non-trivial feature task (a Tier-3 task in this system) that still has open design questions — new functionality, a new subsystem, a new integration, or a real architecture decision. Refines the idea through collaborative dialogue, settles on an approach, and produces an approved design that is folded directly into a plan file via /new-plan. Invoke this whenever a feature is big enough to warrant a plan AND its shape is not already obvious — including when a /start command begins a captured feature task. Do NOT use for research/explore/Q&A (Tier 1), quick one-off edits or fixes (Tier 2), or Tier-3 work whose design is already settled (mechanical refactors, renames, migrations with a known target). When in doubt on a feature-sized task, invoke it — a short design is cheap; an unexamined assumption is not.
metadata:
  tier: target-read-only
---

# Brainstorming Features Into Designs

Turn a rough feature idea into an approved design through collaborative dialogue, then hand the design to `/new-plan` so the existing orchestrator/executor pipeline can run it.

This is the **front half** of the Tier-3 pipeline. It sits *before* `/new-plan` and produces its inputs. It does not write code, scaffold anything, or create the plan file itself — its only output is an approved design that gets folded into the plan.

## When this fires — and when it doesn't

This skill is gated to one slice of work: **Tier-3 feature tasks with open design questions.** The tier classification that already runs on every request is the gate.

| Request | Tier | Brainstorm? |
|---------|------|-------------|
| "what does X do", "how should we approach Y" | 1 — research/Q&A | No — answer directly |
| one edit, a one-off command, a short fix | 2 — quick item | No — just do it |
| new feature / subsystem / integration with design choices to make | 3 — feature | **Yes** |
| multi-file refactor, rename, migration with a known shape | 3 — settled | No — go straight to `/new-plan` |

The distinction inside Tier 3 is **open design questions vs. settled shape.** If you already know exactly what files change and how, there is nothing to brainstorm — scaffold the plan. If there are real choices (data model, interface boundaries, where a responsibility lives, how pieces talk), brainstorm first.

If you started executing and realize the design is not actually settled, stop and invoke this.

## Two ways this skill is reached

The process below is identical regardless of how it starts. Only the **seed** differs.

1. **Auto, at the top of a request.** The tier classification routes a feature-sized request here before any plan exists. The seed is the user's request.
2. **From `/start`, on a captured task.** When the task-provider layer exists, `/start` on a captured task that is a feature with open design delegates here. The seed is the task's pulled **summary** — treat it exactly as you would an initial user request, then run the same dialogue. The summary may name an investigation (`projects/<project>/investigations/<slug>.md`), which `/start` then hands over as part of the seed. (A captured task that is quick or already settled is not sent here — `/start` takes it straight to `/new-plan`.)

In both cases the terminal handoff is the same: `/new-plan`, with the approved design folded into the plan file.

## Process

Work through these in order. Each is a step you can track in `todo.md` if the task already has one.

1. **Explore context.** Read the active project's `memory.md` (it's already injected), the relevant files, and recent commits. If you were reached from `/start`, the captured task's summary is your starting intent — read it first. Don't ask the user what the code or the summary already tells you.
2. **Scope check.** If the request is actually several independent features ("build chat + billing + analytics"), say so before refining details. Help decompose into separate features; each gets its own brainstorm → plan cycle. Don't spend questions polishing something that needs splitting first.
3. **Clarify intent.** Ask about purpose, constraints, and what "done" looks like. One question at a time when the answer genuinely shapes the design; batch a few when the task is well-specified and you're just confirming. Prefer multiple-choice when it's faster for the user. Stop asking once you can state the goal and the success criteria back accurately.
4. **Propose 2-3 approaches.** With trade-offs and a recommendation, leading with the one you'd pick and why. This is where alternatives get surfaced and rejected on the record, not silently.
5. **Present the design in sections.** Scale each section to its complexity — a sentence or two when straightforward, a paragraph when nuanced. Cover the pieces that matter: unit boundaries and interfaces, data flow, error handling, testing. Get a quick approval after each section; go back and revise when something doesn't land.

Design for clear boundaries: each unit should have one job, a well-defined interface, and be understandable and testable on its own. A file that wants to grow large is usually doing too much.

## Output: fold the design into the plan

Once the design is approved, the terminal step is **`/new-plan <name>`**, then write the approved design into the scaffolded sections of `projects/<active>/plans/<name>.md`:

- **`## Goal`** ← the clarified purpose (one or two sentences). When reached from `/start`, this clarified Goal is also what `/start` pushes back to the task as the refined summary — so keep it clean and self-contained.
- **`## Success criteria`** ← the checkable conditions derived *with* the user during clarification. This is the Task Contract — brainstorming is what makes these collaboratively-derived rather than orchestrator-guessed.
- **`## Design`** ← the chosen approach, plus a one-line note on each alternative considered and why it lost. A lightweight decision record, so the "why" survives.
- **`## Risks / open questions`** ← anything surfaced but deferred during the design pass.

Leave **`## Phases`** for `/new-plan`'s normal job (decomposition into phases and `todo.md` items) — that's the writing-plans step, downstream of here.

Do **not** create a spec document in the **target repo**, and do not commit anything there. The brainstorm's own output is the **plan file** — `## Goal`, `## Success criteria`, `## Design`, `## Risks` — never a sibling design doc. The plan lives in the memory tree, like every other plan.

An **investigation** (`projects/<project>/investigations/<slug>.md`) is a different artifact: findings written while exploring, *before* the task existed. It is this skill's **input** — `/start` hands it over as the seed — never its output. It exists only when an investigation was actually done and its findings exceed the task summary's 500-char cap. This skill never writes one.

## Principles

- **YAGNI ruthlessly** — cut features that aren't needed from every design.
- **Explore alternatives** — always 2-3 approaches before settling.
- **Incremental validation** — present in sections, approve as you go.
- **Be flexible** — go back and re-clarify when something stops making sense.
- **Don't over-ask** — the goal is a good-enough design fast, not an interrogation. A short design for a clear feature is a success, not a shortcut.

## What this skill deliberately does not do

- It does not fire on every task — only Tier-3 features with open design questions.
- It does not run for the executor. Brainstorming is an orchestrator-role activity; whichever harness runs the main session owns it. Executors never brainstorm.
- It does not write code or invoke any implementation skill. Its only handoff is `/new-plan`.
- It does not own the task-provider bookkeeping. When reached from `/start`, linking the `task_ref`, pushing the summary, and flipping status are `/start`'s job — this skill only produces the design.
- It does not produce a spec file — not in the target repo, and not as a sibling of the plan. The design lives in the plan. (An `investigations/<slug>.md` may exist as this skill's *input*; the skill never writes one.)

<!-- partial:self-rating START (managed by scripts/apply-partial.sh — edit scripts/partials/self-rating.md) -->
## Self-rating (first-party)

This skill participates in the self-rating loop. The rating is a signal about
**this skill's own friction** — where its instructions were unclear, slow, or
made you guess — not about the correctness of the work product (that is the
Validator's job).

**Do not rate automatically.** Append a rating **only when the user asks** for
one (e.g. "rate this run", "how did the skill do") or when you hit real friction
worth recording. Silence is the default; an empty log is a healthy log.

When you do rate, append one dated entry to this skill's own folder —
`skills/<this-skill>/self-rating.md` (the always-writable own-folder zone; never
the target repo or the system memory tree). Use this shape:

```
## YYYY-MM-DD — <one-line context>
- score: <1-5>   (1 = fought the skill, 5 = frictionless)
- friction: <what was unclear / slow / had to be guessed, or "none">
- improve: <the smallest concrete change that would raise the score, or "none">
```

Aggregate across skills with `scripts/skill-ratings.sh`.
<!-- partial:self-rating END -->
