#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

usage() {
    echo "usage: checkpoint-archive.sh [--section <heading>] [--keep <n>]... <working-file> [slug]" >&2
    echo "       checkpoint-archive.sh [--section <heading>] --list <working-file>" >&2
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
LIST=0
KEEPS=()

# --list prints the section's entries numbered; --keep <n> (repeatable) rolls
# every entry EXCEPT the kept ones. Entries are the fence-depth-0 "### "
# headings, numbered 1-based in file order — the same numbering --list prints,
# so a caller never counts headings itself. Values live in an array: a
# string would be word-split and glob-expanded, so `--keep '?'` could match a
# file named k2 and silently keep entry 2.
while [ $# -gt 0 ]; do
    case "$1" in
        # Not ${2:?...}: under `set -e` that exits 1, which is the same code a
        # missing working file returns. A usage error must be distinguishable.
        --section) [ $# -ge 2 ] || { usage; exit 2; }; SECTION="$2"; shift 2 ;;
        --section=*) SECTION="${1#*=}"; shift ;;
        --list) LIST=1; shift ;;
        --keep) [ $# -ge 2 ] || { usage; exit 2; }; KEEPS+=("$2"); shift 2 ;;
        --keep=*) KEEPS+=("${1#*=}"); shift ;;
        --) shift; break ;;
        -*) usage; exit 2 ;;
        *) break ;;
    esac
done

[ -n "$SECTION" ] || { usage; exit 2; }
if [ "$LIST" -eq 1 ] && [ "${#KEEPS[@]}" -gt 0 ]; then
    echo "checkpoint-archive: --list and --keep cannot be combined" >&2
    exit 2
fi
[ $# -ge 1 ] || { usage; exit 2; }
[ $# -le 2 ] || { usage; exit 2; }
[ "$LIST" -eq 0 ] || [ $# -eq 1 ] || { usage; exit 2; }

WORKING_FILE="$1"
SLUG="${2:-}"
# Options stop at the first positional, so a trailing "--keep=2" would otherwise
# be taken as the slug and roll everything. A slug is only ever a filename part.
if [ $# -eq 2 ]; then
    case "$SLUG" in
        [A-Za-z0-9]*) ;;
        *) echo "checkpoint-archive: invalid slug '$SLUG' (options go before the working file)" >&2; usage; exit 2 ;;
    esac
    case "$SLUG" in
        *[!A-Za-z0-9._-]*) echo "checkpoint-archive: invalid slug '$SLUG' (options go before the working file)" >&2; usage; exit 2 ;;
    esac
fi
SECTION_HEADING="## $SECTION"
SECTION_LABEL="$(printf '%s' "$SECTION" | tr '[:upper:]' '[:lower:]')"

[ -f "$WORKING_FILE" ] || {
    echo "checkpoint-archive: no working file at $WORKING_FILE" >&2
    exit 1
}

# awk reads a relative operand shaped like name=value as an assignment and
# falls back to stdin, so anchor relative paths.
case "$WORKING_FILE" in
    /*) ;;
    *) WORKING_FILE="./$WORKING_FILE" ;;
esac

# CommonMark-style fence tracking, copied from formatters/working.sh so both
# agree on what is inside a fence: up to 3 leading spaces, backtick or tilde
# fences, closing fence of the same char and at least the opening length.
FENCE_AWK='
    function fenceline(s,   t, k) {
        t = s; sub(/^ ? ? ?/, "", t)
        if (fence) {
            sub(/[ \t]+$/, "", t)
            if (substr(t, 1, 1) == fch && t ~ /^(`+|~+)$/ && length(t) >= flen) fence = 0
            return 1
        }
        if (t !~ /^```+[^`]*$/ && t !~ /^~~~+/) return 0
        fch = substr(t, 1, 1); k = 0
        while (substr(t, k + 1, 1) == fch) k++
        flen = k; fence = 1
        return 1
    }
'

TMP_BASE="${WORKING_FILE}.checkpoint-archive.$$"
SECTION_TMP="$TMP_BASE.section"
STATUS_TMP="$TMP_BASE.status"
REWRITE_TMP="$TMP_BASE.rewrite"

cleanup() {
    rm -f "$SECTION_TMP" "$STATUS_TMP" "$REWRITE_TMP"
}
trap cleanup EXIT HUP INT TERM

# The scan also fails closed on input it cannot number reliably: a duplicate
# target heading (which entry list is meant?) or a fence left open at EOF that
# opened at or before the target section (it swallows the section boundary or
# the target itself). A fence opened in a LATER sibling is harmless. Nothing is
# written in any mode, legacy included. Output is captured, never a temp file,
# so --list creates nothing.
SCAN_RC=0
SCAN="$(CA_HEADING="$SECTION_HEADING" awk "$FENCE_AWK"'
    BEGIN { heading = ENVIRON["CA_HEADING"]; state = 0; n = 0; found = 0; dup = 0 }
    {
        r = $0; sub(/\r$/, "", r)
        was = fence
        if (fenceline(r)) {
            if (!was) { fopen_state = state; fopen_line = NR }
            next
        }
        if (r ~ /^## /) {
            t = r; sub(/[[:space:]]+$/, "", t)
            if (t == heading) {
                if (found) dup = 1
                found = 1
                state = 1
            } else if (state == 1) {
                state = 2
            }
            next
        }
        if (state == 1 && r ~ /^### /) { n++; ent[n] = n "\t" r }
    }
    END {
        if (dup) { print "dup"; exit 3 }
        if (fence && fopen_state != 2) { print fopen_line; exit 4 }
        printf "found=%d\n", found
        for (i = 1; i <= n; i++) print ent[i]
    }
' "$WORKING_FILE")" || SCAN_RC=$?

case "$SCAN_RC" in
    0) ;;
    3) echo "checkpoint-archive: '$SECTION_HEADING' appears more than once in $WORKING_FILE; refusing to guess" >&2; exit 2 ;;
    4) echo "checkpoint-archive: unclosed code fence from line $SCAN in $WORKING_FILE may hide section boundaries; refusing to guess" >&2; exit 2 ;;
    *) echo "checkpoint-archive: scan failed on $WORKING_FILE" >&2; exit 1 ;;
esac

SECTION_FOUND="${SCAN%%
*}"
ENTRIES=""
case "$SCAN" in
    *"
"*) ENTRIES="${SCAN#*
}" ;;
esac

if { [ "$LIST" -eq 1 ] || [ "${#KEEPS[@]}" -gt 0 ]; } && [ "$SECTION_FOUND" != "found=1" ]; then
    echo "checkpoint-archive: section '$SECTION_HEADING' not found in $WORKING_FILE" >&2
    exit 2
fi

if [ "$LIST" -eq 1 ]; then
    [ -z "$ENTRIES" ] || printf '%s\n' "$ENTRIES"
    exit 0
fi

# Validate every --keep BEFORE anything is written: a keep that cannot be
# honoured must never degrade into rolling that entry.
ENTRY_COUNT=0
[ -z "$ENTRIES" ] || ENTRY_COUNT="$(printf '%s\n' "$ENTRIES" | wc -l | tr -d ' ')"
KEEP_SET=" "
KEEP_UNIQUE=0
for _k in ${KEEPS[@]+"${KEEPS[@]}"}; do
    case "$_k" in
        ''|*[!0-9]*) echo "checkpoint-archive: --keep '$_k' is not a positive entry number" >&2; exit 2 ;;
    esac
    [ "${#_k}" -le 9 ] || { echo "checkpoint-archive: --keep '$_k' is out of range (entries: $ENTRY_COUNT)" >&2; exit 2; }
    _k=$((10#$_k))
    if [ "$_k" -lt 1 ] || [ "$_k" -gt "$ENTRY_COUNT" ]; then
        echo "checkpoint-archive: --keep $_k is out of range (entries: $ENTRY_COUNT)" >&2
        exit 2
    fi
    case "$KEEP_SET" in
        *" $_k "*) ;;
        *) KEEP_SET="$KEEP_SET$_k "; KEEP_UNIQUE=$((KEEP_UNIQUE + 1)) ;;
    esac
done

if [ "$KEEP_UNIQUE" -gt 0 ] && [ "$KEEP_UNIQUE" -ge "$ENTRY_COUNT" ]; then
    echo "checkpoint-archive: nothing to roll in $WORKING_FILE (all $ENTRY_COUNT entries kept)"
    exit 0
fi

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
CA_STATUS="$STATUS_TMP" CA_HEADING="$SECTION_HEADING" CA_KEEPS="$KEEP_SET" awk "$FENCE_AWK"'
    function is_blank() { return r ~ /^[[:space:]]*$/ }
    function is_placeholder() { return r ~ /^_\(none yet/ }
    # Literal compare after trimming trailing whitespace — see --section above.
    function is_wanted(   line) {
        line = r
        sub(/[[:space:]]+$/, "", line)
        return line == heading
    }
    BEGIN {
        status = ENVIRON["CA_STATUS"]; heading = ENVIRON["CA_HEADING"]; keeps = ENVIRON["CA_KEEPS"]
        found = 0; in_section = 0; real_body = 0; cur = 0
    }
    {
        r = $0; sub(/\r$/, "", r)
        infence = fenceline(r)
        if (!infence && r ~ /^## /) {
            if (in_section) { exit }
            if (is_wanted()) {
                found = 1
                in_section = 1
                print
                next
            }
        }
        if (in_section) {
            if (!infence && r ~ /^### /) { cur++ }
            if (cur > 0 && index(keeps, " " cur " ") > 0) { next }
            print
            if (!is_blank() && !is_placeholder()) { real_body = 1 }
        }
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
CA_PLACEHOLDER="$PLACEHOLDER" CA_HEADING="$SECTION_HEADING" CA_KEEPS="$KEEP_SET" awk "$FENCE_AWK"'
    function is_wanted(   line) {
        line = r
        sub(/[[:space:]]+$/, "", line)
        return line == heading
    }
    function end_section(has_next,   i, last) {
        if (!reset_emitted) {
            print ""
            print placeholder
            reset_emitted = 1
        }
        if (nk > 0) {
            print ""
            last = nk
            if (!has_next) { while (last > 1 && kept[last] ~ /^[[:space:]]*$/) last-- }
            for (i = 1; i <= last; i++) print kept[i]
            if (has_next && kept[nk] !~ /^[[:space:]]*$/) print ""
        } else if (has_next) {
            print ""
        }
        nk = 0
    }
    BEGIN {
        placeholder = ENVIRON["CA_PLACEHOLDER"]; heading = ENVIRON["CA_HEADING"]; keeps = ENVIRON["CA_KEEPS"]
        in_section = 0; reset_emitted = 0; cur = 0; nk = 0
    }
    {
        r = $0; sub(/\r$/, "", r)
        infence = fenceline(r)
        if (!infence && r ~ /^## /) {
            if (in_section) {
                end_section(1)
                in_section = 0
            }
            if (is_wanted()) {
                print
                in_section = 1
                reset_emitted = 0
                cur = 0
                next
            }
        }
        if (in_section) {
            if (!infence && r ~ /^### /) { cur++ }
            if (cur > 0 && index(keeps, " " cur " ") > 0) { kept[++nk] = $0 }
            next
        }
        print
    }
    END {
        if (in_section) {
            end_section(0)
        }
    }
' "$WORKING_FILE" > "$REWRITE_TMP"

mv "$REWRITE_TMP" "$WORKING_FILE"

echo "checkpoint-archive: snapshot $SNAPSHOT"
if [ "$KEEP_UNIQUE" -gt 0 ]; then
    echo "checkpoint-archive: rolled $SECTION for $PROJECT to archive/working/$SNAPSHOT_BASE (kept $KEEP_UNIQUE of $ENTRY_COUNT entries)"
else
    echo "checkpoint-archive: rolled $SECTION for $PROJECT to archive/working/$SNAPSHOT_BASE"
fi
