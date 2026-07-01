# Common workflows & troubleshooting

## Start a new engagement

The common path is two slash commands in Claude:

```
/new-project acme-migration      # scaffold projects/acme-migration/ from _template
/pin acme-migration              # run from inside the repo checkout — writes the
                                 #   forward .claude/memory-project marker AND the
                                 #   reverse repo/repo_path frontmatter in one step
```

Then edit `projects/acme-migration/memory.md`, replacing the template placeholders.

**Manual equivalent (Two-Path).** Every slash command has a hand path that produces the same on-disk result:

```bash
~/.claude-memory/scripts/new-project.sh acme-migration        # == /new-project
cd ~/code/acme-migration
~/.claude-memory/scripts/memory-pin.sh acme-migration         # == /pin (both directions)
# or, forward marker only, no reverse frontmatter:
mkdir -p .claude && echo acme-migration > .claude/memory-project
```

## Switch / activate a project

Pin-first is the model — pin a repo once and any session (Claude or Codex) opened anywhere in it auto-loads the project. From inside the checkout:

```
/pin fiter-charts
```

Manual equivalent:

```bash
cd /path/to/repo && ~/.claude-memory/scripts/memory-pin.sh fiter-charts
# forward marker only:
cd /path/to/repo && mkdir -p .claude && echo fiter-charts > .claude/memory-project
```

There is no global active-project fallback. An unpinned cwd loads no project, so multiple sessions in different repos run concurrently without colliding on a shared default. Pin each repo you want memory in.

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
| Codex doesn't see project memory | `codex-mem.sh` couldn't resolve the project. Pin the repo with `.claude/memory-project` (launch from inside the repo tree). |
| Cross-project delegate (Codex) sees the wrong project | A `codex-mem.sh` executor resolves `AGENTS.md` from the *active* project. Pin the sibling repo before launching, or pass the sibling `memory.md` path in the prompt. |
| `~/.codex/AGENTS.md` looks stale | It's only regenerated when you launch via `codex-mem.sh`. Plain `codex` reads the existing file as-is. |
| Local Codex instructions vanished | You edited `~/.codex/AGENTS.md` (generated, overwritten). Move your additions to `~/.codex/AGENTS.local.md`. |
| `index.md` doesn't reflect a new file | Frontmatter missing or malformed. Run `lint-memory.sh`. Then `regenerate-index.sh`. |
| Bash heredoc fails under Codex `read-only` sandbox | Heredocs need writable `/tmp`. Use `printf` + double-quoted strings in any script that may run under restrictive sandboxes. |
| Slash command not autocompleting | Restart the Claude session — slash commands in `~/.claude/commands/` are indexed at session start. |
| `TaskCreate`/`TaskUpdate` not blocked | `block_task_tools.sh` missing from `settings.json` `PreToolUse`, not executable, or matcher typo. The matcher must be `TaskCreate\|TaskUpdate`. |
