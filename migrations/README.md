# Migrations

Migration files are named:

```text
<semver>-<slug>.sh
```

Example:

```text
1.1.0-agents-marker.sh
```

Rules:

- Forward-only: no down-migrations.
- One migration per version. If a change needs two ordered steps, give them two versions.
- Filename format is strict: semver core without leading zeroes, then a slug containing only letters, numbers, `.`, `_`, or `-`.
- Idempotent and re-runnable: a migration may run against a tree that already has the change.
- Touch data and harness config only: `$MEMORY_DIR` data, `~/.claude/settings.json`, `~/.gemini/...`.
- Never touch engine code: git already moves the engine files.
- N/N+1 compatibility: a migration must not break the previous release's code. Ship the compatibility fallback in release N, then flip the data/config in N+1. The `.agents/memory-project` migration used this pattern: new reader with legacy fallback first, bulk migration after.
- `scripts/migrate-marker.sh` is the historical example and is deliberately not converted into this directory.

Skeleton:

```bash
#!/usr/bin/env bash
set -euo pipefail

: "${MEMORY_DIR:?MEMORY_DIR is required}"
: "${REPO_ROOT:?REPO_ROOT is required}"

# Idempotent change here. Check before writing, tolerate already-migrated state,
# and leave old code compatible with the resulting data/config.
```
