# opencode

Pinned to **opencode v2 (verified on v2.2.6)**. v1 plugins do not run on v2 and are
not supported; the v2 hook API is days old, so re-verify after an upgrade.

opencode is registered by manifest like the other harnesses and has both faces:
**delivery** (an interactive session gets memory injection through a JS plugin; the
infra guard enforces in executor runs, see [Security model](#security-model)) and **execute** (`executor.sh` delegates runs to `opencode run`, typically on a
non-Anthropic model).

## Delivery — the `ai-memory` plugin

`harnesses/opencode/plugin/ai-memory.ts` is a thin v2 plugin (no memory logic). It runs bash
scripts built on the shared `content-core.sh` + `formatters/xml.sh`, so the payload is the
same `<memory:*>` tree Claude gets. JSON on stdin: `context.sh` gets only
`{directory, sessionID}`; `guard.sh` gets the `execute.before` event's fields flattened
(`tool`, `sessionID`, `agent`, `input`) plus `directory`, with no `event` key. The scripts
are resolved from `MEMORY_DIR`, not read from the manifest.

| hook | script | effect |
|------|--------|--------|
| `session` `context` | `hooks/context.sh` | stdout pushed onto `event.system` |
| `tool` `execute.before` | `scripts/hooks/guard.sh` (`AI_MEMORY_GUARD_OUTPUT=opencode`) | deny throws; only that call fails and the model sees the message |

**Full payload on every model call.** opencode rebuilds `event.system` for each model
call and pushes do not persist, so there is no per-session counter and no breadcrumb:
`context.sh` emits the full tree every time (about 26-29KB per call, depending on the
project). That makes post-compaction recovery automatic, so no `compaction` hook is
registered. A build failure or no active project emits nothing and exits 0.

The installer does **not** write `~/.config/opencode/AGENTS.md`: it is a hand-owned static
base (Codex model); the per-call injection already carries identity and doctrine. The
active project is resolved from the `directory` the plugin supplies, via
`.agents/memory-project` as everywhere else.

## Install

```bash
install.sh --harness opencode     # or auto-detected when `opencode` is on PATH or at `~/.opencode/bin/opencode`
```

| link | target |
|------|--------|
| `~/.config/opencode/plugins/ai-memory.ts` | `harnesses/opencode/plugin/ai-memory.ts` (v2 auto-loads the dir; no config edit) |
| `~/.config/opencode/agents/ai-memory-explore.md` | `harnesses/opencode/agents/ai-memory-explore.md` |
| `~/.config/opencode/commands/*.md` | `commands/*.md` (one symlink each; native slash commands) |
| `~/.agents/skills/*` | bundled skills |

Slash commands expand only in the TUI and the API; `opencode run "/x"` sends the literal
text. `~/.agents/skills` may also hold command-skills installed by other harnesses
(codex, copilot, antigravity) or by an earlier opencode install, so a command can appear
both as a slash command and as a skill. This duplication is accepted. With no other
`commands = skill` harness installed, those copies are frozen: delete the
`~/.agents/skills/<name>` dirs that contain `.from-command`. Re-run
`install.sh --harness opencode` to create the commands directory on an existing install.

The installer prints, and never applies, this line for your shell rc:

```bash
export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1
```

Without it opencode lists skills twice, from `~/.claude/skills` and `~/.agents/skills`.
There is no config-level switch, and the variable disables the whole `.claude` config
source, not only skills. The executor wrapper exports it for you.

Auto-detection runs in the order claude, codex, antigravity, copilot, opencode, ...
(`install.sh` `detect_harness`) and takes the first match, so another detected harness wins;
pass `--harness opencode` explicitly.

**Interactive caveat.** `opencode run` (non-standalone) and the TUI go through a shared
background service that keeps the plugins it started with. After installing, restart it
(`opencode service restart`, or quit the TUI) before expecting injection in an interactive
session.

**Verified on v2.2.6:** after `opencode service restart`, the background service and the TUI
load global plugins from `~/.config/opencode/plugins/`, the same as `--standalone`. To check,
start opencode: a session should quote the active project.

## Execute — `opencode-mem.sh`

```
exec_cmd          = opencode-mem.sh run --auto {prompt}
exec_readonly     = opencode-mem.sh run --agent ai-memory-explore {prompt}
exec_model_flag   = -m {model}
exec_last_message = --last-message {file}
exec_probe_cmd    = opencode-mem.sh --probe
```

The wrapper resolves the binary (`PATH`, else `~/.opencode/bin/opencode`), exports the
skills switch, forces `--standalone`, and with `--last-message` runs `--format json` and
writes only the last assistant text. It exits non-zero on a non-zero opencode exit, an
`error` event, a malformed stream or empty final text, leaving the file empty.

### Executor config

Select opencode per role, with the provider/model after the first colon:

```bash
export AI_MEMORY_EXECUTOR_TASK=opencode:openai/gpt-4.1-mini
export AI_MEMORY_EXECUTOR_EXPLORE=opencode:openai/gpt-4.1-mini
export AI_MEMORY_EXECUTOR_VALIDATE=opencode:openai/gpt-4.1-mini
# a model id containing a colon is passed through whole:
export AI_MEMORY_EXECUTOR_TASK=opencode:openrouter/anthropic/claude-3.5-sonnet:beta

executor.sh --role task --which                 # cli:opencode
executor.sh --role task --run --clean "<prompt>"  # final message only
```

There is no `exec_validate`: the validate role reuses the read-only `ai-memory-explore`
agent, so it cannot run code (use another plane for validators that must).

## Security model

- **Who is guarded.** `guard.sh` exits with allow unless `AI_MEMORY_ROLE` is set or
  `AI_MEMORY_GUARD_SCOPE=all`. Interactive sessions get injection only;
  the guard enforces in executor runs, where `executor.sh` sets the role. To opt an
  interactive session in, export `AI_MEMORY_GUARD_SCOPE=all` before starting opencode or
  its service. Under that scope deny-listed commands are denied outright: opencode has no
  ask path, so the `ask` and `permission_mode` handling is Claude-only.
- **`--standalone` is forced** so the guard plugin loads in a private server; the shared
  service may not have it. Under `--auto` the guard is the only stop.
- **Global plugin registration is required.** The wrapper refuses a `run` unless
  `${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-~/.config}/opencode}/plugins/ai-memory.ts` resolves
  to this repo's plugin. A project-local plugin is refused: a session move leaves its
  directory, and the guard with it. There is no override.
- **Code Mode is off.** The wrapper merges `permission.execute: deny` into
  `OPENCODE_CONFIG_CONTENT` (a caller value must be exactly one JSON object) and the
  explore agent denies `execute` too. Code Mode would run JS that calls other tools in-process.
- **Guard coverage** (`guard.sh`, all roles):
  - the shared deny-list (`scripts/deny-list.txt`) on the `shell` tool's `input.command`;
  - protected paths (`scripts/protected-paths.txt`, including the opencode plugin and
    agents dirs) on `write`, `edit`, `patch` (`patchText`), `experimental_image_generate`
    and shell `workdir`;
  - role tool policy: `explore`/`validate` pass only `read glob grep webfetch websearch
    skill question`; everything else, including MCP tools, is denied;
  - denied tool families for every role: `execute`, `opencode_session_*`,
    `opencode_worktree_*`, `opencode_artifact_*`, `opencode_schedule_*` and subagent tools.
  - the agent file also denies `edit`, `bash` and `execute` natively, independent of the guard;
    that native permission does not cover `experimental_image_generate`, so the guard is the layer that stops it.
- **Fail closed.** The guard denies on spawn error, timeout (15s, `AI_MEMORY_PLUGIN_TIMEOUT_MS`),
  non-zero exit, or output that is not a JSON object with `decision: allow|deny`; unparseable
  input or a missing tool name is denied. Injection fails open (no injection, logged).
- **Accepted risks** (user-approved):
  - shell-interpreter writes (`python3 -c ... write_text`) to protected paths pass the
    guard; the shared `path-match.sh` is string matching, not a sandbox (same on Claude/Codex);
  - a non-default `OPENCODE_CONFIG_DIR`/`XDG_CONFIG_HOME` dir is unprotected, so a task run
    can plant a plugin there;
  - the TUI `write_terminal` tool would bypass the deny-list; executor runs cannot reach it
    (`--standalone`, no TUI);
  - the guard falls back to its own cwd when an event lacks `directory`; the plugin always supplies it.

## Troubleshooting

- **`opencode-mem: refusing to run: the ai-memory guard plugin is not installed ...`** The
  global symlink is missing or points elsewhere. Run `install.sh --harness opencode`, and
  check `OPENCODE_CONFIG_DIR`/`XDG_CONFIG_HOME` match where it was installed.
- **`Agent not found: ai-memory-explore`** The agent link is missing, or the file used the
  wrong frontmatter (v2 needs singular `permission:`; an object-form `permissions:` silently
  drops the agent). Re-run the installer.
- **No memory in an interactive session.** The background service is stale and
  predates the install; restart it (`opencode service restart`). The interactive guard is off
  by default (see Security model). Executor runs are unaffected (`--standalone`).
- **Skills listed twice.** Add the `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` export.
