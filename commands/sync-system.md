Sync this instance to its configured channel, run pending migrations, and reinstall every feature the checked-out version ships (hooks, slash commands, skills, agents, statusline).

A plain `git pull` updates repo files, but new commands/skills/agents only become visible to the harness once they are symlinked into `~/.claude/`. This does both — and it never syncs to raw `main` unless the instance is configured to.

**The channel decides what a plain sync does.** It is per-instance, set in the gitignored `config.local.sh`:

- `AI_MEMORY_CHANNEL=release` (**the default when unset**) — check out the latest stable `v*` tag. The instance ends on a detached HEAD at that tag; consumer instances never commit.
- `AI_MEMORY_CHANNEL=dev` — fast-forward pull of the tracking branch. For the source checkout and dogfood instances. Recovers automatically from a detached HEAD.

A value exported in `config.local.sh` **overrides an environment prefix**, so `AI_MEMORY_CHANNEL=dev bash sync-system.sh` will not work on an instance whose config sets the channel. Edit the file.

Argument: `$ARGUMENTS` — optional flags forwarded to the script:

- `--dry-run` — report the resolved channel, the target ref, and the pending migrations. It **does** run `git fetch --tags origin` to resolve the target (falling back to local refs when offline); it does not check out, run migrations, or touch the working tree.
- `--to <ref>` — one-shot checkout of a tag, branch, or sha. **Ephemeral**: it does not change the channel, so the next plain sync snaps back to the channel default. `--to <branch>` checks out that ref *as-is* and does not fast-forward it — to dogfood current `main`, use `--to origin/main`.
- `--no-pull` — skip the fetch/checkout; just relink features from the current tree. Cannot be combined with `--to` (usage error, exit 2).
- `--update` — additionally re-resolve remote skills against their pinned refs.

Step 1 — run:

```
bash ~/.claude-memory/scripts/sync-system.sh $ARGUMENTS
```

Capture stdout and the exit code. Every path shares one tail: dirty-tracked-file guard → `git fetch --tags` → checkout (or ff-merge on `dev`) → **pending migrations** → the idempotent `install.sh`.

Step 2 — report concisely:

- **Synced** — say which version is now live (`git describe --tags`) and name any **new** slash commands / skills / agents that got linked (lines like `link: <name>`).
- **Migrations ran** — name each one. They mutate instance data and harness config, and `.applied-version` records the high-water mark. Never re-run them by hand.
- **Aborted on a dirty tracked tree** — surface the message. The user has local modifications to a *tracked* file. Untracked and git-ignored files never block. Do not stash, commit, or discard on their behalf.
- **Aborted with "no release tag yet"** — the release channel has nothing to check out. Either a tag must be cut, or this instance belongs on `dev`.
- **Aborted on divergence (`dev` only)** — the branch has local commits or a non-ff history. Surface it; do not merge or rebase.
- **A migration failed** — the sync stopped *before* `install.sh`, and `.applied-version` sits at the last migration that succeeded. Re-running resumes from there. Surface the failing filename.

Step 3 — if any new slash command was linked, remind the user once: slash commands load at session start, so they must restart or reconnect the session to see it.

Do not edit files from this command — it is sync-and-relink only.

**Two things this command is not for.**

Converting an existing `main`-tracking instance to the release channel for the first time is a documented runbook, not this command: `UPGRADING.md` → *Converting an existing instance to the release channel*.

Never point an instance at a tag earlier than `v1.1.0`. At `v1.0.0` `identity.md` was still tracked, so checking it out **silently overwrites** a personalised `identity.md` — no conflict, no warning, clean tree afterwards.
