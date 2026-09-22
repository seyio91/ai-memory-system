---
plan: widen-validator-aperture
status: in_progress
created: 2026-09-22
owner: claude (orchestrator)
task_provider: notion
task_ref: 3e1f6850-c619-8185-a7b4-c934dbb2466d
---

# Widen the validator's aperture

## Goal

Stop PR bots finding bug-grade defects after clean validator rounds: the validator does a cold,
production-path, run-it review with a bounded impact radius, and the orchestrator scopes rounds by
risk, runs one decorrelated full-branch pass per phase, and caps rounds at 5 before escalating.

Design input: investigation `validator-aperture` (incl. its 2026-09-22 cost model).

## Success criteria

1. `agents/validator.md` declares inputs `scope: fix-round|final`, `risk: low|medium|high`,
   optional `hypotheses` and optional indirect-consumer list, and defines what each value changes.
2. `agents/validator.md` requires, in order: a cold pass written before any hypothesis is
   checked; a production-path trace (producer on the real path for every new field/map/option);
   running the deliverable on realistic input with output pasted; a one-hop impact radius
   (callers, callees/merged seams, contract consumers, production producers) over the fix diff
   (`fix-round`) or `origin/main...HEAD` (`final`).
3. `agents/validator.md` lists the five new defect classes (argv option injection, unbounded
   counts from untrusted input, ordering lost on split/regroup, parse ambiguity, truncation/partial
   read as success) alongside the existing ten.
4. The report shape has separate `Cold findings` and `Hypotheses` sections and a
   `decorrelated: yes|no` line; `risk: low` runs Part A only.
5. `scripts/executor.sh --role validate --which` writes a note to stderr iff the validate and task
   roles resolve to the same harness family; stdout and exit code are unchanged in both cases;
   `scripts/tests/test_executor.sh` covers same-family, different-family, and the
   `claude-subagent` alias.
6. Orchestrator doctrine — `templates/orchestrator.template.md` and local `orchestrator.md`,
   Validator block byte-identical (`diff` empty) — states: fix rounds use `scope: fix-round`; one
   `scope: final` pass per phase before PR-READY on a different model family, else labelled
   `decorrelated: no`; the three risk tiers and which steps each runs; a 5-round cap (PR-bot rounds
   that triggered fixes count) with the escalation payload (bug-grade findings per round, recurring
   classes, options: continue with named scope / narrow / accept documented risk / redesign).
7. The defect-class bullets appear only in `agents/validator.md`; the doctrine points at it.
8. `docs/workflow.md` reflects 1–7; a `changelog.d/validator-aperture.feature.md` fragment exists.
9. Full suite green (file count reconciled against `tests: N passed`); lint WARN set unchanged
   apart from intended moves.
10. Live exercise: one validator run with `scope: final` against a real commit range in this repo
    produces a report in the new shape (Cold findings, Hypotheses, `decorrelated:` line).

## Design

Split by who knows what:
- **Validator (`agents/validator.md`)** owns per-invocation behaviour — the cold pass, the
  production-path trace, running it, the impact radius, the defect classes, the report shape. Mode
  arrives as brief inputs (`scope`, `risk`); it cannot see round counts or the executor's model.
- **Orchestrator doctrine** owns round-level behaviour — scope per round, the final decorrelated
  pass, risk tier choice, the round cap and escalation, the cross-model rule.
- **`executor.sh`** gains only a non-blocking stderr note when validate and task resolve to the
  same harness family (`subagent` ≡ `claude-subagent`; `cli:<x>` ≡ `cli:<x>`).

Cold-first ordering runs in **one invocation**: hypotheses sit in the brief behind an explicit
"only after Cold findings are written" gate. Never delivered by resuming the agent.

Defect classes are single-sourced in `agents/validator.md` (already the single prompt for both
planes since #107); the doctrine keeps only the PR-gate rule and a pointer.

Rejected:
- Two agent definitions (`validator` / `validator-final`) — two prompts drift, doubles CLI prepend wiring.
- Cold cumulative pass every round — full-branch cost on every fix round.
- All rules in `validator.md` — it cannot act on round counts or executor model.
- Keeping duplicate class lists (with or without a drift test) — single source is cheaper.
- Auto-switching the validator model — implicit, quota-dependent, surprising.
- Two invocations for cold vs hypothesis passes — the ordering gate buys most of it for one.

## Decisions (locked)

- Brief inputs `scope` and `risk`; tier chosen by orchestrator judgement until a formal plan risk tag exists.
- Round cap 5, PR-bot rounds that triggered fixes count.
- Same-family warning is advisory only — never blocks, never changes stdout.

## Phases

### Phase 1 — validator prompt
Edit `agents/validator.md`: inputs, cold-pass-first ordering, production-path trace, run-it,
one-hop impact radius per scope, five new defect classes, `risk: low` short-circuit, report shape.
Keep the read-only role and deny-list intact.
**Verify:** criteria 1–4 checkable by reading the file (each named element present, cold pass
ordered before hypotheses); `bash scripts/tests/test_executor.sh` still green (the CLI prepend
reads this file).

### Phase 2 — same-family warning
`scripts/executor.sh`: on `--role validate --which`, resolve the task role too; if both harness
families match, print one stderr line naming the family and the fix
(`AI_MEMORY_EXECUTOR_VALIDATE=<other>` or label the final pass `decorrelated: no`). Tests in
`scripts/tests/test_executor.sh`. bash 3.2.
**Verify:** criterion 5 — new cases pass under `/bin/bash`; stdout byte-identical to before in
both cases; mutation (delete the comparison) fails the same-family case.

### Phase 3 — doctrine and docs
**Depends:** P1
Validator block in `templates/orchestrator.template.md` and local `orchestrator.md` (byte-identical),
`docs/workflow.md`, `changelog.d/validator-aperture.feature.md`. Remove the defect-class bullets
from the doctrine, point at `agents/validator.md`.
**Verify:** criteria 6–8 — `diff` of the two Validator blocks empty; `grep` finds the defect-class
bullets only in `agents/validator.md`; docs name `scope`, `risk`, the cap, the final pass.

### Pre-PR checkpoint
Criteria 9–10: full suite, lint set diff, live `scope: final` validator run; then branch + PR.

## Risks / open questions

- Codex read-only sandbox denies Go its temp dir, so a codex validator cannot run tests
  (proposal 2 degrades to static traces there). Needs `GOTMPDIR`/`GOCACHE` in a writable path —
  separate change to the codex exec face.
- Part A on a cheaper model than Part B — needs a per-part model mechanism; deferred.
- Risk tier is orchestrator judgement until task `3dbf6850-c619-81eb-afbf-d64578a651d6` adds a
  per-phase risk tag.
- Tier thresholds are unmeasured; task `3dbf6850-c619-817a-a5dd-c77db8f66182` (per-delegation
  metrics) would supply evidence.
- Find-references misses dynamic coupling (interface dispatch, reflection, string-matched errors,
  cross-process files); mitigated only by the brief's indirect-consumer list.
- The ordering gate is prose inside one prompt — hypotheses are visible from the start, so some
  anchoring leaks. Two invocations remain the fallback if trials show it.
