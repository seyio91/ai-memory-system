#!/usr/bin/env bash
# Prune archive files older than a threshold across the memory tree.
# Walks projects/<active>/archive/{plans,todos,working}/ by default.
# Preserves .gitkeep files unconditionally.
#
# Usage:
#   archive-cleanup.sh [--all-projects] [--dry-run] [--days N]
#
# Env:
#   MEMORY_DIR                    default ~/.claude-memory
#   MEMORY_ARCHIVE_RETAIN_DAYS    default 30
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

DAYS="${MEMORY_ARCHIVE_RETAIN_DAYS:-30}"
DRY_RUN=0
ALL_PROJECTS=0

while [ $# -gt 0 ]; do
    case "$1" in
        --all-projects) ALL_PROJECTS=1; shift ;;
        --dry-run)      DRY_RUN=1; shift ;;
        --days)         DAYS="$2"; shift 2 ;;
        --days=*)       DAYS="${1#--days=}"; shift ;;
        -h|--help)
            sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "archive-cleanup: unknown arg: $1" >&2
            exit 1
            ;;
    esac
done

if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
    echo "archive-cleanup: --days must be a non-negative integer (got: $DAYS)" >&2
    exit 1
fi

# Resolve project list.
PROJECTS=()
if [ "$ALL_PROJECTS" -eq 1 ]; then
    for d in "$MEMORY_DIR"/projects/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        [ "$name" = "_template" ] && continue
        PROJECTS+=("$name")
    done
else
    ACTIVE=$(detect_active_project)
    if [ -z "$ACTIVE" ]; then
        echo "archive-cleanup: no active project resolved. Set one or pass --all-projects." >&2
        exit 1
    fi
    PROJECTS+=("$ACTIVE")
fi

TOTAL_DELETED=0
TOTAL_LISTED=0

for project in "${PROJECTS[@]}"; do
    ARCHIVE="$MEMORY_DIR/projects/$project/archive"
    [ -d "$ARCHIVE" ] || continue

    # Collect candidate files: regular files, not .gitkeep, mtime older than threshold.
    # Limit to known subdirs to avoid surprising the user with foreign content.
    CANDIDATES=()
    while IFS= read -r f; do
        [ -n "$f" ] && CANDIDATES+=("$f")
    done < <(
        find "$ARCHIVE/plans" "$ARCHIVE/todos" "$ARCHIVE/working" \
            -type f \
            ! -name '.gitkeep' \
            -mtime "+$DAYS" \
            2>/dev/null
    )

    [ ${#CANDIDATES[@]} -eq 0 ] && continue

    echo "[$project] ${#CANDIDATES[@]} file(s) older than $DAYS day(s):"
    for f in "${CANDIDATES[@]}"; do
        rel="${f#$MEMORY_DIR/}"
        if [ "$DRY_RUN" -eq 1 ]; then
            echo "  would delete: $rel"
            TOTAL_LISTED=$((TOTAL_LISTED + 1))
        else
            rm -- "$f"
            echo "  deleted:      $rel"
            TOTAL_DELETED=$((TOTAL_DELETED + 1))
        fi
    done
done

if [ "$DRY_RUN" -eq 1 ]; then
    echo "---"
    echo "DRY RUN — $TOTAL_LISTED file(s) would be deleted. Re-run without --dry-run to apply."
elif [ "$TOTAL_DELETED" -eq 0 ]; then
    echo "archive-cleanup: nothing to do (no archive files older than $DAYS day(s))."
else
    echo "---"
    echo "archive-cleanup: deleted $TOTAL_DELETED file(s)."
fi
