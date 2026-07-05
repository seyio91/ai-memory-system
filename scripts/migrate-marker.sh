#!/usr/bin/env bash
# migrate-marker.sh — migrate pinned checkouts from the legacy Claude-branded
# project marker (.claude/memory-project) to the harness-neutral
# .agents/memory-project. Walks every project's reverse map (repo_path / repo) to
# locate its checkout, then moves the marker there (same content). Reusable across
# instances of the memory system.
#
#   migrate-marker.sh            # dry-run: show what would change (default)
#   migrate-marker.sh --apply    # perform the migration
#
# Idempotent: a checkout already on the neutral marker is left alone (and a stale
# legacy copy alongside it is removed). Run this AFTER the de-branded readers are
# deployed, so both paths resolve during the transition.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

APPLY=0
case "${1:-}" in
    --apply)         APPLY=1 ;;
    ""|--dry-run)    APPLY=0 ;;
    *) echo "usage: migrate-marker.sh [--apply|--dry-run]" >&2; exit 2 ;;
esac

migrated=0 already=0 unresolved=0 nomarker=0
for mf in "$MEMORY_DIR"/projects/*/memory.md; do
    [ -f "$mf" ] || continue
    proj="$(basename "$(dirname "$mf")")"
    [ "$proj" = "_template" ] && continue

    if ! co="$(resolve_repo_path "$proj")"; then
        printf 'unresolved  %-20s (no checkout found via repo_path/repo)\n' "$proj"
        unresolved=$((unresolved + 1)); continue
    fi

    new="$co/.agents/memory-project"
    old="$co/.claude/memory-project"

    if [ -f "$new" ]; then
        if [ -f "$old" ]; then
            printf 'dedupe      %-20s remove stale legacy %s\n' "$proj" "$old"
            [ "$APPLY" = 1 ] && rm -f "$old"
            migrated=$((migrated + 1))
        else
            already=$((already + 1))
        fi
        continue
    fi

    if [ -f "$old" ]; then
        val="$(tr -d '[:space:]' < "$old")"
        printf 'migrate     %-20s %s -> .agents/memory-project (%s)\n' "$proj" "$old" "$val"
        if [ "$APPLY" = 1 ]; then
            mkdir -p "$co/.agents"
            printf '%s\n' "$val" > "$new"
            rm -f "$old"
        fi
        migrated=$((migrated + 1))
        continue
    fi

    nomarker=$((nomarker + 1))   # checkout resolved but neither marker present
done

printf '\n%s: %d migrated, %d already-neutral, %d unresolved, %d no-marker\n' \
    "$([ "$APPLY" = 1 ] && echo applied || echo 'dry-run')" \
    "$migrated" "$already" "$unresolved" "$nomarker"
[ "$APPLY" = 1 ] || printf 'Re-run with --apply to perform the migration.\n'
