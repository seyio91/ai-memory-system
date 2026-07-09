#!/usr/bin/env bash
# apply-partial.sh — inject/sync a managed partial block into a skill's SKILL.md (#5).
# The one partial we ship is `self-rating`. The canonical text lives once at
# scripts/partials/<partial>.md; this script splices it into a skill between
# demarcation markers so a re-run re-syncs from source (idempotent) and an
# external skill stays fork-safe (the block is clearly machine-managed).
#
# Loop membership is DERIVED from marker presence — a skill is "in" a partial's
# loop exactly when its SKILL.md carries the block. So:
#   * Re-syncing a skill that already has the block needs no flag (idempotent).
#   * The FIRST injection into a skill is an explicit act and requires --force
#     (new-skill --kind workflow passes it automatically). This is the guard that
#     keeps self-rating from being injected into an imported/remote skill unless
#     you ask for it.
#   * --all re-syncs every skill that already carries this partial (use after
#     editing the canonical block source).
#
# Usage:
#   apply-partial.sh --skill <name> [--partial self-rating] [--force]
#   apply-partial.sh --all [--partial self-rating]   # re-sync all carriers
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

SKILL="" PARTIAL="self-rating" FORCE=0 ALL=0
while [ $# -gt 0 ]; do
    case "$1" in
        --skill)    SKILL="${2:-}"; shift 2 ;;
        --partial)  PARTIAL="${2:-}"; shift 2 ;;
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

apply_one() {
    name="$1"
    case "$name" in *[!A-Za-z0-9._-]*|.|..) printf 'apply-partial: invalid skill name %s\n' "$name" >&2; return 2 ;; esac
    sdir="$(resolve_skill_dir "$name")" || { printf 'apply-partial: no SKILL.md for skill %s\n' "$name" >&2; return 2; }
    f="$sdir/SKILL.md"
    # First injection (no block yet) is an explicit act -> require --force.
    # Re-sync (block already present) is always allowed.
    if ! grep -Fq "<!-- partial:$PARTIAL START" "$f" && [ "$FORCE" != 1 ]; then
        printf 'apply-partial: %s does not carry the %s block yet — first injection requires --force (new-skill --kind workflow does this; imported/remote skills get it only on request)\n' "$name" "$PARTIAL" >&2
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
    printf 'applied: %s -> %s\n' "$PARTIAL" "${f#"$MEMORY_DIR"/}"

    # Validate just this skill (markdown body can't break frontmatter, but the
    # store validator is the contract — isolate this skill's findings by name).
    vout="$(bash "$SCRIPT_DIR/validate-skills.sh" 2>&1 || true)"
    verr="$(printf '%s\n' "$vout" | awk -v n="$name" '$1=="ERROR:" && $2==n')"
    [ -z "$verr" ] || { printf '%s\napply-partial: validation failed for %s\n' "$verr" "$name" >&2; return 1; }
    return 0
}

rc=0
if [ "$ALL" = 1 ]; then
    carriers="$(skills_with_partial "$PARTIAL")"
    [ -n "$carriers" ] || { printf 'apply-partial: no skill carries the %s block yet (inject one with --force first)\n' "$PARTIAL" >&2; exit 0; }
    for s in $carriers; do apply_one "$s" || rc=$?; done
elif [ -n "$SKILL" ]; then
    apply_one "$SKILL" || rc=$?
else
    printf 'apply-partial: --skill <name> or --all required\n' >&2; exit 2
fi
exit "$rc"
