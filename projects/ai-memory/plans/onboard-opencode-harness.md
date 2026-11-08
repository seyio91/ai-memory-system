---
plan: onboard-opencode-harness
status: in_progress
created: 2026-11-08
owner: claude (orchestrator)
task_provider: notion
task_ref: 412f6850-c619-81ff-a335-ca806e667dfd
---

# Plan — Onboard opencode as a harness

## Goal
Register opencode v2 as a fifth harness with both faces: interactive sessions get a static AGENTS.md base plus live memory injection, compaction re-arm and the infra guard through a thin JS plugin; `executor.sh` can delegate task/explore/validate runs to `opencode run` with clean final-message output.

**Before:** opencode sessions see no memory; `executor.sh` cannot target opencode; the install engine has no way to register a JS plugin.
**After:** `install.sh --harness opencode` writes `~/.config/opencode/AGENTS.md`, links the `ai-memory` plugin and the `ai-memory-explore` agent, and fans skills into `~/.agents/skills`; an opencode session receives the `<memory:*>` payload and has deny-listed shell commands rejected; `executor.sh --run --clean` on opencode emits only the final agent message.

## Non-goals
- No opencode v1 support (v1 plugins do not run on v2).
- No statusline (v2 has no custom statusline hook).
- No native slash commands — commands arrive as skills.
- No scratch-writable validate mode — the validate role reuses the explore agent.
- The installer never edits the user's shell rc.

## Success criteria
- R1 [acceptance] `scripts/validate-manifest.sh harnesses/opencode/manifest` passes; a manifest with `plugins_dir` but no `plugin_file` is rejected (`test_validate_manifest.sh`).
- R2 [acceptance] `install.sh --harness opencode` under a sandbox `HOME` writes the static base to `~/.config/opencode/AGENTS.md`, symlinks the plugin into `~/.config/opencode/plugins/`, installs `ai-memory-explore.md` into `~/.config/opencode/agents/`, fans skills into `~/.agents/skills`, and prints the `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` export line; a second run changes nothing (`test_install_harness.sh`).
- R3 [acceptance] Fixture-driven hook tests over P1's captured payloads: first `context` call of a session emits the full payload ending in `<memory:working>`, later calls emit the breadcrumb, a `compaction` event arms one full re-injection; each assertion mutation-checked.
- R4 [acceptance] `guard.sh` with `AI_MEMORY_GUARD_OUTPUT=opencode` denies a deny-listed command in the `shell` tool's `input.command`, denies non-read tools under `AI_MEMORY_ROLE=explore`, allows a read; mutation-checked.
- R5 [acceptance] `opencode-mem.sh --last-message <file>` writes only the last assistant text from a `--format json` fixture and propagates the CLI exit code; with opencode configured as executor, `executor.sh --role task --which` prints `cli:opencode` and `--run --clean` emits only the final message.
- R6 [acceptance] Live on an installed opencode v2: a session quotes the active project from injected memory; a deny-listed shell command is rejected and the rejection reaches the model; an `--role explore` run cannot create a file. Evidence: transcript excerpts in the validator report.
- R7 [parity] `bash scripts/run-tests.sh` full run green, and every pre-existing harness test passes unchanged vs `origin/main`.
- R8 [acceptance] `docs/harnesses/opencode.md` exists and is linked from `README.md` and `adding-a-harness.md`; `bash scripts/check-docs.sh` passes; `changelog.d/onboard-opencode-harness.feature.md` exists.

## Design
Copies Codex's shape: `archetype = file` + `context_target = ~/.config/opencode/AGENTS.md` (static base: identity + doctrine) + `refresh = hook` for live injection. `format = xml`.

- **Registration:** new manifest keys `plugins_dir` + `plugin_file`; `scripts/drivers/hook.sh` gains a branch that symlinks `plugin_file` into `plugins_dir` idempotently (v2 auto-loads the plugin dir, no config edit). `validate-manifest.sh`: keys in `KNOWN_KEYS`, `plugins_dir` requires `plugin_file`. `install.sh` `detect_harness`: `command -v opencode`.
- **Plugin (`harnesses/opencode/plugin/ai-memory.ts`):** v2 `Plugin.define`; no memory logic. Pipes `{directory, sessionID, event}` JSON on stdin to bash scripts built on `content-core.sh` + `formatters/xml.sh`:
  - `session.hook("context")` → `hook_script`; stdout pushed onto `event.system`; full payload first call per session, breadcrumb after (per-session counter, as antigravity).
  - `session.hook("compaction")` → `arm_script`; next `context` call re-injects full.
  - `tool` `execute.before` → `guard_script` (`guard.sh`, new `AI_MEMORY_GUARD_OUTPUT=opencode` mode); deny → plugin throws, failing that call only.
  - Session-created event → `session_script` if P1 confirms the event; else the `context` counter covers bootstrap.
  - Script failure: injection degrades to nothing (logged); guard failure denies (fail closed).
- **Skills:** `skills_dir = ~/.agents/skills`, `commands = skill`. `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` prevents the double listing from `~/.claude/skills`: exported by the wrapper for executor runs; printed by the installer for interactive shells unless P1 finds a config-level switch.
- **Execute face:** `harnesses/opencode/scripts/opencode-mem.sh` — probe binary, export the skills switch, accept `--last-message {file}` (runs `--format json`, writes the last assistant text, propagates exit). Manifest: `exec_cmd = opencode-mem.sh run --auto {prompt}`, `exec_readonly = opencode-mem.sh run --agent ai-memory-explore {prompt}`, `exec_model_flag = -m {model}`, `exec_last_message = --last-message {file}`, `exec_probe = opencode`; no `exec_validate` (falls back to `exec_readonly`).
- **Read-only:** `harnesses/opencode/agents/ai-memory-explore.md` (v2 `permissions`: `edit` and `shell` deny) plus the guard denying non-read tools when `AI_MEMORY_ROLE=explore`.

Rejected:
- Pure file archetype (launch wrapper, AGENTS.md only) — no in-session refresh, guard or compaction recovery.
- Plugin-only (no AGENTS.md base) — diverges from the Codex/Antigravity static-base pattern.
- Escape hatch `opencode.sh --install` — install logic outside the driver and its tests.
- Guard-only or agent-only read-only — agent-only leaves the deny-list unenforced for task runs; guard-only forgoes native enforcement.
- Raw stdout executor output — validator verdicts mixed with tool output.
- Reusing `~/.claude/skills` — couples opencode to the Claude install.
- v1 + v2 support — two plugin shapes for a legacy target.

## Security
- Task-role runs use `opencode run --auto` (approves anything not explicitly denied); the deny-list guard is the only stop, so it fails closed on script error or unparseable input.
- Plugin runs `$MEMORY_DIR` scripts with absolute paths fixed at install; no shell interpolation of event content — payload goes over stdin only.
- Explore role: two independent mechanisms (agent permissions, guard); either alone blocks writes.

## Decisions (locked)
- Target opencode v2 only; hook names per the v2 migration guide, confirmed by P1 before P2–P4 code against them.
- Commit route: `git-cli ship` for code/docs; plan/todo bookkeeping `git-cli commit --all` to `main`.
- Conventional-commit types: `feat(harness):`, `feat(install):`, `test(harness):`, `docs(harnesses):`.
- P2, P3, P4 independent after P1 (disjoint `Files touched`); P2 owns the manifest, including execute-face keys.
- **P1 findings (opencode v2.2.6, 2026-11-08; fixtures in `scripts/tests/fixtures/opencode/`):**
  - Plugin shape: `export default { id, async setup(ctx) { … } }`, no package import needed; hooks registered with `await ctx.session.hook("context"|"compaction", fn)` and `await ctx.tool.hook("execute.before", fn)`. Async hooks are awaited.
  - `context`: inject via `event.system.push({type:"text", text})`; fresh `system` array per call. Fires **per model call** (one tool call → 2 calls), so the per-`sessionID` counter is required. `compaction` payload has the same keys as `context`.
  - `execute.before`: `{tool:"shell", sessionID, agent, input:{command}}`. A thrown error fails only that call, and the model sees the message verbatim.
  - Subprocess: `node:child_process` `spawnSync(cmd, {input, encoding:"utf8"})` works.
  - Session-created: `session.created` not delivered to plugins in `run --standalone`, so bootstrap is the first `context` call per `sessionID` (no `session_script`).
  - Agent file: `agents/<name>.md`, frontmatter `permission: {edit: deny, bash: deny}` (**singular `permission`**; object-form `permissions` silently drops the agent).
  - `run --format json`: JSONL with `type` ∈ `step_start|tool_use|step_finish|text|error`; last assistant text = last `type=="text"` line `.part.text`. Exit 0 ok, 1 on provider/model error.
  - Skills: no config switch; `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` only (disables the whole `.claude` config source, not just skills).
  - Compaction is triggered by `ctx.session.compact({sessionID})`; there is no CLI trigger.
  - Unverified: whether the background service (non-`--standalone` `run`, TUI) loads plugins from the global `~/.config/opencode/plugins/`. P3/P5 must confirm live.

## Phases

### Phase 1 — Spike: verify opencode v2 hook surface
- Install opencode v2 locally; load a scratch probe plugin (outside the repo) logging every hook/event payload.
- Confirm: `context`/`compaction`/`tool execute.before` names and payloads; the session-created event name; whether `context` fires per model call or per turn; how a plugin spawns a synchronous subprocess without Bun `$`; that a thrown `execute.before` error reaches the model; `opencode run --format json` event shape; any config-level switch for Claude skills; v2 agent `permissions` syntax for `ai-memory-explore`.
- Capture real payloads as fixtures. Return findings to the orchestrator, which records them under Decisions.

**Files touched:** `scripts/tests/fixtures/opencode/*.json` (new)
**Risk:** low
**Depends:** none
**Verify:** R3, R4, R5 — fixtures exist for `context`, `compaction`, `execute.before` (shell tool) and one `run --format json` stream; each finding above returned with the command or log line proving it.

### Phase 2 — Engine: manifest, registration style, detection, install
- `harnesses/opencode/manifest` (both faces, per Design).
- `validate-manifest.sh`: `plugins_dir`, `plugin_file` in `KNOWN_KEYS`; `plugins_dir` requires `plugin_file`.
- `scripts/drivers/hook.sh`: plugin symlink branch; installs `harnesses/opencode/agents/*.md` into `agents_dir`; prints the skills-switch export line.
- `install.sh` `detect_harness`: `opencode` case.
- Tests: validate-manifest rule, sandbox install + idempotent re-run.

**Files touched:** `harnesses/opencode/manifest` (new), `harnesses/opencode/agents/ai-memory-explore.md` (new), `scripts/validate-manifest.sh`, `scripts/drivers/hook.sh`, `install.sh`, `scripts/tests/test_validate_manifest.sh`, `scripts/tests/test_install_harness.sh`
**Risk:** medium
**Depends:** Phase 1
**Verify:** R1, R2 — `bash scripts/tests/test_validate_manifest.sh` and `bash scripts/tests/test_install_harness.sh` green; sandbox-HOME install shows the four artifacts and a second run leaves the tree unchanged.

### Phase 3 — Plugin and hook scripts
- `harnesses/opencode/plugin/ai-memory.ts` per Design.
- `harnesses/opencode/hooks/{context,compaction,session}.sh` on `content-core.sh` + `formatters/xml.sh`; per-session counter; arm sentinel.
- `scripts/hooks/guard.sh`: `opencode` output mode reading `input.command` for the `shell` tool and the tool name for the explore role.
- Fixture-driven tests, mutation-checked.

**Files touched:** `harnesses/opencode/plugin/ai-memory.ts` (new), `harnesses/opencode/hooks/*.sh` (new), `scripts/hooks/guard.sh`, `scripts/tests/test_opencode_hooks.sh` (new), `scripts/tests/test_guard_paths.sh`
**Risk:** high
**Depends:** Phase 1
**Verify:** R3, R4 — `bash scripts/tests/test_opencode_hooks.sh` and `bash scripts/tests/test_guard_paths.sh` green; reverting each asserted branch makes its test fail.

### Phase 4 — Executor wrapper
- `harnesses/opencode/scripts/opencode-mem.sh`: binary probe, skills switch export, `--last-message {file}` via `--format json`, exit-code propagation.
- Executor test: `--which` resolution and `--run --clean` with a stub `opencode` on `PATH`.

**Files touched:** `harnesses/opencode/scripts/opencode-mem.sh` (new), `scripts/tests/test_opencode_executor.sh` (new)
**Risk:** medium
**Depends:** Phase 1
**Verify:** R5 — `bash scripts/tests/test_opencode_executor.sh` green; the stubbed `--run --clean` output equals the fixture's last assistant text byte for byte.

### Phase 5 — Docs, changelog, live end-to-end
- `docs/harnesses/opencode.md`; rows in `adding-a-harness.md` (new registration style), `docs/scripts.md`, `README.md`, `domain/agent-tooling.md`; `changelog.d/onboard-opencode-harness.feature.md`.
- Live run against installed opencode v2 for R6; full suite for R7.

**Files touched:** `docs/harnesses/opencode.md` (new), `docs/harnesses/adding-a-harness.md`, `docs/scripts.md`, `README.md`, `domain/agent-tooling.md`, `changelog.d/onboard-opencode-harness.feature.md` (new)
**Risk:** low
**Depends:** Phase 2, Phase 3, Phase 4
**Verify:** R6, R7, R8 — live transcript excerpts for the three R6 checks; `bash scripts/run-tests.sh` green (signing off); `bash scripts/check-docs.sh` passes.

## Risks / open questions
- v2 released 2026-11-06; hook API may still shift — P1 pins the observed version in `docs/harnesses/opencode.md`.
- Session-created event name unconfirmed (P1); fallback is counter-based bootstrap in `context`.
- `context` cadence (per model call vs per turn) decides breadcrumb volume — P1.
- Synchronous subprocess from a v2 plugin without Bun `$` — P1; if only async, hooks must await.
- Interactive sessions still list skills twice until the user adds the printed export (no rc editing) — unless P1 finds a config switch.
- No scratch-writable validator on opencode; validators that must run code use another plane.
