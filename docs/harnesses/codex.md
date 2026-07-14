# Codex CLI

Codex runs a **hybrid** memory model: a static `~/.codex/AGENTS.md` base **plus native Codex hooks** for the dynamic layer. The base is rebuilt from the memory tree on every launch by `harnesses/codex/scripts/codex-mem.sh` (via the shared `scripts/build-context-md.sh`), which then `exec codex "$@"`; the hooks (see [Native hooks](#native-hooks-hybrid) below) add live per-turn memory injection and an executor infra guard. At install (`install.sh --harness codex`) the bundled skills **and** the slash-commands-as-skills fan into the cross-agent `~/.agents/skills` (Codex's command mechanism is skills).

> **Codex has stable native hooks** (`codex features list` → `hooks`), verified against codex 0.144.1. The earlier "Codex has no native memory hook" model is retired — it is now a file+hook hybrid, not file-only.

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

## Native hooks (hybrid)

Beyond the `AGENTS.md` base, `install.sh --harness codex` writes a user-level `~/.codex/hooks.json` (Codex's own schema — a top-level `hooks` object keyed by event, distinct from Antigravity's shape) registering three roles from the manifest `[hooks]` map:

| Role | Event | Script | Effect |
|------|-------|--------|--------|
| `per_turn_inject` | `UserPromptSubmit` | shared `scripts/hooks/inject.sh` (`AI_MEMORY_HOOK_FORMAT=md`) | Live per-turn memory injection via `hookSpecificOutput.additionalContext` — so interactive Codex gets fresh active-project memory each prompt (and mid-session project switch), not just the launch-time `AGENTS.md`. |
| `infra_guard` | `PreToolUse` (matcher `^Bash$\|apply_patch`) | shared `scripts/hooks/guard.sh` | Under an executor role (`AI_MEMORY_ROLE` set), denies the shared infra deny-list via `exit 2` — Codex honors it as a tool block. Interactive sessions (no role) pass through. |
| `compaction_arm` | `SessionStart` (arms on `source=compact`) | `harnesses/codex/hooks/arm_recompact.sh` | On a compaction, writes the `<session_id>.recompact` sentinel so the next `UserPromptSubmit` re-injects the full payload through the shared `inject.sh` channel (compaction recovery). Standalone mirror of Claude's `session_start_memory.sh` compact branch. |

**Trust.** Codex hash-pins hook trust by design, so there is no install-writable auto-trust on a personal machine (`requirements.toml` is MDM-only). Interactive Codex needs a **one-time `/hooks` trust** (re-prompts only if a hook's command changes); the headless executor path (`codex-mem.sh --executor`) passes `--dangerously-bypass-hook-trust`.

**Version floor.** Hook registration is gated at install time on `codex --version ≥ hooks_min_version` (0.135.0). Below the floor, Codex falls back to the `AGENTS.md`-only file model with no error.

**Compaction recovery.** The shared `inject.sh` consumes a `.recompact` sentinel; the `compaction_arm` role (`arm_recompact.sh`, above) is the Codex half that *arms* it. A spike against codex 0.144.1 confirmed the `session_id` is **stable across a compaction** (`SessionStart source=compact` shares it with `UserPromptSubmit`), so a sentinel keyed on `session_id` survives into the resumed session and the next prompt re-injects the full payload once. The script's gate — `[ -z "$SOURCE" ] || [ "$SOURCE" = "compact" ]` — arms on `SessionStart(source=compact)` **and** on the sourceless `PreCompact`/`PostCompact` events, rejecting only an explicit non-compact source (a normal `SessionStart source=startup`); so which compaction event fires the arm is pure manifest config (`compaction_arm = SessionStart`, swappable to `PreCompact`/`PostCompact` with no script change). The spike exercised manual `/compact`; whether auto (context-full) compaction emits the same `SessionStart(source=compact)` is confirmed by end-to-end testing before the arm is relied on as the sole channel — the per-turn breadcrumb remains the always-on fallback.

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
