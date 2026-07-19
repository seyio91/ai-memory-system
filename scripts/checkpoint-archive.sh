#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

usage() {
    echo "usage: checkpoint-archive.sh [--section <heading>] <working-file> [slug]" >&2
}

# --section names the h2 to roll, WITHOUT the leading '## '. Defaults to
# Checkpoints, so the legacy two-arg form is unchanged. /promote-memory passes
# "Cross-project learnings (pending promotion)" — the mechanics (fence-aware
# scan, sibling sections preserved, placeholder reset, snapshot) are identical
# per section, so both commands share one implementation instead of two copies
# of this awk.
#
# The heading is matched as a LITERAL string, never as a regex: the learnings
# heading contains parentheses, which an awk regex would read as grouping and
# silently fail to match — leaving the section unrolled while still reporting
# success.
SECTION="Checkpoints"

while [ $# -gt 0 ]; do
    case "$1" in
        # Not ${2:?...}: under `set -e` that exits 1, which is the same code a
        # missing working file returns. A usage error must be distinguishable.
        --section) [ $# -ge 2 ] || { usage; exit 2; }; SECTION="$2"; shift 2 ;;
        --section=*) SECTION="${1#*=}"; shift ;;
        --) shift; break ;;
        -*) usage; exit 2 ;;
        *) break ;;
    esac
done

[ -n "$SECTION" ] || { usage; exit 2; }
[ $# -ge 1 ] || { usage; exit 2; }
[ $# -le 2 ] || { usage; exit 2; }

WORKING_FILE="$1"
SLUG="${2:-}"
SECTION_HEADING="## $SECTION"
SECTION_LABEL="$(printf '%s' "$SECTION" | tr '[:upper:]' '[:lower:]')"

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

# The stamp is minute-resolution, so two rolls in the same minute collide and the
# second silently clobbers the first — losing audit trail, not just annoying.
# That was merely unlikely while only /checkpoint-archive rolled; with
# /promote-memory rolling a DIFFERENT section of the SAME file it is routine, and
# it bit on the first live exercise. Suffix instead of overwrite. The cap is a
# runaway guard: 99 rolls in one minute means something is looping.
if [ -e "$SNAPSHOT" ]; then
    _n=2
    while [ "$_n" -le 99 ]; do
        _candidate="${SNAPSHOT_BASE%.md}-$_n.md"
        if [ ! -e "$ARCHIVE_DIR/$_candidate" ]; then
            SNAPSHOT_BASE="$_candidate"
            SNAPSHOT="$ARCHIVE_DIR/$SNAPSHOT_BASE"
            break
        fi
        _n=$((_n + 1))
    done
    if [ -e "$SNAPSHOT" ]; then
        echo "checkpoint-archive: cannot find a free snapshot name for $SNAPSHOT_BASE" >&2
        exit 1
    fi
fi
TMP_BASE="${WORKING_FILE}.checkpoint-archive.$$"
SECTION_TMP="$TMP_BASE.section"
STATUS_TMP="$TMP_BASE.status"
REWRITE_TMP="$TMP_BASE.rewrite"

cleanup() {
    rm -f "$SECTION_TMP" "$STATUS_TMP" "$REWRITE_TMP"
}
trap cleanup EXIT HUP INT TERM

awk -v status="$STATUS_TMP" -v heading="$SECTION_HEADING" '
    function is_h2() { return !fence && $0 ~ /^## / }
    function is_blank() { return $0 ~ /^[[:space:]]*$/ }
    function is_placeholder() { return $0 ~ /^_\(none yet/ }
    # Literal compare after trimming trailing whitespace — see --section above.
    function is_wanted(   line) {
        line = $0
        sub(/[[:space:]]+$/, "", line)
        return line == heading
    }
    function toggle_fence_if_needed() {
        if ($0 ~ /^[[:space:]]*```/) { fence = !fence }
    }
    BEGIN { found = 0; in_section = 0; real_body = 0; fence = 0 }
    {
        if (is_h2()) {
            if (in_section) { exit }
            if (is_wanted()) {
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
    printf '# Archived %s — %s — %s\n\n' "$SECTION_LABEL" "$PROJECT" "$DAY"
    cat "$SECTION_TMP"
} > "$SNAPSHOT"

PLACEHOLDER="_(none yet — rolled $DAY to archive/working/$SNAPSHOT_BASE)_"
awk -v placeholder="$PLACEHOLDER" -v heading="$SECTION_HEADING" '
    function is_h2() { return !fence && $0 ~ /^## / }
    function is_wanted(   line) {
        line = $0
        sub(/[[:space:]]+$/, "", line)
        return line == heading
    }
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
            if (is_wanted()) {
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
echo "checkpoint-archive: rolled $SECTION for $PROJECT to archive/working/$SNAPSHOT_BASE"
