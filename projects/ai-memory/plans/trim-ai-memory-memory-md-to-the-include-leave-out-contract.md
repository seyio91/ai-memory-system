---
plan: trim-ai-memory-memory-md-to-the-include-leave-out-contract
status: in_progress
created: 2026-10-08
owner: claude (orchestrator)
task_provider: local
task_ref: trim-ai-memory-memory-md-to-the-include-leave-out-contract
---

# Trim ai-memory memory.md to the include/leave-out contract

## Goal

Cut `projects/ai-memory/memory.md` from 45 KB to ≤16 KB (target 12–15 KB) under the include/leave-out contract: drop events and code-readable content, condense decisions to rule + why, move shipped-audience facts to their one home, and add Commands and Conventions sections.

## Success criteria

- `scripts/check-memory-size.sh --file projects/ai-memory/memory.md` prints no WARN: ≤ 16,384 B and no line > 400 B.
- `## Current State` and `## Current Goal` are gone; What It Is, Architecture Decisions, Known Constraints / Gotchas are present. `lint-memory.sh` shows no ai-memory WARN for rules 3 or 16, and the rest of the WARN set matches the pre-change set (compare sets, not counts).
- New `## Commands` lists `run-tests.sh` (`--changed` / `--only`), `lint-memory.sh`, `check-docs.sh`, `assemble-changelog.sh`, plus the signing-override note, each checked against the script's own usage.
- New `## Conventions` covers the commit route (housekeeping → `main`, system → `git-cli ship`), conventional-commit scopes, changelog fragments, and a pointer to `CONTRIBUTING.md`.
- One home per fact: each item the audit lists under "Move" is in its destination and gone from `memory.md`, both checked with `grep`.
- No PR numbers, SHAs or dated incident stories remain in `memory.md`; each kept rule says why in one clause.
- Both `## Current Goal` threads (branch protection, `@`-section loading) are local backlog tasks.
- The P1 PR is green: full suite with signing overrides, `check-docs.sh`.

## Design

Execute the audit's ai-memory section (investigation `memory-md-audit-2026-10`) as written: fix wrong entries first (D2), then cut, condense, move and add. Placement decisions:
- The testing doctrine (mutation testing, hermetic fixtures, test-runner glob, `set -e`, truncating pager, empty-list fixtures, live exercise of prose commands) moves to `CONTRIBUTING.md`, not a new `domain/testing-discipline.md`. New `domain/` files are gitignored, so they would never ship, and contributors need this doctrine.
- Codex `exec`/execpolicy facts go to `domain/codex.md`, which is tracked and shipped.
- The `link-skills.sh` prune rationale becomes a code comment at the prune pass.
- Git tag/force-push facts: `release.sh` already documents `--cleanup=verbatim`, so the memory line is cut. The force-push fact shrinks to one Gotchas line, since it is a repo-ops trap with no other home.
- The two `## Current Goal` threads are captured as backlog tasks, and the section is deleted (D6).

Rejected: one combined change. The moves touch shipped files and need a PR, while `memory.md` is housekeeping that goes straight to `main`. Mixing them would put housekeeping on a PR branch.

## Decisions (locked)

- Commit route: P1 → `git-cli ship` PR (system); P2/P3 → `git-cli commit --all` + push to `main` (housekeeping).
- D5 and D6 (still proposed) are treated as binding here, matching the shipped lint.

## Phases

### Phase 1 — Move shipped-audience facts to their homes
Add the testing-doctrine section to `CONTRIBUTING.md`, the Codex `exec`/execpolicy facts to `domain/codex.md`, and the prune-rationale comment to `scripts/link-skills.sh`. Add a changelog fragment if the change is user-visible. Ship with `git-cli ship`.
**Verify:** each moved fact can be found with `grep` in its destination; `bash scripts/run-tests.sh` is green under signing overrides; `check-docs.sh` passes; the PR is open.

### Phase 2 — Capture Current Goal threads as tasks
`taskctl capture ai-memory` for branch protection on `main` (status checks without required PRs) and for `@`-sign section-level loading.
**Verify:** `taskctl list ai-memory backlog` shows both.

### Phase 3 — Rewrite memory.md to the contract
**Depends:** P1, P2
Delete Current State and Current Goal. Apply the audit's cut and condense lists, remove each moved fact, and add Commands and Conventions. Record the lint WARN set before and after.
**Verify:** the success criteria for size, sections, lint set, one-home-per-fact and no-events all pass.

### Phase 4 — Validate and close
**Depends:** P3
Run a Validator pass (`risk: medium`) against `## Success criteria`. Commit the housekeeping to `main`, then mark the plan done, the task done and the Target done.
**Verify:** the validator returns READY; the task status is `done`; the plan is archived.

## Risks / open questions

- Over-cutting: a deleted gotcha resurfaces as a repeated mistake. Mitigation: the validator spot-checks each deleted Gotchas entry against the per-line test.
- P1 is a system change waiting on a PR merge, and P3 waits on P1, so P3 must not remove moved facts until P1 has merged.
