# Codex CLI

Codex has no native memory hook. The bridge is `harnesses/codex/scripts/codex-mem.sh`, a wrapper that rebuilds `~/.codex/AGENTS.md` from the memory tree (via the shared `scripts/build-context-md.sh`) and then `exec codex "$@"`. At install (`install.sh --harness codex`) the bundled skills **and** the slash-commands-as-skills fan into the cross-agent `~/.agents/skills` (Codex's command mechanism is skills).

## Daily use

```bash
# Instead of `codex`:
~/.claude-memory/harnesses/codex/scripts/codex-mem.sh

# Or alias it:
alias codex='~/.claude-memory/harnesses/codex/scripts/codex-mem.sh'

# Subcommands pass through:
codex-mem.sh exec --sandbox read-only "what does our terraform domain file say?"
codex-mem.sh review
```

## What lands in `~/.codex/AGENTS.md`

Built fresh on every invocation, in this order:

1. **`# === IDENTITY ===`** — `identity.md` verbatim.
2. **`# === PROJECT: <name> ===`** — `projects/<active>/memory.md`.
3. **`# === MEMORY INDEX ===`** — `index.md` (lifecycle prose + auto-generated catalog).
4. **`# === DOMAIN INDEX ===`** — table synthesized from frontmatter in each `domain/*.md` (file path, triggers, summary), with a lazy-load instruction: Codex reads the file with its shell tool when the user's request matches a topic's triggers.
5. **`# === WORKING MEMORY ===`** — `projects/<active>/working.md` if non-empty.
6. **`# === LOCAL OVERLAY ===`** — `~/.codex/AGENTS.local.md` if present.

## Local overlay — your permanent Codex instructions

`~/.codex/AGENTS.local.md` is **never** touched by the script. Edit it freely; it's concatenated at the bottom of the generated file every time. The Codex analogue of `~/.claude/CLAUDE.md`.

```bash
echo "Always run 'just lint' before suggesting commit messages." >> ~/.codex/AGENTS.local.md
```

## `/checkpoint` inside Codex

Captures the session into `projects/<active>/working.md`. Two trigger surfaces, same behavior:

- **Explicit slash command** — `~/.codex/prompts/checkpoint.md`. Type `/checkpoint` in the Codex TUI.
- **Autonomous skill** — `~/.codex/skills/checkpoint/SKILL.md`. Codex invokes the skill itself when the session is winding down or you say things like *"save state"*, *"let's pause here"*, *"before I close"*. Discovered via the SKILL's `description` field.

Either path runs:

1. `harnesses/codex/scripts/codex-mem-checkpoint.sh --for-codex` (prints active project, `working.md` path, recent-history snippet, scaffold).
2. Synthesizes Task/Done/Next/Blockers from this session's context (no questions asked).
3. Appends a `### YYYY-MM-DD — <task>` block at the end of `## Checkpoints` in `working.md` (newest last; prior entries preserved).
4. If applicable, appends a bullet to `## Cross-project learnings (pending promotion)`.

Net effect: typing `/checkpoint` or simply ending a session with "let's save state" captures the work back into memory. Same memory is visible to Claude next session.

## Concurrent features — git worktrees

Codex has no in-session worktree switch (Claude's `EnterWorktree`), but the memory system still isolates concurrent features per worktree. The process is manual and one-time:

1. `git worktree add ../<repo>-<feature> -b <feature>` — a second checkout on its own branch.
2. `cd ../<repo>-<feature> && codex` — launch Codex **in** the worktree.

Because Codex resolves the project and builds `AGENTS.md` from `$PWD`, launching inside the worktree routes both the injected context *and* `/checkpoint` to `working.<worktree-name>.md` — the [per-worktree overlay](../file-formats.md#per-worktree-overlays-workingkeymd) — with no config. The other checkout's `working.md` is untouched. (First-class `--worktree`/`--tmux` flags are only a proposed Codex feature; until then, the manual `git worktree add` above is the flow.) This process is regression-tested end-to-end (`scripts/tests/test_worktree_feature_process.sh`).

## Adding a new domain topic (Codex picks it up automatically)

1. Drop a new file `domain/postgres.md` with frontmatter:

   ```yaml
   ---
   topic: postgres
   triggers: [pg, postgres, psql, plpgsql]
   summary: Postgres conventions, indexing rules, migration patterns
   ---
   ```

2. Next `codex-mem.sh` invocation regenerates `AGENTS.md` with a new row in the Domain Index.
3. No code change. Codex sees it on the next session.

## Standalone `codex-mem-checkpoint.sh`

Outside a Codex session — useful after exiting Codex while a session insight is still fresh:

```bash
~/.claude-memory/harnesses/codex/scripts/codex-mem-checkpoint.sh
```

Opens `$EDITOR` on `working.md` with a checkpoint scaffold appended. Fill in done/next/blockers, save, done.
