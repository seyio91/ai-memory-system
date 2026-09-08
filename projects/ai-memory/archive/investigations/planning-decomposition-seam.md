---
investigation: planning-decomposition-seam
created: 2026-09-08
status: complete
task_ref: close-the-plan-decomposition-seam-in-the-tier-3-pipeline
summary: Comparison of two external planning skills against this system's Tier-3 pipeline; identifies the undefined decomposition seam between `/new-plan`'s `## Phases` and executor delegation
---

# Investigation — the plan-decomposition seam

## Trigger

Reviewing two external skills for fit against this system:

- `planning-and-task-breakdown` — https://github.com/addyosmani/agent-skills/blob/main/skills/planning-and-task-breakdown/SKILL.md
- `to-tickets` — https://github.com/mattpocock/skills/blob/main/skills/engineering/to-tickets/SKILL.md

## What the two skills are

**`planning-and-task-breakdown`** — a full decomposition doctrine: dependency graph → vertical
slices → per-task template (acceptance criteria + verification + files touched + estimated
scope) → sizing table (XS–XL, "L or bigger, break it down further") → checkpoints every 2–3
tasks → parallelization triage (safe / must-be-sequential / needs-coordination). Also carries a
"never overwrite an incomplete plan" rule that distinguishes *same work being replanned* (edit
in place) from *different work* (stop and ask). Output: `tasks/plan.md` + `tasks/todo.md` in the
target repo, or mapped onto an external tracker.

**`to-tickets`** — thinner, and `disable-model-invocation: true` (user-invoked only, so it is
slash-command-shaped, not skill-shaped). Tracer-bullet vertical slices, **explicit blocking
edges**, a quiz-the-user gate before publishing, and expand–contract sequencing for wide
mechanical refactors. Output: `01`–`NN` numbered markdown files in dependency order, or native
tracker issues labeled `ready-for-agent`.

## Overlap against the existing stack

| Their concern | Already covered by | Verdict |
|---|---|---|
| Read-only plan mode, no code while planning | `orchestrator.md` tier gate + `brainstorming` | redundant |
| Decompose if it's several features | `brainstorming` step 2; `superpowers:writing-plans` Scope Check | redundant |
| Quiz / approve before publishing | `brainstorming` sectioned approval + `/new-plan` step 4 | redundant |
| Don't overwrite an incomplete plan | `/new-plan` step 2 | covered, blunter — ours aborts on path *existence*; theirs distinguishes replan-in-place from stop-and-ask |
| Per-task template (files, interfaces, steps) | `superpowers:writing-plans` (stronger — Consumes/Produces interface block, Task Right-Sizing) | redundant |
| Per-task verification during execution | `superpowers:subagent-driven-development` (reviewer subagent per task) | redundant |
| Parallelization triage | `superpowers:dispatching-parallel-agents` + `executor.sh` roles | mostly covered |
| Publish tickets to a tracker | `/task` + `taskctl` + Notion provider | **conflicts** — see Rejected |

## The gap they expose

The pipeline is `tier → brainstorm → /new-plan → todo.md → executor → validator`.

`/new-plan` explicitly defers decomposition: *"Leave `## Phases` for `/new-plan`'s normal job
(decomposition into phases and `todo.md` items)."* But **neither `/new-plan` nor
`orchestrator.md` states how to decompose.** There is no sizing bar, no dependency declaration,
no per-phase verification, and no checkpoint-placement rule.

Consequence: the Task Contract puts success criteria at **plan** level only, so a six-phase plan
gets one Validator pass at the very end — a phase-2 defect is not caught until phase 6 is built
on top of it. This is the same shape as the recorded lesson that a green suite is where
validation *starts*: terminal-only validation is structurally late.

## Findings worth extracting

1. **Phase-level success criteria.** A Task Contract extension, not a new skill: each `## Phases`
   entry carries its own checkable criteria so the Validator can be invoked per phase rather than
   once terminally. Source: `planning-and-task-breakdown` step 4's acceptance-criteria /
   verification split.

2. **A decomposition rule inside `/new-plan`.** Sizing bar (what constitutes one executor
   delegation), dependency ordering, and checkpoint placement at the human/CI gates
   `orchestrator.md` already says to pause at but never locates. Source: that skill's steps 2/3/5
   plus its sizing table.

3. **Explicit dependency edges on `todo.md` items.** From `to-tickets`. Today `todo.md` is a flat
   checkbox list under `## Active`, and `/start` appends `### <title> → [plan](plans/<slug>.md)`
   plus unchecked phase boxes — order is *implied by sequence*, never declared. `orchestrator.md`
   says to "walk them in documented order" for plan sets, which is prose, not data. An
   annotation convention makes parallel-safe phases legible to an orchestrator resuming after
   compaction.

4. **Expand–contract sequencing** for wide mechanical changes (add new form alongside old →
   migrate call sites in batches → delete old, each phase green independently). Correct shape for
   Terraform variable renames and Helm values migrations; not recorded in `domain/terraform.md`
   or `domain/helm.md`.

## Rejected, with reasons

- **`tasks/plan.md` + `tasks/todo.md` in the target repo.** Direct architectural conflict: plans
  live in `projects/<active>/plans/`, and `brainstorming` states outright *"Do not create a spec
  document in the target repo, and do not commit anything there."* Adopting this forks the plan
  store and puts plan artifacts inside client repos.
- **One-file-per-ticket `01`–`NN` output.** A fourth artifact type (plans, todos, investigations,
  tasks already exist) with no lifecycle — no `/plan-archive` equivalent, no frontmatter, nothing
  the linter or catalog sees.
- **Publishing N tickets into the task provider.** Fights two settled decisions: task `summary` is
  a capped thin *intent* record, not a design; and the provider is deliberately push-dominant.
  Ticket bodies carrying acceptance criteria do not fit, and Notion page bodies are explicitly
  outside the provider contract.
- **`superpowers:writing-plans`' bite-sized TDD granularity** ("write failing test → run it →
  implement → run → commit") as the decomposition unit. Wrong loop for Terraform/GitOps work,
  where verification is `fmt` / `validate` / plan-diff and the apply belongs to ArgoCD.

## Incidental findings

- **Two `brainstorming` skills are live.** This system's (`skills/brainstorming/`) and
  `superpowers:brainstorming`. `using-superpowers` instructs *"Let's build X →
  superpowers:brainstorming first"*; `orchestrator.md` says invoke *"the brainstorming skill"*.
  Same name, different namespaces, different terminal handoffs — ours ends at `/new-plan`, theirs
  at `superpowers:writing-plans` → `docs/superpowers/plans/`. Selection is currently
  underdetermined; only the plan-path memory rule keeps the artifact location correct.
- **`superpowers:writing-plans` is an unreferenced parallel answer** to finding 2. It is
  installed, it is stronger than the external skill on task structure, and nothing in this tree
  points at it — `/new-plan` does not mention it, `orchestrator.md` does not gate it.
- ~~**The 500-char `summary` cap may not be enforced by the local provider.**~~ **Disproven
  2026-09-08.** `taskctl capture` rejected a 661-char and then a 517-char summary with an explicit
  error naming the cap, so the local provider enforces it correctly. The oversized
  `author-dd-k8s-skill-…` backlog record therefore did *not* come through `capture` — it was
  written to the flat store directly, or predates the gate. No provider bug; nothing to follow up
  on the cap itself.

## Conclusion

Install neither skill. Extract findings 1–3 into `/new-plan` and the Task Contract in
`identity.md`, resolve the `brainstorming` namespace collision, and record finding 4 as a domain
entry.
