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

## Concurrent features — git worktrees

Antigravity has no in-session worktree switch, but the single-workspace-per-session
model composes with git worktrees for isolating concurrent features:

1. `git worktree add ../<repo>-<feature> -b <feature>` — a second checkout on its own branch.
2. **Open that directory as a workspace** (Agent Manager → "Open Workspace"); `agy.sh` exports
   `AI_MEMORY_CWD="$PWD"` at launch, so the worktree becomes the session's resolved cwd.

Because `preinvocation.sh` reads `AI_MEMORY_CWD`, the injected memory then routes to
`working.<worktree-name>.md` — the [per-worktree overlay](../file-formats.md#per-worktree-overlays-workingkeymd) —
with no extra config; the other workspace's `working.md` is untouched. This process is
regression-tested (`scripts/tests/test_worktree_feature_process.sh`).

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
   `scripts/deny-list.txt` — `terraform apply`/`destroy`, `kubectl apply`/`delete`,
   `gh`/`bkt` `pr merge`, `az repos pr update`, `helm install`/`upgrade`/`uninstall`/`delete`
   — is hard-blocked (`{"decision":"deny"}`). The O/E/V "never apply/merge to running
   infra" rule, **enforced** rather than only restated in the prompt.

   Matching lives in `scripts/deny-match.sh`. A spec is `<binary> <subcommand…>`, and
   the matcher **tokenizes** rather than substring-matching. Per command segment it
   strips `VAR=val` assignments and transparent exec-wrappers (`sudo`, `env`, `timeout`,
   `nice`, `flock`, `xargs`, `setsid`, `stdbuf`, …), takes the binary's basename, drops
   flag tokens, and looks for the spec's subcommands as a consecutive run. That catches
   `terraform -chdir=envs/prod apply` and `kubectl -n foo delete pod x` — an interposed
   flag used to defeat the old regex — and `timeout 5 terraform apply`, where the wrapper
   hides the binary. After a wrapper the binary's position is unreliable (`sudo -u root
   kubectl …` puts a flag *value* at the head), so the tail is scanned instead.

   Segments split on `&&`, `||`, `;`, `|`, newline, **a lone `&`** (`sleep 1 & terraform
   apply` backgrounds `sleep` and runs terraform), and subshell/brace punctuation
   (`( … )`, `{ …; }`). Compound-statement leaders (`then`, `do`, `else`, …) are skipped,
   so `if true; then terraform apply; fi` is caught. After a wrapper whose flag takes a
   value (`timeout 5 …`, `sudo -u root …`) the tail is scanned for a payload-bearing binary,
   so `timeout 5 sh -c "terraform apply"` is caught; and a wrapper's own `-c` command flag
   is followed (`flock <lock> -c "terraform apply"`, the serialized-infra idiom). It recurses into shell re-entry
   (`sh -c`, `bash -lc`, glued `-c"…"`, `bash <<< "…"`, `eval`, `trap`, and
   `su`/`runuser` `-c` — whose *only* idiom is `-c`, so they are payload binaries, not
   plain wrappers) and into substitutions (`$(…)`, backticks, `<(…)`), with a depth cap
   that **denies** when hit.

   Quote state models the shell. Single quotes suppress substitution, so
   `echo '$(terraform apply)'` is **allowed** — the shell prints it, it does not run it —
   while `echo "$(terraform apply)"` is denied. Inside double quotes an apostrophe is a
   literal, so `echo "it's $(terraform apply)"` is **denied**: a contraction must not mask
   a live substitution. `find` executes only what follows `-exec`/`-execdir`/`-ok`, never
   a `-name` value.

   False positives are a real failure mode: a deny-list that blocks legitimate work
   (`grep -r "terraform apply" docs/`, `git commit -m "kubectl delete"`,
   `find . -name terraform -o -name apply`) gets switched off, and then it protects nothing.

   Consequence worth knowing: `echo terraform apply` is **allowed** — the binary is
   `echo`. The pre-2026-07-09 substring regex denied it. Deliberate: an ungated substring
   match would also deny `git commit -m "kubectl delete"`.
2. **Read-only (explore/validate roles).** Only a read-tool **allowlist** is permitted
   (`view_file`, `grep_search`, `code_search`, `list_dir`, `read_url_content`, …);
   `run_command` and every write tool are denied. It's an *allowlist*, not
   deny-by-name, because Antigravity's live `toolCall.name` drifts from the
   doc-derived names (`list_dir`, not `list_directory`) — allowing by name **fails
   safe**.

The deny-list is a **shared shipped artifact** (`scripts/deny-list.txt`), read by
the guard — seeding a future manifest `guard` capability so any hook-capable
harness can plug the same list into its native gate.

**It fails closed.** Under a delegation (`AI_MEMORY_ROLE` set) the guard denies when
there is no JSON parser (`jq`/`python3`) to inspect the tool call with, and when
`scripts/deny-list.txt` is missing **or contains no rules** — an absent *or truncated*
rules file is indistinguishable from a disarmed guard, and `: > deny-list.txt` disarms
exactly as well as `rm` does. All these checks sit *after* the role gate, so an
interactive `agy` on a machine without `jq` is unaffected.

**Customising it without bricking sync.** `scripts/deny-list.txt` holds the tracked
defaults and **must never be hand-edited on an installed instance**: a modified tracked
file makes `sync-system.sh:dirty_tracked_guard` refuse to sync (the same trap that
[`identity.md` used to set](../../UPGRADING.md)). Add instance rules to the gitignored
`scripts/deny-list.local.txt`, which the guard concatenates. It is **additive only** —
there is no un-deny syntax, and a leading `-` is just an ordinary entry. Keeping the
defaults tracked is what lets a new rule (e.g. `helm uninstall`) reach every instance on
the next sync; a seed-from-`.example` design would freeze each instance's copy forever.

A deny-list is a **backstop, not a sandbox.** It matches command text, so a determined
process can still obfuscate (base64, a script file, a wrapper binary). Its job is to stop
an honest agent from doing the obviously-forbidden thing. The destructive-class floor for
`codex` remains its execpolicy; Claude subagents get the list restated in the prompt only.

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
