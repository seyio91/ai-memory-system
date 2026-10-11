---
name: skill-audit
description: Audits Claude skills (a folder with a SKILL.md) against 13 skill-writing rules from Anthropic's guides. Runs a bundled lint script for the mechanical checks, judges the rest, reports pass/fail with file:line evidence and a ranked fix list, then applies only the fixes the user approves by number. Use when reviewing, auditing, linting, or improving a skill or a folder of skills, or when asked whether a skill follows best practices.
---

# Skill audit

Audit one skill or a folder of skills, report first, edit only what the user approves.

## Must not miss

- Report before editing anything. No file changes until the user replies with fix numbers.
- Apply only the approved fix numbers. Never bundle extra edits in.
- Re-check after fixing: re-run the script and re-judge the changed skills.
- Rule 4 and the rule 11 baseline run are "test this" items. They are never fails.
- Script candidates (rules 10 and 13) are heuristic. Read the line in context and confirm before listing a fail.

## Needs

`python3` 3.8 or newer, stdlib only. Check with `python3 --version`. No packages to install.

## Workflow

Copy this checklist into the reply and tick items off:

```
- [ ] 1. Run the lint script
- [ ] 2. Confirm candidates, judge rules 3, 4, 6, 7, 8, 12
- [ ] 3. Write the report
- [ ] 4. Stop and wait for approval numbers
- [ ] 5. Apply only the approved fixes
- [ ] 6. Re-run the script, re-judge changed skills
- [ ] 7. List changes file by file
```

1. Run `python3 <skill-dir>/scripts/lint_skill.py <path>`, where `<skill-dir>` is the folder containing this SKILL.md. `<path>` is one skill folder or a folder whose subfolders are skills. The output is JSON: per skill, findings with `rule`, `status` (`fail`, `candidate`, `error`), `file`, `line`, `message`. An `error` finding (rule 0) means a file could not be read; report it and continue. If the script exits 2, fix the path and repeat this step.
2. Read each skill's SKILL.md and files it links. Open the file and line behind every `candidate` and decide: confirmed (becomes a fail) or dismissed (drop it). Then judge rules 3, 4, 6, 7, 8 and 12 using [references/rules.md](references/rules.md). Rules 1, 2, 5, 9, 11 are covered by the script; judge only their non-mechanical parts (rule 5 verbosity, rule 9 dependency list). If a skill cannot be read in full, say so and mark the affected rules n.a.
3. Write the report in the shape below.
4. Stop. Ask which fix numbers to apply. Do not edit.
5. Apply only the approved numbers, smallest diff that resolves each.
6. Re-run the script on the same path and re-judge the changed skills. If anything approved still fails, go back to step 5. After two attempts on the same fix, stop and report what still fails and why.
7. List the changes file by file, with the fix number each one resolves.

## Report shape

This is the default shape; adapt it only if the user asks.

**Summary table**: one row per skill.

| Skill | Fails | Worst problem |
|---|---|---|

**Per skill**: one rule table, all 13 rules.

| Rule | Result | Evidence (file:line) | Fix |
|---|---|---|---|

Result is `pass`, `fail`, `n.a.` or `test`.

**Fixes**: one numbered list across all skills, ranked by impact, each naming the skill, file and change.

**Test these**: a separate list for rule 4 (instructions to try removing against the evals) and the rule 11 baseline run. Never counted as fails.

## Rules

One line per rule. Check and fix detail, plus source URLs, live in [references/rules.md](references/rules.md).

1. Progressive disclosure: body under 500 lines, files linked directly from SKILL.md, no dead links.
2. Contents lists: reference files over 100 lines open with one.
3. Degrees of freedom: instruction precision matches how fragile the step is.
4. Test on the models used: stale scaffolding for older models. Test item only.
5. Concise, third-person: description says what and when, no first or second person.
6. Workflows and checklists: numbered steps, copyable checklist, go-back lines.
7. Feedback loops: check, fix, repeat; script errors name the problem and what exists.
8. Common patterns: template strictness stated, example pairs, explicit branches.
9. Shareability: forward-slash relative paths, dependencies named with install lines.
10. Hooks for must-hold rules: never/always/must lines as hook candidates. Applies to Claude Code only; on other harnesses report n.a.
11. Evaluations first: `evals/` with at least 3 prompts; baseline run is a test item.
12. Important instructions first: must-not-miss rules at the top of SKILL.md.
13. No reasoning echo: no instruction to write out reasoning in the reply.

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
