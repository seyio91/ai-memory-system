---
plan: initiative-orchestrator
status: done
completed: 2026-11-20
created: 2026-11-19
owner: claude (orchestrator)
task_provider: local
task_ref: initiative-orchestrator-spawn-target-sessions-in-iterm2-panes-and-coordinate-via-sendmessage
---

# Plan — Initiative orchestrator (Claude + iTerm2 personal skill)

## Goal
A personal skill that turns a Claude session into an initiative launcher: it offers the initiative's "Sessions to start", opens a named Claude session per confirmed Target in an iTerm2 pane in the Target's repo, and hands it the task in the launch prompt. It does not supervise: Target sessions run under the normal doctrine and update the initiative themselves.

**Before:** Each Target session is opened by hand: find the repo, open a tab, start claude, paste the task.
**After:** `/initiative-orchestrator <slug>` opens confirmed Target sessions in panes (orchestrator + 2 in the first tab, 3 per tab after), each named after its Target, in its resolved repo, with a launch prompt that runs `/start <task>` for a fresh Target, resumes the live plan for an in-flight one, or carries the scope when there is no task; after launch the sessions are independent.

## Non-goals
- Shipping it with the engine: no `scripts/`, `harnesses/` or `docs/` change, no changelog fragment, no PR.
- Any terminal other than iTerm2 (tmux deferred), any harness other than Claude Code.
- A session registry or state file — the initiative file, checkpoints and session names already carry the state.
- Closing panes: the user closes finished panes.
- Auto-spawning: every session is opened only after the user confirms that Target.
- Supervising sessions after launch: no report protocol, no single-writer rule, no restart re-attach (removed 2026-11-19 — a long-running Target loses launch-prompt rules on `/clear`, and the orchestrator should not babysit). Target sessions update their own Target and append decisions under the normal doctrine.

## Success criteria
- R1 [acceptance] Spike findings recorded under `## Risks / open questions`: whether a `claude --name <target-id>` session shows that name in `ListAgents`; why two of today's tabs never registered (reproduced with cause, or recorded as not reproduced with a guard in `spawn.sh`); what happens to a `SendMessage` to a session in a different permission mode.
- R2 [acceptance] `spawn.sh`, given the orchestrator's iTerm2 session id, places Target 1 and 2 as panes in the orchestrator's tab and Target 3+ in further tabs of at most 3 panes, counting live panes — closing a pane frees its slot. Shown by an osascript dump of tabs and session counts after each spawn.
- R3 [acceptance] `spawn.sh` resolves the Target's project through `resolve_repo_path` (`scripts/_lib.sh`); when that returns non-zero or the result is not a directory it exits non-zero with a message naming the Target, and opens nothing.
- R4 [acceptance] The skill lists the initiative's "Sessions to start" and opens only the Targets the user confirms; each launch prompt carries `/start <task>` (or, when there is no `task:`, the Target `scope:` as plain text — never `/start <scope>`), and the instruction to work in its own git worktree before changing files.
- R5 [removed 2026-11-19 — supervision dropped] A `STATUS` report updates that Target's `- status:` line and a `PROPOSE` report appends the next `D<n> proposed <date>` with its `unconfirmed:` line (and a topic when frontmatter `topics:` is set), both written by the orchestrator, followed by `initiative-render.sh <slug> --write`; `--check` then passes. A report it cannot place is put to the user, not guessed.
- R6 [removed 2026-11-19 — supervision dropped] After an orchestrator restart, the new orchestrator finds live Target sessions by name in `ListAgents` and sends each "orchestrator is now `<name>`"; the next report arrives at the new session.
- R7 [acceptance] No tracked file changes outside `projects/ai-memory/` (`git status --porcelain -- . ':!projects/ai-memory'` is empty); the skill lives in gitignored `skills/initiative-orchestrator/` and is linked by `scripts/link-skills.sh`.

## Design
- **Spawn:** `claude --name <target-id> -- "<launch prompt>"` in a pane; the launch prompt is the whole handoff. The user can still message a Target by name with SendMessage, but the skill does not.
- **Layout:** panes are split relative to the orchestrator's `ITERM_SESSION_ID` (not "current session", which moves with focus). First tab: orchestrator + 2 Targets; later tabs: up to 3 Targets. Slots counted from live iTerm2 panes, never from a file.
- **Session ↔ Target:** sessions are named after their Target id (`--name`, verified in the spike: the name is what `ListAgents` shows). A name already running is never spawned again, so collisions are refused up front (first-report fallback dropped, Phase 3 validation).
- **No supervision:** after launch the orchestrator does nothing. Target sessions follow the normal doctrine (update their own Target, append D<n> with the highest-D-id re-check), so `/checkpoint`, `/clear` and resume behave as in any session.
- Single writer with STATUS/PROPOSE reports → rejected 2026-11-19 after Phase 3 validation: engine commands (`/start`, `/checkpoint`, `/plan-done`) write the initiative themselves, and `/clear` drops launch-prompt rules, so it needed re-injection machinery for a long-running Target the orchestrator should not babysit.
- **Repo resolution:** Target id `<project>/<name>[@env]` → `resolve_repo_path <project>` from `scripts/_lib.sh` (handles relative-to-`AI_MEMORY_PROJECTS_ROOT`, absolute, `$MEMORY_DIR`, and the git-remote fallback). Never read `repo_path` raw.
- **Sessions to start:** rows in the Now fence carry only `| <target-id> | <next> |`; `task:` and `scope:` come from the Target's `### <id>` block. Run `initiative-render.sh <slug>` (print mode) first so a stale fence is not trusted.
- **Done Target:** its `status: done` is the whole record; the pane stays open for the user to close.
- In-process `Agent` subagents → rejected: not visible or steerable in panes.
- Headless `claude -p` → rejected: cannot be messaged, no interactive view.
- State-file registry → rejected: done Targets need only `status: done`, and live mapping comes from session names.

**Builds on:** `scripts/initiative-render.sh` (Now view "Sessions to start", `--write`/`--check`), initiative Target format (`docs/initiatives.md`), `scripts/link-skills.sh`, Claude Code `ListAgents`/`SendMessage`/`notify_when_idle`, `claude --name`.

## Decisions (locked)
- base: `30a34941a5520443676dae7bcf73e0a75e631cb0`
- Second session per project: warn and ask; each launch prompt requires a worktree (2026-11-19).
- Personal skill under gitignored `skills/initiative-orchestrator/` (`SKILL.md` + `spawn.sh`); commit route for this plan is `projects/**` only.
- Phases are sequential; P2 and P3 both depend on P1's findings.

## Phases
### Phase 1 — Spike: naming, registration, permission modes
- Open a pane with `claude --name spike-a "hello"` via osascript; check whether `ListAgents` shows `spike-a`.
- Reproduce the two unregistered tabs (new tab via `current window`/`current session`, `claude "hello"`), find the cause.
- Send to a session started in a different permission mode; record whether the message is held, dropped or delivered.
- Record findings with the commands used in this plan's `## Risks / open questions`; adjust `## Design` if `--name` does not reach `ListAgents`.

**Files touched:** `projects/ai-memory/plans/initiative-orchestrator.md`
**Risk:** low
**Depends:** none
**Verify:** R1 — the three findings are in `## Risks / open questions`, each with the command that produced it.

### Phase 2 — spawn.sh launcher
- `spawn.sh --orchestrator <ITERM_SESSION_ID> --target <id> --prompt <text> [--dry-run]`: strip the `wNtNpN:` prefix (AppleScript ids are the bare UUID), resolve the repo with `resolve_repo_path <project>`, resolve layout from live panes, split or open a tab, run `cd <repo> && claude --name <target-id> "<prompt>"`, print the new pane's session id. `--dry-run` prints the repo and layout decision and opens nothing.
- Refuse an unresolvable or non-directory repo before touching iTerm2.

**Files touched:** `skills/initiative-orchestrator/spawn.sh` (new)
**Risk:** medium
**Depends:** Phase 1
**Verify:** R2, R3 — `--dry-run` shows the layout decision for each step; four spawns of a no-op prompt yield tab/pane counts 3, then 3+1, matching osascript dumps; closing one pane and spawning again reuses that tab; a bad repo exits non-zero with no new pane.

### Phase 3 — Orchestrator skill
- `SKILL.md`: read the initiative's "Sessions to start", resolve each Target's repo, ask the user which to open, compose the launch prompt, call `spawn.sh` one at a time, then stop.
- Run `scripts/link-skills.sh`.

**Files touched:** `skills/initiative-orchestrator/SKILL.md` (new)
**Risk:** medium
**Depends:** Phase 1, Phase 2
**Verify:** R4, R7 — live run on a scratch initiative (below): only confirmed Targets open; launch prompts contain `/start <task>` or the scope, and the worktree rule; the R7 git command is empty.

### Checkpoint
- Live exercise on a scratch initiative `initiatives/orchestrator-scratch.md` (gitignored) with three Targets in `ai-memory` and no `task:`, then delete it.
- Real-initiative spawn: from vault-eks "Sessions to start", open one Target per project (e.g. `eks/vault-tenant-tp-staging`) with a read-only test prompt; it lands in the resolved repo. Done once in Phase 2 (2026-11-19): repo `ccv-terraform/eks`; `rds-user-management/vault-support` refused — no `rds-user-management` project in memory.
- `bash scripts/lint-memory.sh` shows no new ERROR.
- User reviews `SKILL.md` and the pane layout.

## Risks / open questions
- **Spike finding (2026-11-19) — naming:** `claude --name spike-a 'hello'` in a split pane (osascript `split vertically` on the orchestrator's session) and `claude --name spike-b 'hello'` in a new tab both appear in `ListAgents` as `spike-a` / `spike-b` within 2 s (sockets `/tmp/cc-socks/<pid>.sock`, `ps` shows `claude --name spike-a hello`). An unnamed session gets a generated `<project>-<hex>` name. Target-id naming works; `spawn.sh` refuses a name that is already running.
- **Spike finding (2026-11-19) — unregistered tabs:** not reproduced (R1 amended by the user to accept this). Re-spawning the same `create tab` + `write text "… claude 'hello'"` registered (`ai-memory-0a`) within 2 s. The earlier tabs were already closed (osascript session dump showed only the orchestrator's session), so the original cause is unknown; most likely the first `ListAgents` ran before registration and the second tab was never checked alone. Mitigation in `spawn.sh`/skill: after launch, wait for `/tmp/cc-socks/<pid>.sock` or the name in `ListAgents` before relying on it.
- **Spike finding (2026-11-19) — permission modes:** orchestrator in auto mode; `spike-a` (default) and `spike-plan` (`--permission-mode plan`) both received `SendMessage` with no hold notice and replied; both report `from-mode="prompting"`. Default and plan share a class, so orchestrator → Target messaging is not held. Untested: `bypassPermissions` Targets — the skill launches Targets in default mode only. `notify_when_idle` notices are documented as guaranteed only for the same permission class or sessions this session spawned; in the spike both `prompting` sessions' idle notices did reach the auto-mode orchestrator.
- `/start <ref>` on a live run scaffolds a plan in the Target's project and flips the task to `started` — the scratch Checkpoint uses Targets without `task:` to avoid that.
- Live runs open real panes and sessions; only `spawn.sh --dry-run` is side-effect free.
- Feasibility CAUTION (base `30a3494`): the plan file and `orchestrator.local.md` are untracked/gitignored, so they can only be checked in the working tree, never at base.
- Feasibility CAUTION: Phase 2 real spawns and the Phase 3 live run have no dry-run form; `--dry-run` covers only the repo and layout decision.
- `spawn.sh` is reached through the `~/.claude/skills` symlink, so it must source `_lib.sh` from the memory root (`$MEMORY_DIR` / `~/.claude-memory/scripts/_lib.sh`), not relative to its own path.
- Scratch Targets without `task:` raise a lint WARN (not ERROR); expected during the Checkpoint.
- Target sessions open in the project's shared checkout on whatever branch it is on (the eks test landed on `fix/vault-auth-mount-staging-env-name`), and two Targets of one project (both `platform-sandbox/*` in vault-eks) would share one checkout. Decided 2026-11-19: every launch prompt tells the session to work in its own worktree before changing anything, and the skill warns and asks before opening a second live session for a project that already has one (found by name prefix `<project>/` in `ListAgents`).
- Phase 2 validator (READY, `decorrelated: no`): fixed in `spawn.sh` — parallel spawns overfilling a tab (`mkdir` lock per orchestrator around layout+split; two concurrent spawns went to tab5 and a new tab6), missing option value hanging the arg loop, prompts starting with `-` (`--` before the prompt), long prompts typed into a starting shell (prompt passed via a temp file, read and removed by the pane's shell; a 2455-byte prompt arrived intact). Accepted: registration check matches only a bare `claude` argv[0] (true here: native binary on PATH); tab index can shift if the user reorders tabs between the two osascript calls; no osascript timeout beyond AppleEvent's ~2 min.
- Phase 3 validation (BLOCKED, 2026-11-19): Target sessions' engine commands still wrote the initiative file and PROPOSE appended at end of file (under `## Closure`) — both moot after supervision was dropped. A live scratch run had proven STATUS/PROPOSE intake and restart re-announce before the drop.
- Launcher re-run (2026-11-19): first alpha spawn failed — a stray keystroke reached the new pane before the command (`zsh: command not found: acd`), the likely cause of the spike's unregistered tabs too. Fixed in `spawn.sh`: Ctrl-U clears typeahead before the command, focus returns to the orchestrator pane after each spawn; retry and beta/gamma registered. Not exercised live: an unselected Target staying closed (the user selected all rows both runs).
- Final validation round 1 (NOT-READY, 2026-11-20), fixed: in-flight Targets (task with a live plan, e.g. vault-eks `eks/vault-tenant-tp-staging`) would have been sent `/start <task>` and could get a duplicate plan — the skill now resumes the matched plan, refuses two live plans, and runs `/start <task> --worktree` only for fresh Targets; focus restore re-finds the orchestrator by unique id inside `try` after the new pane's id is captured; `spawn.sh` refuses a Target name that is already running; the prompt temp file is removed when the spawn fails before launch (a pane whose typed command never ran still leaves it); `(stage: …)` placeholders are dropped from prompts; unnamed sessions are matched on the repo directory name. Drift exit 1 on `30a3494...HEAD` is only #158 (`6ed33e5`, domain-files plan), not this plan.
- Final validation round 2 (READY, `decorrelated: no`, 2026-11-20). Follow-ups applied: INT/TERM/HUP now exit through the EXIT trap so a killed spawn frees its lock and temp file; in-flight detection uses `extract_fm_field` like `initiative-status.sh`; the worktree line tells a resumed Target to continue on the plan's existing branch/worktree. Accepted: the duplicate-name guard matches only `claude --name <id>` argv (bare `claude` on PATH here; the skill's ListAgents check covers the rest); unchecked prompt-file write; dry-run prints an already-deleted temp path.
- Deferred: offering to open a newly unblocked Target when its dependency finishes.
- Deferred: tmux backend.
