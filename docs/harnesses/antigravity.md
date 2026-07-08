# Antigravity CLI (`agy`)

Antigravity is the headline third-party harness: registered once, as a manifest,
it works as **both** an install target and an executor with no Antigravity-specific
engine code beyond a thin hook I/O adapter. It is a **`hook` archetype** — memory
is injected **live, per model call**, the same live-refresh model as Claude's
`UserPromptSubmit`, not materialized into a file. It is also the second harness
with *enforced* guardrails after codex execpolicy.

The CLI binary is `agy` (v1.0.16 at `~/.local/bin/agy`); headless is `agy -p
"<prompt>"`, with `--model` and `--dangerously-skip-permissions`.

## Daily use

```bash
# Instead of `agy` (resolves the active project + exports it for the hook):
~/.claude-memory/harnesses/antigravity/scripts/agy.sh

# Alias it:
alias agy='~/.claude-memory/harnesses/antigravity/scripts/agy.sh'

# Arguments pass through:
agy -p "what does our terraform domain file say?"
```

## How injection works — the `PreInvocation` hook

Antigravity discovers **lifecycle hooks** from a `hooks.json` at its global
customization root, `~/.gemini/config/`. `install.sh --harness antigravity`
registers two namespaced entries there:

| key | event | script | effect |
|-----|-------|--------|--------|
| `ai-memory-inject` | `PreInvocation` | `hooks/preinvocation.sh` | inject project memory before each model call |
| `ai-memory-guard` | `PreToolUse` (matcher `*`) | `hooks/pretooluse.sh` | executor-only enforcement (see below) |

`preinvocation.sh` emits Antigravity's `injectSteps` envelope (an
`ephemeralMessage`) built from the **shared** `content-core.sh` selection +
`formatters/xml.sh` — byte-for-byte the same `<memory:*>` payload Claude injects:

- **`invocationNum == 0`** (0-based — the first model call of a session) → the
  **full** payload: `<memory:identity>` + `<memory:project>` + `<memory:index>` +
  `<memory:working>`.
- **later invocations** → the lightweight `<memory:active>` **breadcrumb** (project
  pointer + absolute memory paths + a re-read directive).
- **no active project** → `{"injectSteps":[]}` — the memory system stays dormant
  (generic `agy`) until a repo is onboarded with `/pin`.

Because the hook re-reads content every call, editing `working.md` mid-session
surfaces on the next model turn — no relaunch.

### Why the launch wrapper exports the project

Antigravity's hook payload carries **no workspace handle** — `workspacePaths` is
empty and the hook's cwd is the config dir, in every session (verified live). So
the active project cannot be resolved from the payload. Instead `agy.sh` resolves
it from `$PWD` **at launch** and exports it into agy's environment, which the hook
inherits and reads:

```
export MEMORY_DIR
export AI_MEMORY_PROJECT="$(detect_active_project)"   # walks up to .agents/memory-project
export AI_MEMORY_CWD="$PWD"
exec agy "$@"
```

An `agy` session is single-workspace for its lifetime, so launch-time resolution
is equivalent to per-invocation — and env-scoping per process sidesteps the
global-single-file clobber a materialized `~/.gemini/config/AGENTS.md` would have.

## Static base — your permanent Antigravity instructions

Antigravity has **no `AGENTS.local.md`**. The static, always-on workflow-rules base
(the `~/.claude/CLAUDE.md` analogue) is a **hand-owned** `~/.gemini/config/AGENTS.md`
— agy reads `AGENTS.md`/`GEMINI.md` by walking up from cwd, and honors this global
one for every session. The memory system **never writes it**; the dynamic
per-project memory lives entirely in the hook.

```bash
echo "Always run 'just lint' before suggesting commit messages." >> ~/.gemini/config/AGENTS.md
```

## Enforcement — the `PreToolUse` guard

`pretooluse.sh` is registered globally but **self-gates on `AI_MEMORY_ROLE`**,
which `executor.sh` sets only for a delegation. Interactive `agy` (no role) is
**unguarded** — the human decides. For a delegation it applies two layers:

1. **Deny-list (both roles).** A tool whose shell `CommandLine` matches the shared
   `scripts/deny-list.txt` — `terraform`/`kubectl apply`, `terraform destroy`,
   `kubectl delete`, `gh`/`bkt` `pr merge`, `az repos pr update`, `helm
   install`/`upgrade` — is hard-blocked (`{"decision":"deny"}`). The O/E/V "never
   apply/merge to running infra" rule, **enforced** rather than only restated in
   the prompt.
2. **Read-only (explore/validate roles).** Only a read-tool **allowlist** is permitted
   (`view_file`, `grep_search`, `code_search`, `list_dir`, `read_url_content`, …);
   `run_command` and every write tool are denied. It's an *allowlist*, not
   deny-by-name, because Antigravity's live `toolCall.name` drifts from the
   doc-derived names (`list_dir`, not `list_directory`) — allowing by name **fails
   safe**.

The deny-list is a **shared shipped artifact** (`scripts/deny-list.txt`), read by
the guard — seeding a future manifest `guard` capability so any hook-capable
harness can plug the same list into its native gate.

## The executor face

The same manifest that installs Antigravity declares its `execute` face:

```
exec_cmd        = $MEMORY_DIR/harnesses/antigravity/scripts/agy.sh -p {prompt} --dangerously-skip-permissions
exec_readonly   = $MEMORY_DIR/harnesses/antigravity/scripts/agy.sh -p {prompt} --dangerously-skip-permissions
exec_model_flag = --model {model}
exec_probe      = agy
```

Select it per role with `AI_MEMORY_EXECUTOR_TASK` / `AI_MEMORY_EXECUTOR_EXPLORE` /
`AI_MEMORY_EXECUTOR_VALIDATE` (see [Workflow › Executor selection](../workflow.md#executor-selection));
`executor.sh` substitutes `{prompt}`/`{model}`, exports `AI_MEMORY_ROLE`, and runs
it headless.

**Read-only is real now.** `agy -p` has no read-only CLI flag, so `exec_readonly`
is the *same* command — the read-only guarantee comes from the `PreToolUse` guard
denying every non-read tool when `AI_MEMORY_ROLE` is `explore` **or** `validate`. So
Antigravity is a genuine read-only executor for both roles, not degrading to the
Claude `Explore`/subagent plane. (Enforcement requires the guard installed — i.e.
`install.sh --harness antigravity` registered the hooks.json entries.)

## Skills and commands — the `.agents/` namespace

Antigravity natively discovers the cross-agent `.agents/` namespace, so both skills
and slash commands reach it with no adapter:

- **Skills** — `skills/<name>/SKILL.md` here is byte-identical to Antigravity's own
  layout, so fan-out is a zero-transform symlink into the shared `~/.agents/skills`
  (Antigravity is registered in `~/.agents/.skill-lock.json`).
- **Commands** — the manifest declares `commands = skill`, so each canonical
  slash-command body under `harnesses/claude/commands/` is wrapped as a `SKILL.md`
  into the same `~/.agents/skills` (Antigravity's command mechanism *is* skills).

Because both land in `~/.agents/skills`, the exact same store is shared with Codex.

## Statusline

`install.sh --harness antigravity` also registers a **memory-aware statusline**
(`harnesses/antigravity/statusline.sh`). agy renders `settings.json → statusLine.command`
each frame, piping a JSON payload on stdin (`agent_state`, `model.display_name`,
`context_window.used_percentage`, `vcs.branch`/`dirty`, `sandbox`, `subagents`, `task_count`,
`terminal_width`); the script prints the formatted line. Registration is an idempotent merge
into `~/.gemini/antigravity-cli/settings.json` that **preserves** existing keys
(`colorScheme`, `trustedWorkspaces`, …):

```json
{ "statusLine": { "type": "", "command": "bash …/harnesses/antigravity/statusline.sh", "enabled": true } }
```

It surfaces, left→right: the **memory project** — resolved from `AI_MEMORY_PROJECT`
(exported by `agy.sh`), else by walking up `$PWD` for `.agents/memory-project`; the **folder**; git **branch** (+dirty); **model**; a **context-window %** bar; and **agent state**
(+subagent/task counts). It's **responsive** (wide single-line / medium two-line / narrow
compact) and never crashes the CLI (jq-optional, defaults on error).

- **Emoji glyphs by default** (🧠 project · 📁 folder · 🌿 branch — the same set Claude's statusline
  uses, so they render in any terminal). Set `USE_NERD_FONTS=true` for Nerd Font icons instead (needs a
  Nerd Font installed, else they show as boxes).
- Toggle it in-CLI with `/statusline on|off`. The memory project shows as **dormant** outside a
  pinned repo (or when launched without the `agy.sh` wrapper, which is what exports the project).

## Adding a new domain topic

Drop `domain/<topic>.md` with `topic` / `triggers` / `summary` frontmatter. The
`<memory:index>` block (injected live) carries the new Domain Index row on the next
model call — agy reads the file on demand when a request matches the triggers. No
code change, no relaunch.
