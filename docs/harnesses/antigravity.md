# Antigravity CLI (`agy`)

Antigravity is the headline third-party harness: it was registered once, as a
manifest, and works as **both** an install target and a task-role executor with no
Antigravity-specific engine code. Like Codex it has no native memory hook — the
bridge is `harnesses/antigravity/scripts/agy.sh`, a launch wrapper that rebuilds
`~/.gemini/config/AGENTS.md` from the memory tree (via the shared
`scripts/build-context-md.sh`) and then `exec agy "$@"`.

The CLI binary is `agy` (v1.0.16 at `~/.local/bin/agy`); headless is `agy -p
"<prompt>"`, with `--model` and `--dangerously-skip-permissions`.

## Daily use

```bash
# Instead of `agy`:
~/.claude-memory/harnesses/antigravity/scripts/agy.sh

# Or alias it:
alias agy='~/.claude-memory/harnesses/antigravity/scripts/agy.sh'

# Arguments pass through:
agy -p "what does our terraform domain file say?"
```

## What lands in `~/.gemini/config/AGENTS.md`

Built fresh on every launch by the shared `build-context-md.sh` (label `agy`) —
the same builder and section order Codex uses:

1. **`# === IDENTITY ===`** — `identity.md` verbatim.
2. **`# === PROJECT: <name> ===`** — `projects/<active>/memory.md`.
3. **`# === MEMORY INDEX ===`** — `index.md` (lifecycle prose + auto-generated catalog).
4. **`# === DOMAIN INDEX ===`** — table synthesized from each `domain/*.md` frontmatter (path, triggers, summary), with a lazy-load instruction: Antigravity reads the file when the request matches a topic's triggers.
5. **`# === WORKING MEMORY ===`** — `projects/<active>/working.md` if non-empty.
6. **`# === LOCAL OVERLAY ===`** — `~/.gemini/config/AGENTS.local.md` if present.

The target is a **best-guess global path**: Antigravity reads `GEMINI.md` /
`AGENTS.md` by walking up from `$PWD` to the repo root, and honors the
machine-local `~/.gemini/config/`. If a live `agy` session turns out to read a
different global path, it's a one-line fix in the manifest (`context_target`).

## Local overlay — your permanent Antigravity instructions

`~/.gemini/config/AGENTS.local.md` is **never** touched by the wrapper. Edit it
freely; it's concatenated at the bottom of the generated file every launch. The
Antigravity analogue of `~/.claude/CLAUDE.md` / `~/.codex/AGENTS.local.md`.

```bash
echo "Always run 'just lint' before suggesting commit messages." >> ~/.gemini/config/AGENTS.local.md
```

## Skills and commands — the `.agents/` namespace

Antigravity natively discovers the cross-agent `.agents/` namespace, so both
skills and slash commands reach it with no adapter:

- **Skills** — `skills/<name>/SKILL.md` in this repo is byte-identical to
  Antigravity's own layout, so fan-out is a zero-transform symlink. At install
  time `scripts/link-skills.sh` links the store into the shared
  `~/.agents/skills` (Antigravity is registered in `~/.agents/.skill-lock.json`).
- **Commands** — the manifest declares `commands = skill`, so each canonical
  slash-command body under `harnesses/claude/commands/` is wrapped into a
  `SKILL.md` and fanned into the same `~/.agents/skills` by
  `scripts/link-command-skills.sh`. Antigravity's command mechanism *is* skills,
  so `/checkpoint`, `/pin`, etc. surface as invocable skills rather than native
  slash commands.

Because both land in `~/.agents/skills`, the exact same store is shared with
Codex — install either harness and both agents see the same skills + commands.

## The executor face

Antigravity is also a **task-role executor** — the same manifest that installs it
declares its `execute` face:

```
exec_cmd        = agy -p {prompt} --dangerously-skip-permissions
exec_model_flag = --model {model}
```

Select it with `AI_MEMORY_EXECUTOR` (see [Workflow › Executor
selection](../workflow.md#executor-selection)); `executor.sh` substitutes
`{prompt}` / `{model}` and runs it headless.

**Read-only caveat.** `agy -p` is write-capable and has **no clean read-only
flag**, so `exec_readonly` is intentionally omitted from the manifest —
Antigravity is a **task-role executor only**. Read-only exploration degrades to
the Claude `Explore` agent instead. (A future `PreToolUse` `hooks.json` guard
could add enforced read-only.) The infra deny-list still applies: it is restated
in every delegation prompt regardless of executor.

## Adding a new domain topic

Same as every `file`-archetype harness: drop `domain/<topic>.md` with `topic` /
`triggers` / `summary` frontmatter, and the next `agy.sh` launch regenerates
`AGENTS.md` with a new Domain Index row. No code change.
