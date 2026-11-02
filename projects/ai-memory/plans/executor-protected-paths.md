---
plan: executor-protected-paths
status: in_progress
created: 2026-11-02
owner: claude (orchestrator)
task_provider: notion
task_ref: 402f6850-c619-8118-a392-e5815438ab0a
---

# Executor-protected paths: guard config and plans

## Goal

An executor or subagent cannot take the convenient path of weakening a gate it hit: the existing PreToolUse guard denies its file-tool writes and obvious Bash writes to the live guard config and to plan files, so a deny is reported instead of edited away and a plan changes only via the orchestrator.

## Threat model

**Convenient-path executors, not a deliberate attacker.** The failure being prevented is a well-meaning executor that hits a deny and adds an exception, or misses a criterion and softens it — a direct, visible edit to an obvious file. Indirect routes (editing a script a hook executes, re-running the installer, variable/`eval`/interpreter tricks, redirects from unrelated verbs) are out of scope by design: a PreToolUse heuristic cannot win against an adversary anyway. **Review and validation briefs for this plan state this threat model; a finding that requires deliberate evasion goes to Risks, not to scope.**

## Success criteria

1. **R1** — In a guarded context, a Claude `Write`/`Edit`/`NotebookEdit` or Codex `apply_patch` targeting a protected path under the live root is denied (tests; Codex from a real captured payload).
2. **R2** — Protected set (`scripts/protected-paths.txt`): `scripts/deny-list*.txt`, `scripts/hooks/**`, `scripts/deny-match.sh`, `scripts/jsonutil.sh`, `scripts/path-match.sh`, `scripts/protected-paths.txt`, `config.local.sh`, `projects/*/plans/**`, plus the installed hook configs `~/.claude/settings.json` and `~/.codex/hooks.json`. Everything else — including the rest of the engine and `todo.md` — stays writable (test per entry).
3. **R3** — Live root = `path-match.sh`'s realpath'd repo, never env or cwd; globs anchored at it; target realpath'd. A worktree copy (incl. nested `<root>/.claude/worktrees/<slug>/`) or another clone is writable; a symlink or `..` path into a protected file is denied (tests).
4. **R4** — Guarded context = `AI_MEMORY_ROLE` set or Claude `agent_id` present, regardless of `AI_MEMORY_GUARD_SCOPE`: the path check runs before `guard.sh`'s scope early-exit. The path check never denies the main session; existing infra deny-list behaviour (incl. main-session `scope=all` denies) is unchanged (tests).
5. **R5** — Bash, obvious writes only: a guarded command that names a protected path (absolute, `~`-form, or relative to the hook input's `cwd`) **and** writes with `sed -i`, `>`/`>>`, `tee`, `cp`/`mv`, `rm` or `truncate` is denied. Reads and pathless commands are untouched (tests: `cat scripts/deny-list.txt`, `ls -la && git log --oneline` allowed; each write form denied).
6. **R6** — Deny reason names the route: guard config and plans change only via the orchestrator; report the deny or the divergence in your return.
7. **R7** — Doctrine executor hard rules and `docs/workflow.md`'s delegation contract carry one line: an executor that finds the design diverged from the plan, or hits a guard deny, reports it and never edits the plan or guard config.
8. **R8** — Each deny test is mutation-checked; full gate (`bash scripts/run-tests.sh`) green; `changelog.d` feature fragment; `check-docs.sh` clean.
9. **R9** — Post-merge live probe after `install.sh`: a Claude subagent `Edit` on `scripts/deny-list.txt` is denied (hash unchanged), and on a disposable probe plan created by the main session; the main session then edits and deletes the probe.

## Design

- **Matcher:** new sourceable `scripts/path-match.sh` (`path_guard_match <input-json>` → exit 0 + one-line reason, exit 1 allowed), data in `scripts/protected-paths.txt`. Extracts the target from Claude `tool_input.file_path` / `notebook_path`, Codex `apply_patch` file headers, or a Bash command (R5).
- **Single entry point:** `guard.sh` sources `path-match.sh` next to `deny-match.sh` and runs the path check first, before its scope early-exit; denies via its existing `deny`. Claude's `infra_guard` matcher widens from `Bash` to `Bash|Write|Edit|NotebookEdit`; Codex already matches `^Bash$|apply_patch`. No new manifest role.
- **Unextractable target** on a known write tool (`Write`/`Edit`/`NotebookEdit`/`apply_patch`) → deny. Every other tool passes the path check untouched.

Rejected:
- **Hardened version (whole-engine protection, installer deny, four-harness capture, four-class tool dispatch, worktree mandate for engine work)** — defends against a deliberate attacker; out of proportion to the convenient-path threat. Reviews drifted there by asking for every disarm route without a threat model.
- **Separate `path_guard` manifest role** — would need a Codex matcher special case and a second Copilot `preToolUse` key the no-Python installer fallback duplicates.
- **Follow `GUARD_SCOPE`** — inert on this instance (executors are Claude subagents, scope unset).
- **Protect `todo.md`** — executors tick their own phases; no gate reads it.

## Decisions (locked)

- Threat model: convenient-path executors (see above).
- Coverage: Claude and Codex — the executor planes in use. Copilot and Antigravity are a follow-up task.
- Live install only; worktrees and other clones writable.
- Executors + Claude subagents guarded regardless of `GUARD_SCOPE`; main session never denied by the path check.
- Engine work routing is unchanged by this plan.
- Divergence reporting is prose in the executor's return.
- **R5 validation cap (2026-11-02, after validator round 2):** the Bash heuristic is best-effort. Round-2 findings (redirect operands, `cd` chains, `truncate -r`) are fixed; from validator round 3 on, any further Bash parsing edge case outside R5's listed write forms goes to Risks, not blockers.

## Phases

### Phase 1 — `path-match.sh`: protected set, Claude file tools, Bash obvious writes
- `scripts/protected-paths.txt` (R2); `scripts/path-match.sh`: live-root resolution, anchored globs, realpath, context detection, Claude extraction, Bash write-form check, deny reason (R6).
- `scripts/tests/test_path_match.sh` covering R2–R6 on synthetic Claude input, mutation-checked.

**Depends:** none
**Verify:** `bash scripts/run-tests.sh --only path_match` green; each deny case fails when its rule is removed; shellcheck clean.

### Phase 2 — Codex `apply_patch` extraction
- Capture one real Codex `apply_patch` PreToolUse payload under a scratch `CODEX_HOME` (never the live `~/.codex`); save as `scripts/tests/fixtures/codex/pre_tool_use_apply_patch.json`.
- Extract target paths from its file headers in `path-match.sh`; fixture test for R1 (protected target denied, unprotected allowed, unparseable denied).

**Depends:** Phase 1
**Verify:** fixture is a real capture; Codex tests green and fail under mutation.

### Phase 3 — Wiring, doctrine, docs
- `guard.sh` sources `path-match.sh`, runs it before the scope early-exit; Claude manifest matcher widened; `test_hook_mapping.sh` / `test_install_harness.sh` Claude expectations.
- R7 line in `doctrine/orchestrator.md` and `docs/workflow.md`; `docs/harnesses/{claude,codex}.md` guard rows; `changelog.d/<id>.feature.md`; follow-up task captured for Copilot/Antigravity.

**Depends:** Phase 1, Phase 2
**Verify:** end-to-end test pipes a Claude `Edit` input and the Codex fixture through `guard.sh` and gets exit 2; R4 test with scope unset; existing `test_shared_hooks.sh` unchanged and green; `check-docs.sh` clean; R7 line present (grep); full gate green.

### Checkpoint — before PR
- Validator `scope: final`, `risk: high`, brief states the threat model (evasion findings → Risks, not blockers). Full gate green. PR via `git-cli ship`; merge is human.

### Phase 4 — Post-merge live probe
- `install.sh` on this instance (also clears the dangling `~/.claude/hooks/*` symlinks into the old `Downloads/` checkout), restart, run R9.

**Depends:** Phase 3, merge
**Verify:** R9 observed and recorded in the checkpoint.

## Risks / open questions

- **Interpreter writes — observed, deferred:** during fix round 2 a well-meaning executor edited protected `path-match.sh` via a python heredoc, contradicting this plan's assumption that interpreters imply deliberate evasion. Deferred to follow-up task `40cf6850-c619-8141-a6ea-e887e51abb18`, which also amends the threat model.
- **Uncovered shell forms (accepted):** `>|` (noclobber override — the shared tokenizer splits on `|`) and GNU `cp -t DIR src`.
- **Deliberate evasion is not covered** — indirect writes (hook-executed scripts, `install.sh`, interpreters, variables) remain possible; out of scope per the threat model.
- **Copilot / Antigravity executors unguarded** by this plan — follow-up task `40cf6850-c619-814d-b101-e80aecdbae02`; payload shapes and native-subagent markers unknown.
- **Codex `apply_patch` (verified P2, codex 0.163.0):** patch text is in `tool_input.command` — the same field `guard.sh` reads as `CMDLINE`, so patches are also deny-list-matched. A scratch hook only fired with `--dangerously-bypass-hook-trust`.
- **Known false positive:** `~/.claude/settings.json` is protected for every subagent, so the `statusline-setup` agent is denied; run it from the main session.
- **Codex `apply_patch` payload shape** unverified until P2.
- **Widened Claude matcher** sends every `Write`/`Edit` through `guard.sh`; its deny-list path must stay a no-op for non-Bash tools (empty `CMDLINE`) — covered by existing guard tests staying green.
- **Worktree bash block** (subagents in a worktree, cause unrecorded — possibly the gitignored `.claude/settings.local.json` allow-list missing in worktrees) is unrelated to this plan now; worth its own investigation if worktree routing comes back.
