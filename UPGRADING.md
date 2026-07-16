# Upgrading

## How instances upgrade

Instances upgrade through `scripts/sync-system.sh`. The channel is per instance, set in
gitignored `config.local.sh` with `AI_MEMORY_CHANNEL`.

| Instance | `AI_MEMORY_CHANNEL` | Gets |
|----------|---------------------|------|
| dev machine (the source checkout) | `dev` | ff-pull of the tracking branch |
| dogfood instance | `dev`, or one-shot `--to <ref>` | main / branches on demand |
| stable instance | `release` (default) | latest stable `v*` tag only; aborts when no stable tag exists |

A release-channel instance aborts with an actionable message if no stable `v*` tag
exists yet.

> **Do not point an instance at a tag earlier than `v1.1.0`.** At `v1.0.0`,
> `identity.md` was still tracked, so checking it out **silently overwrites** a
> personalised `identity.md` with the tag's copy — no conflict, no warning, and a
> clean tree afterwards. See [1.1.0](#110).

Precedence: `config.local.sh` is sourced after the process environment exists, so
values exported there win over one-off environment prefixes. To change an
instance's channel, edit `config.local.sh`; `AI_MEMORY_CHANNEL=release sync-system.sh`
will not override a configured `AI_MEMORY_CHANNEL`.

Common invocations:

```bash
sync-system.sh              # channel default
sync-system.sh --to v1.3.0  # check out an older tag for this run
sync-system.sh --to origin/main  # dogfood current dev state once
sync-system.sh --to <sha>   # bisect a specific commit
sync-system.sh --dry-run    # preview the chosen checkout and migrations
```

`--to` is ephemeral. It never changes the channel, so the next plain
`sync-system.sh` snaps the instance back to its channel default. A release-channel
consumer ends on a detached HEAD at the selected tag, and consumer instances never
commit.

`--to <branch>` checks out that ref as-is and does not fast-forward it. To dogfood
the current dev state, name the remote-tracking ref, for example
`--to origin/main`.

A downgrade with `--to` rolls back code only. Data stays migrated because
`.applied-version` is a high-water mark and older migrations do not re-run; this
is safe because of the [N/N+1 rule](#the-two-standing-rules).

A downgrade can still clobber a file that the older tag tracked and the newer one
does not. `--to v1.0.0` overwrites `identity.md`, because `v1.0.0` tracks it. Back
it up first.

## Converting an existing instance to the release channel

For an instance that was cloned before releases existed and still tracks `main`.
Run everything from the instance's own memory tree (`~/.claude-memory` by default;
`echo "$MEMORY_DIR"` if you are unsure).

```bash
cd ~/.claude-memory
```

**1. Confirm what you have.**

```bash
git branch --show-current          # probably "main"
git status --porcelain             # must be empty of TRACKED changes
git fetch --tags origin && git tag -l 'v*' | sort -V | tail -1
```

A dirty *tracked* file aborts the sync. Untracked and git-ignored files never do —
your `projects/`, `domain/`, `tasks/`, `config.local.sh`, and `identity.md` are all
ignored, so they are safe and are **not** touched by any checkout.

**2. Set the channel.** `release` is the default, so an instance with no
`AI_MEMORY_CHANNEL` is already a release-channel consumer — doing nothing is a
choice, not a no-op. To be explicit, add to the gitignored `config.local.sh` that
`install.sh` created:

```bash
echo 'export AI_MEMORY_CHANNEL="release"' >> config.local.sh
```

Remember the precedence rule above: a value in `config.local.sh` beats an
environment prefix. Editing the file is the only way to change an instance's channel.

**3. Preview, then sync.**

```bash
bash scripts/sync-system.sh --dry-run     # fetches tags, then reports channel + target tag; no checkout, no migrations
bash scripts/sync-system.sh
```

The sync checks out the latest stable tag, runs any pending migrations, and re-runs
`install.sh` to rebuild the harness wiring from that version.

**4. Verify.**

```bash
git describe --tags        # -> v1.1.0
cat .applied-version       # -> highest migration version applied, if any ran
```

**Afterwards the instance is on a detached HEAD** at the tag. That is intended.
Consumer instances never commit, and `git pull` will fail there — use
`sync-system.sh` to move between versions, not raw git. To return the instance to
tracking a branch, set `AI_MEMORY_CHANNEL=dev` in `config.local.sh` and sync again;
the dev path recovers the tracking branch from a detached HEAD automatically.

## The two standing rules

1. Migrations are **forward-only and idempotent**. There are no down-migrations.
2. **N/N+1 compatibility**: a migration must not break the previous release's code.
   Old code plus new data must still work. Ship the compatibility fallback in
   release N, then flip in N+1.

Rule 2 exists because a downgrade with `--to` moves code back but leaves data
migrated: `.applied-version` is a high-water mark, and the runner never re-runs an
older migration. N/N+1 compatibility is what makes that safe.

If `.applied-version` is absent, the runner treats the instance as `0.0.0`, so
the first upgrade runs the full migration history. That is safe because
migrations are idempotent; see [migrations/README.md](migrations/README.md) for
the migration contract.

The `.agents/memory-project` marker migration is the worked example: first ship the
new reader with the legacy `.claude/memory-project` fallback, then bulk-migrate the
marker after old readers can tolerate the new state.

## The semver rule of thumb

MAJOR: breaks an instance without a migration, or incompatibly changes the
`MEMORY_DIR`, marker, or manifest contracts.

MINOR: new features, a new harness, additive manifest keys, or any N-1-compatible
migration.

PATCH: fixes.

## What a migration may touch

A migration may touch instance data and harness config, not engine code. See
[migrations/README.md](migrations/README.md) for the full migration contract.

## Distribution

Releases are git tags; no downloadable archive is provided. A zip distribution for
external users is deliberately deferred.

## Per-version upgrade notes

Released versions that need manual steps or carry a migration get one section:

```markdown
## <version>
```

`scripts/tests/test_upgrading_doc.sh` enforces that every
`migrations/<version>-<slug>.sh` file has a matching `## <version>` section here.
The reverse does not hold: a version may need a manual step without shipping a
migration — as the next section does.

## 1.4.0

**Codex's `~/.codex/AGENTS.md` becomes a hand-owned static base.**

The memory system no longer generates `~/.codex/AGENTS.md`. The dynamic memory
tree (identity, project, index, domain, working) now injects live through Codex's
`SessionStart` hook — the same model Antigravity and Claude already use — so a
plain `codex` (no alias, no wrapper) gets full memory. `~/.codex/AGENTS.md` is left
as a hand-owned static base for permanent Codex-specific workflow rules or personal
instructions.

Migration `1.4.0-codex-agents-handoff.sh` converts an existing machine-built
`AGENTS.md` in place. It is **header-keyed**: only a memory-generated file carries
the `Generated by codex-mem` header, so a file you wrote by hand is left
byte-identical. When it finds a generated file it seeds the hand-owned base from
your `~/.codex/AGENTS.local.md` overlay (or a stub if you had none) and retires the
now-redundant overlay to `AGENTS.local.md.retired` (renamed, not deleted).

Interactive Codex re-prompts `/hooks` trust once when a hook command changes — the
`SessionStart` command does change here, so trust the ai-memory hooks again after
upgrading. Headless executor runs bypass trust automatically
(`--dangerously-bypass-hook-trust`) and are unaffected.

`arm_recompact.sh` survives this release as a compatibility shim (it delegates to
the shared session-start script) so a stale `~/.codex/hooks.json` from a manual
`git pull` that hasn't re-run `install.sh` keeps working. It is removed in the next
release.

**The canonical slash-command store moved: `harnesses/claude/commands/` → repo-level
`commands/`.**

The store is harness-neutral (Claude symlinks it natively; Codex/Antigravity wrap
the same bodies as skills; `doc`-surface harnesses render a reference), so it now
lives beside the other neutral stores (`skills/`, `agents/`). Upgrading through
`sync-system.sh` self-heals: `install.sh` re-links `~/.claude/commands/*` at the
new paths. A raw `git pull` that skips `install.sh` leaves those symlinks dangling
(slash commands vanish) until `install.sh`/`sync-system.sh` runs.

**Claude's `SessionStart` hook script moved — a manual `git pull` breaks session
start until `install.sh` re-runs.**

The same relocation moved Claude's session-start script from
`harnesses/claude/hooks/session_start_memory.sh` to the shared
`scripts/hooks/session_start_memory.sh`. A live `~/.claude/settings.json` that
still points at the old path fails every session start with
`no such file or directory` (the memory base silently stops loading).

Upgrading through `sync-system.sh` fixes this automatically: it re-runs
`install.sh`, whose settings merge sweeps ai-memory hook entries by script name
regardless of path and re-registers them at the current location — including the
`env MEMORY_DIR=... AI_MEMORY_HOOK_FORMAT=xml AI_MEMORY_HOOK_EVENT=SessionStart`
prefix the shared script expects. No manual step.

Only an instance updated with a raw `git pull` that skips `install.sh` hits the
error. Recovery is the same either way: run `install.sh` (or `sync-system.sh`).

## 1.1.0

**`identity.md` is no longer tracked. Back it up before upgrading.**

It is now per-instance and git-ignored, like `config.local.sh` and `skills.toml`.
`install.sh` seeds it from the tracked `identity.template.md` whenever it is missing.

Tracking it was a trap: `install.sh` tells you to edit `identity.md`, and
`sync-system.sh`'s dirty-tracked-file guard then aborts every subsequent sync. An
instance was bricked the moment it was personalised.

This is not only a `sync-system.sh` concern. `identity.md` is removed by **any
checkout that crosses this commit** — `git pull`, `git reset --hard`, or switching
branches — because at that moment the file is still tracked in your old `HEAD`. A
dev or dogfood checkout that never runs `sync-system.sh` is affected too.

What happens when you cross `1.1.0`:

| Your `identity.md` | Result |
|---|---|
| Edited (differs from the last tracked version) | `sync-system.sh` **aborts** on the dirty guard; a plain `git pull` refuses to overwrite. Save your copy, then `git checkout -- identity.md`, pull, and restore it. |
| Unedited | Git deletes it during checkout; `install.sh` reseeds the generic template. Your previous content is recoverable — see below. |
| Absent (fresh install) | Seeded from the template. Nothing to do. |

The unedited row is the dangerous one: it is **silent**. Nothing warns you, and
`install.sh` cheerfully replaces your file with the stock template.

**A migration cannot do this for you.** The runner executes *after* checkout, by
which point git has already removed the file — so this is a manual note, not a
`migrations/1.1.0-*.sh`. Any future removal of a tracked file has the same
constraint.

Recover the old content at any time — the blob is still in history, and `identity.md`
is now git-ignored, so writing it back leaves the tree clean:

```bash
git show v1.0.0:identity.md > identity.md
```

Verify it landed intact:

```bash
cmp <(git show v1.0.0:identity.md) identity.md && echo restored
```
