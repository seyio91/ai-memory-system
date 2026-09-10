#!/usr/bin/env bash
# apply-partial.sh — inject/sync a managed partial block into a markdown carrier (#5).
# The one partial we ship is `self-rating`. The canonical text lives once at
# scripts/partials/<partial>.md; this script splices it into a skill between
# demarcation markers so a re-run re-syncs from source (idempotent) and an
# external skill stays fork-safe (the block is clearly machine-managed).
#
# Loop membership is DERIVED from marker presence — a skill is "in" a partial's
# loop exactly when its SKILL.md carries the block. So:
#   * Re-syncing a carrier that already has the block needs no flag (idempotent).
#   * The FIRST injection into a carrier is an explicit act and requires --force
#     (new-skill --kind workflow passes it automatically). This is the guard that
#     keeps self-rating from being injected into an imported/remote skill unless
#     you ask for it.
#   * --all re-syncs every carrier that already has this partial (use after
#     editing the canonical block source).
#
# Usage:
#   apply-partial.sh --skill <name> [--partial self-rating] [--force]
#   apply-partial.sh --file <path> [--partial self-rating] [--force]
#   apply-partial.sh --all [--partial self-rating]   # re-sync all carriers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

SKILL="" FILE="" PARTIAL="self-rating" FORCE=0 ALL=0
need_value() {
    [ "$#" -ge 2 ] || { printf 'apply-partial: %s needs a value\n' "$1" >&2; exit 2; }
}
while [ $# -gt 0 ]; do
    case "$1" in
        --skill)    need_value "$@"; SKILL="$2"; shift 2 ;;
        --file)     need_value "$@"; FILE="$2"; shift 2 ;;
        --partial)  need_value "$@"; PARTIAL="$2"; shift 2 ;;
        --all)      ALL=1; shift ;;
        --force)    FORCE=1; shift ;;
        -h|--help)  sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'apply-partial: unknown arg: %s\n' "$1" >&2; exit 2 ;;
    esac
done

case "$PARTIAL" in *[!A-Za-z0-9._-]*|""|.|..) printf 'apply-partial: invalid --partial\n' >&2; exit 2 ;; esac
PFILE="$SCRIPT_DIR/partials/$PARTIAL.md"
[ -f "$PFILE" ] || { printf 'apply-partial: no partial source at %s\n' "$PFILE" >&2; exit 2; }

START="<!-- partial:$PARTIAL START (managed by scripts/apply-partial.sh — edit scripts/partials/$PARTIAL.md) -->"
END="<!-- partial:$PARTIAL END -->"

canonical_path() {
    local input="$1" path link dir hops=0
    case "$input" in
        /*) path="$input" ;;
        *) path="$PWD/$input" ;;
    esac
    while [ -L "$path" ]; do
        hops=$((hops + 1))
        [ "$hops" -le 40 ] || return 1
        link="$(readlink "$path")" || return 1
        case "$link" in
            /*) path="$link" ;;
            *) path="$(dirname "$path")/$link" ;;
        esac
    done
    dir="$(cd -P "$(dirname "$path")" 2>/dev/null && pwd)" || return 1
    printf '%s/%s\n' "$dir" "$(basename "$path")"
}

MEMORY_CANON="$(canonical_path "$MEMORY_DIR")" || {
    printf 'apply-partial: cannot resolve MEMORY_DIR %s\n' "$MEMORY_DIR" >&2
    exit 2
}

apply_target() {
    local f="$1" label="$2" tmp
    # First injection (no block yet) is an explicit act -> require --force.
    # Re-sync (block already present) is always allowed.
    if ! grep -Fq "<!-- partial:$PARTIAL START" "$f" && [ "$FORCE" != 1 ]; then
        printf 'apply-partial: %s does not carry the %s block yet — first injection requires --force\n' "$label" "$PARTIAL" >&2
        return 1
    fi

    tmp="$f.partial.$$"
    # Strip any existing managed block (markers inclusive), then trailing blanks.
    awk -v s="$START" -v e="$END" '
        $0 == s { inblk = 1; next }
        inblk && $0 == e { inblk = 0; next }
        inblk { next }
        { print }
    ' "$f" | awk '
        { buf[NR] = $0 }
        END { last = NR; while (last > 0 && buf[last] ~ /^[[:space:]]*$/) last--; for (i = 1; i <= last; i++) print buf[i] }
    ' > "$tmp"

    {
        printf '\n%s\n' "$START"
        cat "$PFILE"
        printf '%s\n' "$END"
    } >> "$tmp"

    mv "$tmp" "$f"
    printf 'applied: %s -> %s\n' "$PARTIAL" "${f#"$MEMORY_CANON"/}"
}

apply_skill() {
    local name="$1" sdir f vout verr
    case "$name" in *[!A-Za-z0-9._-]*|.|..) printf 'apply-partial: invalid skill name %s\n' "$name" >&2; return 2 ;; esac
    sdir="$(resolve_skill_dir "$name")" || { printf 'apply-partial: no SKILL.md for skill %s\n' "$name" >&2; return 2; }
    f="$sdir/SKILL.md"
    apply_target "$f" "$name" || return $?

    # Validate just this skill (markdown body can't break frontmatter, but the
    # store validator is the contract — isolate this skill's findings by name).
    vout="$(bash "$SCRIPT_DIR/validate-skills.sh" 2>&1 || true)"
    verr="$(printf '%s\n' "$vout" | awk -v n="$name" '$1=="ERROR:" && $2==n')"
    [ -z "$verr" ] || { printf '%s\napply-partial: validation failed for %s\n' "$verr" "$name" >&2; return 1; }
    return 0
}

apply_file() {
    local input="$1" f
    f="$(canonical_path "$input")" || { printf 'apply-partial: cannot resolve --file path %s\n' "$input" >&2; return 2; }
    case "$f" in
        "$MEMORY_CANON"/*) ;;
        *) printf 'apply-partial: --file path must be inside MEMORY_DIR: %s\n' "$input" >&2; return 2 ;;
    esac
    [ -f "$f" ] || { printf 'apply-partial: no markdown file at %s\n' "$input" >&2; return 2; }
    apply_target "$f" "$f"
}

rc=0
if [ -n "$SKILL" ] && [ -n "$FILE" ]; then
    printf 'apply-partial: --skill and --file are mutually exclusive\n' >&2
    exit 2
elif [ "$ALL" = 1 ]; then
    carriers="$(skills_with_partial "$PARTIAL")"
    found=0
    for s in $carriers; do
        found=1
        apply_skill "$s" || rc=$?
    done
    for f in "$MEMORY_DIR"/commands/*.md; do
        [ -f "$f" ] || continue
        grep -Fq "<!-- partial:$PARTIAL START" "$f" || continue
        found=1
        apply_file "$f" || rc=$?
    done
    [ "$found" = 1 ] || printf 'apply-partial: no carrier carries the %s block yet (inject one with --force first)\n' "$PARTIAL" >&2
elif [ -n "$SKILL" ]; then
    apply_skill "$SKILL" || rc=$?
elif [ -n "$FILE" ]; then
    apply_file "$FILE" || rc=$?
else
    printf 'apply-partial: --skill <name>, --file <path>, or --all required\n' >&2; exit 2
fi
exit "$rc"
