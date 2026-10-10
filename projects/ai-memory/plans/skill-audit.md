---
plan: skill-audit
status: in_progress
created: 2026-10-10
owner: claude (orchestrator)
task_provider: local
task_ref: add-audit-skill-command-delegating-to-hub-skill-audit
---

# Plan — In-engine `skill-audit` skill

## Goal

Ship a generic `skills/skill-audit` skill in this engine, invoked as `/skill-audit <path>`. It audits any skill or folder of skills against 13 skill-writing rules from Anthropic's guides, using a bundled Python lint script for the mechanical checks plus judgement for the rest. It reports first and applies only the fixes you approve by number.

## Success criteria

- `skills/skill-audit/` contains `SKILL.md`, `references/rules.md`, `scripts/lint_skill.py` and `evals/` with ≥3 test prompts. No file in it contains CCV-specific rules, names or paths (`grep -ri ccv` is empty).
- `python3 skills/skill-audit/scripts/lint_skill.py <path>` works on one skill folder and on a folder of skills. It uses only the stdlib on Python ≥3.8 and outputs JSON per skill: `rule`, `status`, `file`, `line`, `message`. Each message names the problem and what was found.
- The script detects:
  - Rule 1: body over 500 lines, a file reachable only through another file, a linked file that is missing.
  - Rule 2: a file over 100 lines with no contents list.
  - Rule 5: a first- or second-person description.
  - Rule 9: backslash paths, machine-specific absolute paths.
  - Rule 10: never/always/must lines, listed as hook candidates.
  - Rule 11: `evals/` with <3 entries (counts `evals/evals.json` entries, else files).
  - Rule 13: reasoning-echo phrasing.
  
  A unittest with good and bad fixture skills covers each detection and runs in `run-tests.sh`'s python stage. A mutation that disables any one detection fails the unittest.
- `SKILL.md` stays under 500 lines and opens with the most important rules. Its workflow is a copyable checklist with go-back lines: script, then judgement, then report, then wait, then apply only approved numbers, then re-check until pass, then list changes per file. It links `references/rules.md` one level deep. Its description is third person and says both what the skill does and when to use it. It names its dependency with an install line.
- `references/rules.md` has a contents list. For each of the 13 rules it gives the check, the fix and an Anthropic source URL. The wording is paraphrased, with no copied third-party guide text.
- Rules 3, 4, 6, 7, 8 and 12 are judgement checks. Rule 4 and rule 11's baseline run come out as "test this" items, never as fails.
- The skill passes its own audit: the script reports no fails on `skills/skill-audit`.
- `validate-skills.sh` stays clean. `bash scripts/run-tests.sh` passes in full, including the self-rating drift gate after the carrier is added. A `changelog.d/` feature fragment exists. It ships via a `git-cli ship` PR.
- One live `/skill-audit` run on `skills/design-brainstorm` produces the report in the specified shape and edits nothing before approval.

## Design

**Chosen:** a self-contained skill in `skills/skill-audit/`:
- `SKILL.md` holds the workflow and a one-line-per-rule checklist.
- `references/rules.md` holds the per-rule check, fix and source.
- `scripts/lint_skill.py` (Python 3 stdlib, JSON output) handles the mechanical checks.
- `evals/` holds the test prompts.

The model handles the judgement rules and writes the report: a summary table (skill, fails, worst problem), then per skill and per rule pass/fail/n.a. with file:line evidence, then one numbered fix list ranked by impact. It then waits, applies only the fixes you approve, re-checks until they pass, and lists the changes per file. The skill works on any skill folder, inside or outside this system, and carries no CCV content. `validate-skills.sh` stays the engine's minimal CI gate, and the audit runs on demand only.

Rejected alternatives:
- Adopting `robonuggets/skill-creator-plus` as a remote skill: it would live in `.skill-cache/`, not editable here; you chose an engine-owned skill.
- Extending `validate-skills.sh` with the checks: the skill could no longer stand alone outside the engine (rule 9).
- Keeping both a skill-local and an engine lint: duplicated checks.
- Report-only: you want the approve-by-number fix loop.
- All rules in `SKILL.md`: a heavier always-loaded body, and the skill wouldn't practise rules 1 and 2 itself.
- Accepting only `evals/evals.json` for rule 11: too tied to one format.
- A CI gate in `run-tests.sh`: it would turn advisory rules into build failures.

## Decisions (locked)

- Build our own skill in `skills/skill-audit`, tracked and shipped with the engine. No CCV-specific content.
- The lint script lives inside the skill: Python 3 stdlib, JSON output.
- Report first, then apply only the fixes you approve by number, then re-check.
- The rule checklist goes in `SKILL.md` and the per-rule detail in `references/rules.md`.
- Rule 11: `evals/` with ≥3 entries, in any format. The baseline run is a manual confirm item.
- No `run-tests.sh` gate on skills beyond the existing `validate-skills.sh`.

## Phases

### Phase 1 — `scripts/lint_skill.py` + unittest
Write the mechanical checks for rules 1, 2, 5, 9, 10, 11 and 13, taking one skill or a folder and outputting JSON. Add good and bad fixture skills, and a unittest wired into the existing python stage.
**Depends:** none
**Verify:** the unittest passes, each detection has a failing fixture case, a mutation that disables any detection fails the test, and the script is stdlib-only.

### Phase 2 — `references/rules.md`
Write the 13 rules, each with its check, fix and Anthropic source URL, under a contents list. Paraphrased; generic; no CCV content.
**Depends:** none
**Verify:** all 13 rules are present with a check, a fix and a source. The contents list matches the headings. `grep -ri ccv` is empty.

### Phase 3 — `SKILL.md` + `evals/` + self-rating partial
Write the workflow checklist with go-back lines, the rule checklist, the Needs line and the report shape. Write a third-person description. Add ≥3 eval prompts. Inject the self-rating partial with `apply-partial.sh --force` and bump the drift-gate carrier count.
**Depends:** P1, P2
**Verify:** `lint_skill.py skills/skill-audit` reports no fails. `validate-skills.sh` is clean. `SKILL.md` is under 500 lines. The self-rating drift test passes.

### Phase 4 — Docs, live run, ship
Add the skill to the docs' skill listing and write `changelog.d/skill-audit.feature.md`. Do a live `/skill-audit skills/design-brainstorm` run (report only, no fixes applied). Run the full suite, validate, then `git-cli ship`.
**Depends:** P3
**Verify:** `run-tests.sh` passes in full. The live report has the summary table, the per-rule table and the ranked fixes, and nothing was edited. The PR is open.

## Risks / open questions

- The rules track Anthropic's skill guide, which changes. Re-syncing is manual for now. This rule set is a candidate for the `[workaround:]` tag and re-check in plan `add-a-per-release-prune-memory-pass`.
- Rule 10's hook advice is Claude-specific, since other harnesses have no skill-frontmatter hooks. The audit notes this and never fails a skill for it outside Claude.
- Heuristic false positives: the rule-10 never/always/must scan and the rule-13 phrasing regex will over-match. They're reported as candidates, and the model confirms them before listing a fail.
- The task ref still reads `add-audit-skill-command-delegating-to-hub-skill-audit`, because `taskctl` can't rename refs.
