## Plan scaffold

The plan body, written once here and carried by `/new-plan` and `/start`. Fill the placeholders; the angle-bracket prose is guidance, not content. `/new-plan` writes `status: draft`, `/start` writes `status: in_progress`. Lint rule 20 reads this shape for plans created on or after 2026-11-08 — see `docs/file-formats.md` → Plan body.

```markdown
---
plan: <slug>
status: draft
created: YYYY-MM-DD
owner: claude (orchestrator)
# task_provider / task_ref: written by the Task linking step (Step 5 in /new-plan, Step 4 in /start).
# Never leave task_ref absent — a linked plan carries the full ref, a deliberately
# plan-only one carries `task_ref: none`. An absent field is what lint rule 12 flags.
---

# Plan — <human-readable title>

## Goal
<one paragraph: what problem this plan solves>

**Before:** <the observable state today — what is broken or missing>
**After:** <the observable state when the plan is done; the final validator pass reads this line>

## Non-goals
- <what this plan deliberately does not do>

## Success criteria
<the checkable conditions that define "done" for the WHOLE plan — each one a Validator could verify by reading output, running a command, or inspecting state. Required for plan-tier work (see doctrine/orchestrator.md → Task Contract). If the user did not state criteria, draft best-effort ones from session context; never leave this blank. One line per criterion, `R<n>` ids in order, each tagged. Per-phase checks go on each phase's `**Verify:**` line, which cites the R-ids it proves.>
- R1 [acceptance] <a condition proven by running a command or inspecting state>
- R2 [parity] <behaviour that must not change> — vs `<git-ref>` <tolerance, e.g. modulo `updated:`>
- R3 [parity] <output that must stay identical> — baseline `plans/<slug>.baseline/<path>` <tolerance>

<`[parity]` criteria name a re-runnable reference: ``vs `<git-ref>` `` (re-run the check at that ref and compare) or ``baseline `plans/<slug>.baseline/<path>` `` (a snapshot kept on disk beside the plan; it requires a `### Phase N — Baseline` that captures it). Delete the parity lines when nothing must stay unchanged.>

## Design
<for feature-tier plans this is populated by the `design-brainstorm` skill: the chosen approach (unit boundaries/interfaces, data flow, error handling) plus a one-line note per rejected alternative and why it lost — a lightweight decision record. For settled-shape plans (mechanical refactors, renames, migrations) that skipped brainstorming, a one-line statement of the known approach suffices.>
- <chosen approach>
- <alternative considered → why rejected>

**Builds on:** <existing code, commands, issues or plans this reuses — references only, never a dependency declaration>

## Security
<required when any phase is `Risk: high`: the threat the change introduces or exposes and how the plan contains it. Otherwise delete this section.>

## Decisions (locked)
- <bullet>

## Phases
### Phase 1 — <name>
- <step>

**Files touched:** `<repo-relative/path>`, `<dir/glob/*>`, `<path/the/phase/creates>` (new)
**Risk:** low | medium | high
**Depends:** none | Phase N[, Phase N…]
**Verify:** R1[, R2…] — <the checkable condition for THIS phase alone: readable output, a runnable command, or inspectable state; a phase that introduces a cache, lock, pool, background worker, deduplicated or in-flight work, or external process must also state concurrency, cancellation, timeout and failure-caching behaviour (see docs/workflow.md → Task Contract → "Shared state needs behaviour criteria").>

## Risks / open questions
- <bullet>
```

Field rules, one field per line: `Files touched` is comma-separated backticked paths or globs, repo-relative, with a file the phase creates suffixed ` (new)` after its closing backtick. `Depends` takes phase numbers only, never names — mirror it onto the `todo.md` checkbox as `(needs: Pn)`. `Verify` is a single line whose R-ids come before the em dash. Only `### Phase N — ` headings are phases; a `### Checkpoint` is not.
