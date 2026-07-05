# Common workflows & troubleshooting

## Start a new engagement

One slash command in Claude does the whole thing:

```
/new-project acme-migration
```

`/new-project` scaffolds `projects/acme-migration/` from `_template`, **asks for the repo's absolute path and places the `.agents/memory-project` marker there itself** (so the project is pinned — no separate `/pin` step), then interviews you section-by-section to fill `memory.md`. Leave the path blank to skip pinning and scaffold only.

**Manual equivalent (Two-Path).** The raw script is scaffold-only; do the marker by hand:

```bash
~/.claude-memory/scripts/new-project.sh acme-migration
cd ~/code/acme-migration && mkdir -p .agents && echo acme-migration > .agents/memory-project
```

## Re-pin when the checkout moves

`/new-project` already pins the project at creation, so you rarely touch `/pin`. Use it **when the project's location changes** — the checkout moved to a new path, or you're pinning an already-scaffolded project to its repo. Run from inside the checkout:

```
/pin acme-migration
```

`/pin` (`memory-pin.sh`) writes **both directions**: the forward `.agents/memory-project` marker *and* the reverse `repo`/`repo_path` frontmatter in `memory.md` (which powers cross-project code resolution — see [Reverse map](install.md#reverse-map-project--checkout)). That reverse half is why `/pin` — not just the plain marker — is the right tool when a location changes.

Manual equivalent:

```bash
cd /new/path/to/repo && ~/.claude-memory/scripts/memory-pin.sh acme-migration
```

There is no global active-project fallback. An unpinned cwd loads no project, so multiple sessions in different repos run concurrently without colliding on a shared default.

## Group projects by client, and report a client's work

Tag each project with a **category** (a client/group), then view or report work per client. Category is **personal** — it lives only in the gitignored project `memory.md`.

```
# tag an existing project's checkout with its client:
/pin acme-eks --category acme-corp
# (new projects: /new-project asks for a category; or hand-edit the `category:` frontmatter)

# see live work grouped by client, or one client's in-flight work:
/state                     # every project, grouped by category
/state acme-corp           # just this client's live work

# report the plans created for a client in the last month (reviewing / invoicing):
/activity acme-corp --since 30d
/activity --all --since 30d   # every category
```

`/activity` counts **plans by their `created` date** within the window (scanning live and archived plans), grouped by category — a plan is one unit of work. It's independent of the task backend, and its output (`activity.md`) is gitignored/personal.

## Capture a learning mid-session

- **Claude**: just say "remember that X" — maintenance rules route it.
- **Codex**: `/checkpoint` (captures plus pulls cross-project learnings out into the right section).

## Promote a learning

```
/promote-memory
```

Asks: domain or project? If "new" domain, prompts for triggers + summary, seeds a properly frontmatter'd file. Archives `working.md` and regenerates `index.md`.

## Periodic maintenance

Run when memory feels dusty (monthly, or before a long break):

```
/lint-memory       # Content quality: contradictions, stale paths, orphans, template gaps
/reindex           # Rebuild the index from frontmatter (also runs after /promote-memory)
```

For deeper cleanup (dedup, merge, split files): tell Claude "reorganize memory" — see the procedure in `~/.claude/CLAUDE.md`.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| Memory not injected in Claude session | Hook didn't fire. Check `~/.claude/settings.json` registers it and `~/.claude/hooks/inject_memory.sh` is executable. Confirm output is `hookSpecificOutput.additionalContext` JSON. Working memory only injects when non-empty. |
| Identity re-injected every prompt | The per-session marker isn't being written. Confirm `~/.claude/memory_sessions/` is writable and the hook can parse `session_id` from stdin. |
| Codex doesn't see project memory | `codex-mem.sh` couldn't resolve the project. Pin the repo with `.agents/memory-project` (launch from inside the repo tree). |
| Cross-project delegate (Codex) sees the wrong project | A `codex-mem.sh` executor resolves `AGENTS.md` from the *active* project. Pin the sibling repo before launching, or pass the sibling `memory.md` path in the prompt. |
| `~/.codex/AGENTS.md` looks stale | It's only regenerated when you launch via `codex-mem.sh`. Plain `codex` reads the existing file as-is. |
| Local Codex instructions vanished | You edited `~/.codex/AGENTS.md` (generated, overwritten). Move your additions to `~/.codex/AGENTS.local.md`. |
| `index.md` doesn't reflect a new file | Frontmatter missing or malformed. Run `lint-memory.sh`. Then `regenerate-index.sh`. |
| Bash heredoc fails under Codex `read-only` sandbox | Heredocs need writable `/tmp`. Use `printf` + double-quoted strings in any script that may run under restrictive sandboxes. |
| Slash command not autocompleting | Restart the Claude session — slash commands in `~/.claude/commands/` are indexed at session start. |
| `TaskCreate`/`TaskUpdate` not blocked | `block_task_tools.sh` missing from `settings.json` `PreToolUse`, not executable, or matcher typo. The matcher must be `TaskCreate\|TaskUpdate`. |
