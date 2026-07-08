# Upgrading

## How instances upgrade

Instances upgrade through `scripts/sync-system.sh`. The channel is per instance, set in
gitignored `config.local.sh` with `AI_MEMORY_CHANNEL`.

| Instance | `AI_MEMORY_CHANNEL` | Gets |
|----------|---------------------|------|
| dev machine (the source checkout) | `dev` | ff-pull of the tracking branch |
| dogfood instance | `dev`, or one-shot `--to <ref>` | main / branches on demand |
| stable instance | `release` (default) | latest stable `v*` tag only; aborts when no stable tag exists |

There are currently no stable `v*` tags, so release-channel instances abort until
the first release is cut.

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
