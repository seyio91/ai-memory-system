# Upgrading

## How instances upgrade

Instances upgrade through `scripts/sync-system.sh`. The channel is per instance, set in
gitignored `config.local.sh` with `AI_MEMORY_CHANNEL`.

| Instance | `AI_MEMORY_CHANNEL` | Gets |
|----------|---------------------|------|
| dev machine (the source checkout) | `dev` | ff-pull of the tracking branch |
| dogfood instance | `dev`, or one-shot `--to <ref>` | main / branches on demand |
| stable instance | `release` (default) | latest stable `v*` tag only |

Common invocations:

```bash
sync-system.sh              # channel default
sync-system.sh --to v1.3.0  # pin or rollback to a tag
sync-system.sh --to main    # dogfood main once
sync-system.sh --to <sha>   # bisect a specific commit
sync-system.sh --dry-run    # preview the chosen checkout and migrations
```

`--to` is ephemeral. It never changes the channel, so the next plain
`sync-system.sh` snaps the instance back to its channel default. A release-channel
consumer ends on a detached HEAD at the selected tag, and consumer instances never
commit.

## The two standing rules

1. Migrations are **forward-only and idempotent**. There are no down-migrations.
2. **N/N+1 compatibility**: a migration must not break the previous release's code.
   Old code plus new data must still work. Ship the compatibility fallback in
   release N, then flip in N+1.

Rule 2 exists because a downgrade with `--to` moves code back but leaves data
migrated: `.applied-version` is a high-water mark, and the runner never re-runs an
older migration. N/N+1 compatibility is what makes that safe.

The `.agents/memory-project` marker migration is the worked example: first ship the
new reader with the legacy `.claude/memory-project` fallback, then bulk-migrate the
marker after old readers can tolerate the new state.

## The semver rule of thumb

MAJOR: breaks an instance without a migration, or incompatibly changes the
`MEMORY_DIR`, marker, or manifest contracts.

MINOR: new features, a new harness, additive manifest keys, or any N-1-compatible
migration.

PATCH: fixes.

## Per-version upgrade notes

Released versions that need manual steps or carry a migration get one section:

```markdown
## <version>
```

`scripts/tests/test_upgrading_doc.sh` enforces that every
`migrations/<version>-<slug>.sh` file has a matching `## <version>` section here.

There are currently no per-version upgrade notes because there are no migration
files yet.

## What a migration may touch

A migration may touch instance data and harness config, not engine code. See
[migrations/README.md](migrations/README.md) for the full migration contract.

## Distribution

Releases are git tags; no downloadable archive is provided. A zip distribution for
external users is deliberately deferred.
