#!/usr/bin/env bash
# skill-ratings.sh — aggregate per-skill self-ratings (#6).
# Globs skills/*/self-rating.md (the co-located, own-folder rating logs) and
# prints one row per rated skill: entry count, latest score, average score, and
# the latest improve note. Dependency-free (awk); skills with no log are skipped.
#
# Rating-entry shape (written by the self-rating partial, on request only):
#   ## YYYY-MM-DD — <context>
#   - score: <1-5>
#   - friction: <...>
#   - improve: <...>
#
# Usage: skill-ratings.sh [--all]   (--all also lists in-loop skills — those carrying
#        the self-rating block — that have no ratings yet)
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

SKILLS_DIR="${SKILLS_DIR:-$MEMORY_DIR/skills}"
ALL=0
[ "${1:-}" = "--all" ] && ALL=1

[ -d "$SKILLS_DIR" ] || { printf 'skill-ratings: no skills dir at %s\n' "$SKILLS_DIR" >&2; exit 2; }

# Parse one rating log -> "count<TAB>latest_score<TAB>avg<TAB>latest_improve".
# LC_ALL=C pins the decimal point to '.' regardless of the shell locale.
parse_log() {
    LC_ALL=C awk '
        /^[[:space:]]*-[[:space:]]*score:/ {
            v = $0; sub(/^[^:]*:[[:space:]]*/, "", v); sub(/[[:space:]].*$/, "", v)
            if (v ~ /^[1-5]$/) { n++; sum += v; last = v }
        }
        /^[[:space:]]*-[[:space:]]*improve:/ {
            t = $0; sub(/^[^:]*:[[:space:]]*/, "", t); imp = t
        }
        END {
            if (n == 0) { print "0\t-\t-\t-"; exit }
            printf "%d\t%s\t%.1f\t%s\n", n, last, sum / n, (imp == "" ? "-" : imp)
        }
    ' "$1"
}

found=0
printf '%-34s %5s %7s %5s  %s\n' "SKILL" "N" "LATEST" "AVG" "LATEST IMPROVE"
for d in "$SKILLS_DIR"/*/; do
    [ -d "$d" ] || continue
    name="$(basename "$d")"
    log="$d/self-rating.md"
    if [ -f "$log" ]; then
        IFS="$(printf '\t')" read -r n latest avg imp <<EOF
$(parse_log "$log")
EOF
        [ "$n" = "0" ] && continue
        found=$((found + 1))
        printf '%-34s %5s %7s %5s  %s\n' "$name" "$n" "$latest" "$avg" "$imp"
    fi
done

# --all also lists skills that are IN the loop (carry the self-rating block)
# but have no VALID scored entries yet. Membership is marker-derived; "rated" is
# decided by parse_log (same 1-5 validation as the main loop) so a log with only
# out-of-range scores still shows here rather than vanishing from both views.
if [ "$ALL" = 1 ]; then
    for s in $(skills_with_partial self-rating "$SKILLS_DIR"); do
        log="$SKILLS_DIR/$s/self-rating.md"
        n=0
        [ -f "$log" ] && n="$(parse_log "$log" | cut -f1)"
        if [ "${n:-0}" = "0" ]; then
            printf '%-34s %5s %7s %5s  %s\n' "$s" "0" "-" "-" "(no ratings yet)"
        fi
    done
fi

[ "$found" -gt 0 ] || printf 'skill-ratings: no ratings recorded yet\n'
exit 0
