# Skill audit rules

Per-rule reference for auditing a skill folder: what to check, how to fix it, and where the guidance comes from.

## Contents

1. [Progressive disclosure](#1-progressive-disclosure)
2. [Contents lists](#2-contents-lists)
3. [Degrees of freedom](#3-degrees-of-freedom)
4. [Test on the models you use](#4-test-on-the-models-you-use)
5. [Concise, third-person](#5-concise-third-person)
6. [Workflows and checklists](#6-workflows-and-checklists)
7. [Feedback loops](#7-feedback-loops)
8. [Common patterns](#8-common-patterns)
9. [Shareability](#9-shareability)
10. [Hooks for must-hold rules](#10-hooks-for-must-hold-rules)
11. [Evaluations first](#11-evaluations-first)
12. [Important instructions first](#12-important-instructions-first)
13. [No reasoning echo](#13-no-reasoning-echo)

## 1. Progressive disclosure

**Check** (mechanical: `scripts/lint_skill.py`): the SKILL.md body is under 500 lines. Every supporting file is linked directly from SKILL.md, one level deep. No file is reachable only through another reference file. Every linked file exists. Judgement: detail that only some runs need (long examples, API tables, edge cases) belongs in a separate file, not the body.

**Fix**: move bulky detail into files under `references/`, link each one from SKILL.md with a line saying when to read it, and delete or relink orphans and dead links.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

## 2. Contents lists

**Check** (mechanical): any reference file over 100 lines opens with a contents list near the top, so a partial read still shows the full scope.

**Fix**: add a `## Contents` list of the file's sections right under the H1. Anchor links are optional but help.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

## 3. Degrees of freedom

**Check** (judgement): instruction specificity should match how fragile the step is. Fragile or costly steps (migrations, deletes, deploys, exact-format output) need an exact command or bundled script. Steps where many approaches work need a plain goal. Flag risky steps left loose, and simple steps locked down to the character.

**Fix**: for a loose risky step, give the exact command or move it into a script with a "run as is" instruction. For an over-locked step, replace the procedure with the goal and any constraints that matter.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

## 4. Test on the models you use

**Check** (judgement; report as a test item, never a fail): guardrails, repeated emphasis, or step-by-step scaffolding written for an older model can over-constrain a current one. Look for shouted capitals, redundant reminders, and micro-managed procedures for tasks the model handles unaided.

**Fix**: do not remove anything blindly. Propose "run the evals with this instruction removed" and keep the instruction only if results get worse. Recheck whenever the target model changes.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices and https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5#recommended-scaffolding-changes

## 5. Concise, third-person

**Check** (mechanical: description person; judgement: verbosity): the frontmatter `description` is third person ("Audits...", "Use when...") and states both what the skill does and when to use it. It must not use "I" or "you". In the body, keep only what the model cannot infer: domain facts, internal conventions, non-obvious pitfalls. Flag paragraphs that explain general knowledge (what a PDF is, how git works).

**Fix**: rewrite the description in third person with a what and a when. Cut general-knowledge explanations down to the project-specific delta.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

## 6. Workflows and checklists

**Check** (judgement): a multi-step job has numbered steps, a copyable progress checklist, and after each verification step a go-back line saying where to return on failure. Flag unnumbered multi-step prose and verification steps with no failure path.

**Fix**: number the steps, add a checkbox checklist the model can copy into its reply and tick off, and add "if this fails, go back to step N" after each check.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

## 7. Feedback loops

**Check** (judgement): output where quality matters runs a loop of check, fix, repeat until the check passes. Bundled scripts emit specific errors that name the problem and what actually exists (for example the missing field and the fields found), not a bare "invalid".

**Fix**: add a validation step with an explicit repeat-until-pass instruction. Improve script errors to say what was wrong, where, and what is available.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

## 8. Common patterns

**Check** (judgement): a template states how strictly to follow it (exact format versus adapt as needed). Output that depends on style has input/output example pairs. A job with branches has an explicit fork ("if creating new, do A; if editing existing, do B").

**Fix**: add a one-line strictness note to each template, add two or three example pairs for style-dependent output, and turn buried branching into an explicit decision point.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

## 9. Shareability

**Check** (mechanical: paths; judgement: dependency list): no backslash paths and no machine-specific absolute paths (home directories, drive letters, usernames). Judgement: every package or tool the skill needs is named with an install line in SKILL.md, not assumed present.

**Fix**: switch to forward slashes and paths relative to the skill folder. Add a "Needs" line with an install command for each dependency.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices

## 10. Hooks for must-hold rules

**Check** (mechanical candidates; judgement to confirm): lines saying never, always, or must describe rules that should hold every run. Prompt text can be skipped, so these are candidates for a hook declared in the skill's `hooks` frontmatter. Confirm the rule is actually enforceable by a command, and name the event (for example PreToolUse on Bash to block a forbidden command). Claude Code specific: on other harnesses, note the candidate and never fail the skill.

**Fix**: add a hook entry in frontmatter with the event, matcher, and a small script that blocks or corrects the violation, and keep the prose rule as the explanation.

**Source**: https://code.claude.com/docs/en/skills and https://code.claude.com/docs/en/hooks

## 11. Evaluations first

**Check** (mechanical: count; baseline is a manual confirm item): `evals/` holds at least three test prompts, either entries in skill-creator's `evals/evals.json` or separate files. Ask whether a baseline run without the skill was done to show what the skill adds. Report the baseline as a "test this" item, never a fail.

**Fix**: write three or more realistic prompts, including at least one edge case. Run them with and without the skill and compare before refining the instructions.

**Source**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices and https://code.claude.com/docs/en/skills

## 12. Important instructions first

**Check** (judgement): the must-not-miss rules sit near the top of SKILL.md. After context compaction, only the start of an invoked skill may be retained, so rules buried at the bottom can be lost. Flag critical constraints that first appear late in a long body.

**Fix**: move the critical rules to the top, directly under the title or description, and leave background and examples lower down or in reference files.

**Source**: https://code.claude.com/docs/en/skills

## 13. No reasoning echo

**Check** (mechanical candidates; judgement to confirm): no instruction asks the model to write out its internal reasoning in the reply ("think step by step in your answer", "show your chain of thought"). A short explanation of the final answer is fine. Regex hits are candidates; confirm the intent before failing.

**Fix**: replace with a request for the conclusion plus a brief justification, or let the model reason internally without echoing it.

**Source**: https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5#recommended-scaffolding-changes
