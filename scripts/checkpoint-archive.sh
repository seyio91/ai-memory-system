#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

usage() {
    echo "usage: checkpoint-archive.sh <working-file> [slug]" >&2
}

[ $# -ge 1 ] || { usage; exit 2; }
[ $# -le 2 ] || { usage; exit 2; }

WORKING_FILE="$1"
SLUG="${2:-}"

[ -f "$WORKING_FILE" ] || {
    echo "checkpoint-archive: no working file at $WORKING_FILE" >&2
    exit 1
}

PROJECT_DIR="$(cd "$(dirname "$WORKING_FILE")" && pwd)"
PROJECT="$(basename "$PROJECT_DIR")"
ARCHIVE_DIR="$PROJECT_DIR/archive/working"
STAMP="$(date +%Y-%m-%d-%H%M)"
DAY="$(date +%Y-%m-%d)"
SNAPSHOT_BASE="$STAMP"
if [ -n "$SLUG" ]; then
    SNAPSHOT_BASE="$SNAPSHOT_BASE-$SLUG"
fi
SNAPSHOT_BASE="$SNAPSHOT_BASE.md"
SNAPSHOT="$ARCHIVE_DIR/$SNAPSHOT_BASE"
TMP_BASE="${WORKING_FILE}.checkpoint-archive.$$"
SECTION_TMP="$TMP_BASE.section"
STATUS_TMP="$TMP_BASE.status"
REWRITE_TMP="$TMP_BASE.rewrite"

cleanup() {
    rm -f "$SECTION_TMP" "$STATUS_TMP" "$REWRITE_TMP"
}
trap cleanup EXIT HUP INT TERM

awk -v status="$STATUS_TMP" '
    function is_h2() { return !fence && $0 ~ /^## / }
    function is_blank() { return $0 ~ /^[[:space:]]*$/ }
    function is_placeholder() { return $0 ~ /^_\(none yet/ }
    function toggle_fence_if_needed() {
        if ($0 ~ /^[[:space:]]*```/) { fence = !fence }
    }
    BEGIN { found = 0; in_section = 0; real_body = 0; fence = 0 }
    {
        if (is_h2()) {
            if (in_section) { exit }
            if ($0 ~ /^## Checkpoints[[:space:]]*$/) {
                found = 1
                in_section = 1
                print
                toggle_fence_if_needed()
                next
            }
        }
        if (in_section) {
            print
            if (!is_blank() && !is_placeholder()) { real_body = 1 }
        }
        toggle_fence_if_needed()
    }
    END {
        printf "found=%d\nreal_body=%d\n", found, real_body > status
    }
' "$WORKING_FILE" > "$SECTION_TMP"

FOUND="$(awk -F= '$1 == "found" { print $2 }' "$STATUS_TMP")"
REAL_BODY="$(awk -F= '$1 == "real_body" { print $2 }' "$STATUS_TMP")"

if [ "${FOUND:-0}" -ne 1 ] || [ "${REAL_BODY:-0}" -ne 1 ]; then
    echo "checkpoint-archive: nothing to roll in $WORKING_FILE"
    exit 0
fi

mkdir -p "$ARCHIVE_DIR"
{
    printf '# Archived checkpoints — %s — %s\n\n' "$PROJECT" "$DAY"
    cat "$SECTION_TMP"
} > "$SNAPSHOT"

PLACEHOLDER="_(none yet — rolled $DAY to archive/working/$SNAPSHOT_BASE)_"
awk -v placeholder="$PLACEHOLDER" '
    function is_h2() { return !fence && $0 ~ /^## / }
    function emit_reset() {
        if (!reset_emitted) {
            print ""
            print placeholder
            reset_emitted = 1
        }
    }
    function toggle_fence_if_needed() {
        if ($0 ~ /^[[:space:]]*```/) { fence = !fence }
    }
    BEGIN { in_section = 0; reset_emitted = 0; fence = 0 }
    {
        if (is_h2()) {
            if (in_section) {
                emit_reset()
                print ""
                in_section = 0
            }
            if ($0 ~ /^## Checkpoints[[:space:]]*$/) {
                print
                in_section = 1
                reset_emitted = 0
                toggle_fence_if_needed()
                next
            }
        }
        if (in_section) {
            toggle_fence_if_needed()
            next
        }
        print
        toggle_fence_if_needed()
    }
    END {
        if (in_section) {
            emit_reset()
        }
    }
' "$WORKING_FILE" > "$REWRITE_TMP"

mv "$REWRITE_TMP" "$WORKING_FILE"

echo "checkpoint-archive: snapshot $SNAPSHOT"
echo "checkpoint-archive: rolled Checkpoints for $PROJECT to archive/working/$SNAPSHOT_BASE"
