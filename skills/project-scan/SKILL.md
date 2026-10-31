---
name: project-scan
description: Scans a project's checkout read-only and proposes memory.md content that passes the memory content contract — links docs the repo already has, drafts only commands and conventions no doc states, and turns code signals into candidate architecture decisions and gotchas for the user to confirm. Drafts a fresh memory.md during onboarding or proposes numbered additions and corrections for an existing one, applying only what the user picks. Use when onboarding a project into memory (called by /new-project), or when asked to scan, map, or refresh a project's memory from its repo.
---

# Project scan

Read a project's checkout once, then propose `memory.md` content that a session could not
work out from the code or the repo's own docs. Never write the repo. Never write `memory.md`
without the user's pick.

## Must not miss

- **The target repo is read-only.** No file, marker, commit or `/init` there — ever. Many
  checkouts are client repos.
- **Point, don't copy.** If a repo doc (CLAUDE.md, AGENTS.md, README, `docs/`, ADRs) already
  states a command or convention, link the doc under `## Pointers`; do not restate it.
- **Every line cites its source** — `file:line` or a commit sha. A line you cannot cite is
  not proposed.
- **Nothing is applied without a pick.** Present, wait for the user's numbers, apply only those.
- **The filter is visible.** Report what the contract filter dropped, as a count by reason.

## Inputs

- **Project name** (required) — the memory project, `projects/<name>/memory.md` under the
  memory root (`$MEMORY_DIR`, default `~/.claude-memory`).
- **Repo path** — first of: an explicit argument; the caller's value (`/new-project`'s
  repo-path answer); `repo_path` in the project's frontmatter, resolved against
  `AI_MEMORY_PROJECTS_ROOT` when relative. None, or not a directory → stop and say so (the
  caller falls back to its own questions).

## Mode

- **draft** — `memory.md` still carries template placeholders (the `summary:` placeholder or
  section bodies that are only template guidance). Produce section drafts.
- **propose** — `memory.md` is populated. Produce a numbered change list against it.

## Step 1 — one read-only explore pass

Dispatch **one** read-only explore agent at the repo (Claude: the `Explore` subagent; other
harnesses: `scripts/executor.sh --role explore`). Give it the repo path, and in propose mode
the current `memory.md`. Ask for three lists, each item with its `file:line` or commit:

1. **Docs found** — CLAUDE.md, AGENTS.md, README, `docs/`, ADR directories, CONTRIBUTING.
   One line each on what the doc covers.
2. **Undocumented commands and conventions** — build/test/lint/release commands, branch
   naming, commit/PR format, style rules that come from CI config, Makefile/Taskfile, package
   scripts, commitlint, pre-commit or branch rules **and are stated in no doc from list 1**.
   For each, name the doc it checked and did not find it in.
3. **Candidate decisions and gotchas** — code signals that suggest a locked-in choice or a
   landmine: `HACK`/`FIXME`/`XXX`/workaround comments with a reason, a pinned version with a
   stated reason, reverted commits, ADRs, a deliberately disabled check. Each candidate names
   its signal. Cap at the ten strongest; say how many more were seen.

In propose mode also ask for: lines in the current `memory.md` the repo **disproves** (a
command that no longer exists, a path that moved), each with the evidence.

## Step 2 — apply the content contract

Filter every item against the include/leave-out table in `docs/file-formats.md` (→ *Project
memory sections*): keep a line only if removing it would make a session go wrong. Drop
inventories, version pins without a reason, counts, layout trees, file-by-file descriptions,
standard language conventions, anything that changes often. Keep a tally of drops by reason.

## Step 3 — present

**draft mode** — show, in template section order:

- `## What It Is` — one line (stack, purpose), from the docs found.
- `## Commands` / `## Conventions` — only the undocumented items from list 2.
- `## Pointers` — one line per doc from list 1.
- **Candidates** — numbered decisions/gotchas from list 3, each with its signal.

**propose mode** — one numbered list: `add` (new line, target section), `correct` (old →
new), `stale` (a line the repo disproves, with evidence). Existing lines not mentioned are
untouched.

End with the filter line: `dropped N: <reason> ×k, …`. Ask which numbers to apply.

## Step 4 — apply the picks, then ask the gaps

- Write only the picked items into `memory.md`, in their sections. In draft mode also set
  the frontmatter `summary:` to the What It Is line.
- Then ask the user for `## Architecture Decisions` and `## Known Constraints / Gotchas`,
  using the confirmed candidates as prompts ("you confirmed X — anything else locked in?").
  These two sections are required; the scan cannot produce them alone.
- Run `bash <memory-root>/scripts/regenerate-index.sh` (draft mode) and
  `bash <memory-root>/scripts/lint-memory.sh`, and report any finding on this project.

## Failure handling

- Explore pass fails or returns nothing usable → report it and stop; the caller's manual
  path still works.
- The user picks nothing → change nothing; say so.
- A pick conflicts with an existing line (propose mode) → show both and ask; never merge
  silently.

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
