---
plan: project-scan
status: done
completed: 2026-10-31
created: 2026-10-20
owner: claude (orchestrator)
task_provider: notion
task_ref: 3dbf6850-c619-814d-8eba-e26e28c029cf
---

# project-scan — derive project memory from the repo

## Goal

Add a `project-scan` skill that reads a project's checkout read-only and proposes `memory.md` content without breaking the content contract: point to docs the repo already has, draft only commands and conventions no doc states, and turn code signals into candidate decisions/gotchas you confirm. `/new-project` uses it at onboarding; it also runs standalone on existing projects.

## Success criteria

1. `skills/project-scan/SKILL.md` exists, passes the suite's skill validation (`run-tests.sh` skills stage) with no new warning, and `link-skills.sh` installs it.
2. The skill states and follows: repo resolved from `repo_path` frontmatter, an argument, or the caller; **draft** mode when `memory.md` still holds template placeholders, **propose** mode otherwise; one read-only explore pass; contract filter (`docs/file-formats.md` include/leave-out table) with a dropped-lines count by reason; applies only what the user picks; never writes the target repo; never writes `memory.md` without confirmation.
3. Every drafted or proposed line cites its source (`file:line` or commit); every candidate decision/gotcha cites the code signal behind it.
4. `/new-project` calls `project-scan` after the repo-path question, skips questions whose sections the user accepted, always asks Architecture Decisions and Known Constraints / Gotchas, and keeps today's six-question flow when no repo path is given or the scan fails.
5. Live exercise A — new project on a real repo that has a CLAUDE.md/README: Pointers links it, no command is copied from a doc that already states it; target repo `git status --porcelain` identical before/after; lint on the new `memory.md` has no finding beyond the template baseline. Throwaway project removed afterwards.
6. Live exercise B — standalone on an existing populated project: numbered proposals only, `memory.md` byte-identical until a pick is made, then only picked lines change.
7. Docs: skill listed where bundled skills are described (`docs/harnesses/claude.md` Skills, `docs/showcase.md`); `commands/new-project.md` updated; changelog fragment `changelog.d/project-scan.feature.md`. Full gate green; lint ERROR/WARN set unchanged.

## Design

Prose skill (`skills/project-scan/SKILL.md`) that delegates the read to one explore agent (Claude `Explore` subagent; other harnesses via `executor.sh --role explore`). Harness-agnostic, Two-Path, no new script.

Flow: resolve repo → one explore pass returns (a) docs found (CLAUDE.md, AGENTS.md, README, `docs/`, ADRs), (b) commands/conventions stated by **no** doc, with source file:line (CI, Makefile, package scripts, commitlint, branch rules), (c) candidate decisions/gotchas from code signals (HACK/FIXME/XXX/workaround comments, pins with a stated reason, reverted commits, ADRs) → contract filter, count drops by reason → present (draft: Pointers + undocumented Commands/Conventions + candidates; propose: numbered add/correct/stale-line list) → apply picks → ask Decisions/Gotchas for the gaps, candidates as prompts → `regenerate-index.sh` + lint the file.

Alternatives rejected:
- Skill + deterministic `project-scan-signals.sh` — more code for a rarely-run operation (YAGNI); revisit if the prose pass proves flaky.
- Inline in `/new-project` only — the 13 existing projects never benefit.
- Drafting all derivable sections — duplicates `/init` / repo docs and the contract's "readable from the code" leave-out row.
- Parallel fan-out by focus area — orchestration cost for repos one pass covers.
- Coupling to `fiter-infrastructure-analyzer` — it writes repo docs; this writes memory.

## Decisions (locked)

- Pointer-first: link existing docs, never copy them.
- Target repo is read-only; never offers `/init` or writes any file there.
- Propose mode never auto-applies; user picks by number.
- Contract filter shows what it dropped (count by reason), never silent.
- Separate from `fiter-infrastructure-analyzer`.
- Phases are sequential (P2 wires what P1 defines; P3 exercises both).

## Phases

### Phase 1 — the skill
**Depends:** none
**Verify:** criteria 1–3 by reading `SKILL.md` against each clause; `bash scripts/run-tests.sh` skills stage clean; `bash scripts/link-skills.sh` links `project-scan` into `~/.claude/skills/`.

### Phase 2 — wire `/new-project`, docs, changelog
**Depends:** Phase 1
**Verify:** criteria 4 and 7 by reading `commands/new-project.md` (no-path and scan-failure paths still reach the six questions); `check-docs.sh` 0 findings; full gate green.

### Phase 3 — live exercise
**Depends:** Phase 2
**Verify:** criteria 5 and 6 with pasted evidence (before/after `git status --porcelain`, `cmp` of `memory.md`, lint output); throwaway project directory gone.

## Risks / open questions

- Explore pass may misjudge "stated by a doc" vs undocumented (e.g. a command in README prose vs a code block). Live exercise A is the check; tighten the skill's wording if it copies documented commands.
- Candidate signals may be noisy on large repos (hundreds of TODOs). Cap candidates shown (e.g. top 10 by signal strength) if exercise output is unreadable.
- Deterministic signal script deferred — add only if prose results are inconsistent across runs.
- Live exercise A creates a real project dir under `projects/`; must be removed and index regenerated after.
