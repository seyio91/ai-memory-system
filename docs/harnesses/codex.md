# Codex CLI

Codex gets its memory **live through native Codex hooks**: the full dynamic tree
(identity → orchestrator → project → index → domain table → working) injects at `SessionStart`, and the
per-turn breadcrumb / compaction recovery ride `UserPromptSubmit` — so a **plain `codex`**
(no alias, no wrapper) has full memory. `~/.codex/AGENTS.md` is a **hand-owned static
base** the memory system never writes (the Antigravity model): put permanent
Codex-specific workflow rules there. At install (`install.sh --harness codex`) the
bundled skills **and** the slash-commands-as-skills fan into the cross-agent
`~/.agents/skills` (Codex's command mechanism is skills).

> **Codex caps each hook `additionalContext` message at ~10,100 bytes** (middle-elided
> with a `…N tokens truncated…` marker; probe vs codex 0.144.4 — not lifted by
> `tool_output_token_limit`). But every registered hook **entry** gets its own budget,
> delivered in registration order — so the base fans out across N chunk entries
> (`session_chunks`/`inject_chunks` in the manifest, ≤9,000B line-boundary slices).
> Overflow is **loud** (a truncation marker on the last slice tells you to raise the
> chunk count), never silent.
>
> Registration order holds **on Codex specifically** — Claude does not guarantee it
> (see `docs/harnesses/claude.md` → Chunked injection). Slices therefore carry a
> `<memory:chunk index of>` ordering envelope from the shared `emit_hook_chunk`;
> on Codex it is inert insurance, not a fix for an observed defect here.

## Daily use

```bash
codex        # plain launch — full memory via the SessionStart hook

# The wrapper survives for the EXECUTOR face only (sandbox/network flags for
# delegated runs; --executor-bare suppresses all memory injection):
~/.claude-memory/harnesses/codex/scripts/codex-mem.sh --executor "do the thing"
~/.claude-memory/harnesses/codex/scripts/codex-mem.sh --executor-bare "lean review"
```

## Native hooks

`install.sh --harness codex` writes a user-level `~/.codex/hooks.json` (Codex's own schema — a top-level `hooks` object keyed by event, distinct from Antigravity's shape) registering three roles from the manifest `[hooks]` map:

| Role | Event | Script | Effect |
|------|-------|--------|--------|
| `session_bootstrap` | `SessionStart` (×`session_chunks` entries) | shared `scripts/hooks/session_start_memory.sh` (`AI_MEMORY_HOOK_FORMAT=md`, `AI_MEMORY_HOOK_CHUNK=i/N`) | Injects the full memory base once at session load, chunked across N ordered entries (each renders and emits its slice, statelessly). On `source=compact` (or a sourceless `*Compact*` event) chunk 1 arms the `.recompact` sentinel instead. |
| `per_turn_inject` | `UserPromptSubmit` (×`inject_chunks` entries) | shared `scripts/hooks/inject.sh` (`AI_MEMORY_HOOK_FORMAT=md`, `AI_MEMORY_HOOK_CHUNK=i/N`) | Chunk 1 emits the per-prompt breadcrumb; the post-compact re-inject and the `@memory` reload fan the full payload out across all N entries (a single message would hit the ~10KB cap). |
| `infra_guard` | `PreToolUse` (matcher `^Bash$\|apply_patch`) | shared `scripts/hooks/guard.sh` | Under an executor role (`AI_MEMORY_ROLE` set), denies the shared infra deny-list via `exit 2` — Codex honors it as a tool block. Interactive sessions (no role) pass through. |

**Bare executor opt-out.** `codex-mem.sh --executor-bare` exports `AI_MEMORY_SKIP_INJECT=1` (both hook scripts honor it — no base, no breadcrumb) **and** sets `-c project_doc_max_bytes=0` (no hand-owned `AGENTS.md`/repo docs), for lean review subagents.

**Trust.** Codex hash-pins hook trust by design, so there is no install-writable auto-trust on a personal machine (`requirements.toml` is MDM-only). Interactive Codex needs a **one-time `/hooks` trust** (re-prompts only if a hook's command changes); the headless executor path (`codex-mem.sh --executor`) passes `--dangerously-bypass-hook-trust`.

**Version floor.** Hook registration is gated at install time on `codex --version ≥ hooks_min_version` (0.135.0).

**Compaction recovery.** The shared `inject.sh` consumes a `.recompact` sentinel armed by the session-start script's compact branch (chunk 1 only). A spike against codex 0.144.1 confirmed the `session_id` is **stable across a compaction**, so the sentinel survives into the resumed session and the next prompt re-injects the full payload once — chunked, the sentinel consumed by the last chunk. The arm fires on `SessionStart(source=compact)` **and** on a sourceless event whose `AI_MEMORY_HOOK_EVENT` names a `*Compact*` event, so the event choice stays pure manifest config. `harnesses/codex/hooks/arm_recompact.sh` was a one-release compatibility shim for a stale pre-flip `hooks.json` and is now deleted. Its name is deliberately retained in the hook-registration sweep set (`scripts/drivers/hook.sh`), so re-running `install.sh` removes a stale entry rather than leaving one pointed at a file that no longer exists.

## What the SessionStart hook injects

Rendered live from the memory tree on every session load (`md` format), in this order:

1. **`# === IDENTITY ===`** — `identity.md` verbatim.
2. **`# === ORCHESTRATOR ===`** — `orchestrator.md` verbatim.
3. **`# === PROJECT: <name> ===`** — `projects/<active>/memory.md`.
4. **`# === MEMORY INDEX ===`** — `index.md` (lifecycle prose + auto-generated catalog).
5. **`# === DOMAIN INDEX ===`** — table synthesized from frontmatter in each `domain/*.md` (file path, triggers, summary), with a lazy-load instruction: Codex reads the file with its shell tool when the user's request matches a topic's triggers.
6. **`# === WORKING MEMORY ===`** — the session's working file if non-empty (worktree-aware — see below).

Unlike the retired file build, edits to the tree are picked up **live**: the next session (or `@memory` in the current one) sees them with no relaunch of a wrapper.

## `~/.codex/AGENTS.md` — your permanent Codex instructions

Hand-owned, never written by the memory system. The Codex analogue of `~/.claude/CLAUDE.md` — permanent workflow rules and personal instructions go here. (Migration `1.4.0-codex-agents-handoff.sh` converts a previously machine-generated file, seeding it from your old `AGENTS.local.md` overlay; the overlay is retired — its whole reason to exist was surviving regeneration.)

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

The hooks resolve the project and the working overlay from the **session's cwd** (carried in the hook event payload and exported as `AI_MEMORY_CWD`), so launching inside the worktree routes both the injected context *and* `/checkpoint` to `working.<worktree-name>.md` — the [per-worktree overlay](../file-formats.md#per-worktree-overlays-workingkeymd) — with no config. The other checkout's `working.md` is untouched. (First-class `--worktree`/`--tmux` flags are only a proposed Codex feature; until then, the manual `git worktree add` above is the flow.) This process is regression-tested end-to-end (`scripts/tests/test_worktree_feature_process.sh`).

## Status line — not wired (fixed item vocabulary, no script hook)

Investigated 2026-07-17 against codex 0.144.4. Codex **has** a TUI status line —
`/statusline` in the TUI, persisted as `tui.status_line` (+ `status_line_use_colors`)
in `config.toml` — but it only toggles a **fixed set of built-in items**:

```
app-name · project-name · current-dir · activity · run-state · thread-title ·
git-branch · context-remaining · context-used · five-hour-limit · weekly-limit ·
codex-version · used-tokens · total-input-tokens · total-output-tokens ·
thread-id · fast-mode · model-with-reasoning · reasoning · task-progress
```

There is **no command-backed/custom segment** (verified by binary probe — no
`custom` item, no statusline feature flag), so unlike Claude
(`settings.json → statusLine`) and Antigravity (`statusline.sh`), the memory
system cannot inject an active-project or memory-todo-count segment here. The
memory system therefore does not touch Codex's status line — turn the built-in
items on yourself with `/statusline` if you want them.

**Revisit trigger:** command-backed statusline rendering is an open upstream
request ([openai/codex#20140](https://github.com/openai/codex/issues/20140),
[#20244](https://github.com/openai/codex/issues/20244)). If it ships, file a
fresh task: a manifest `statusline_*` pair plus the shared memory-todo-count
segment (design record: the `codex-statusline` plan).

## Adding a new domain topic (Codex picks it up automatically)

1. Drop a new file `domain/postgres.md` with frontmatter:

   ```yaml
   ---
   topic: postgres
   triggers: [pg, postgres, psql, plpgsql]
   summary: Postgres conventions, indexing rules, migration patterns
   ---
   ```

2. The SessionStart hook renders a new row in the Domain Index on the next session (or immediately via `@memory`).
3. No code change.

## Standalone `codex-mem-checkpoint.sh`

Outside a Codex session — useful after exiting Codex while a session insight is still fresh:

```bash
~/.claude-memory/harnesses/codex/scripts/codex-mem-checkpoint.sh
```

Opens `$EDITOR` on `working.md` with a checkpoint scaffold appended. Fill in done/next/blockers, save, done.
