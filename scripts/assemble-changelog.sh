#!/usr/bin/env bash
#
# assemble-changelog.sh — turn per-PR news fragments in changelog.d/ into a
# CHANGELOG section, and compute the next version from the fragment kinds.
#
# A fragment is a file  changelog.d/<id>.<kind>.md  whose body is the
# human-facing note (one or more markdown bullets). Kinds:
#
#   breaking | feature | fix | upgrade
#
# This script is PURE: it reads fragments and prints; it never mutates the tree
# (release.sh owns deletion + the commit). Assembly is deterministic — same
# fragment set in, byte-identical section out — so nothing is left to infer.
#
# Usage:
#   assemble-changelog.sh [--dir <changelog.d>] assemble   # default: print section body
#   assemble-changelog.sh [--dir <changelog.d>] --bump     # print computed next version (bare)
#   assemble-changelog.sh [--dir <changelog.d>] --check     # validate fragment filenames
#
#   --dir   fragment directory (default: <repo>/changelog.d)
#
# Exit: 0 ok; 1 validation findings; 2 usage / nothing to do.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/_lib.sh"

KINDS="breaking feature fix upgrade"
DIR="$REPO_ROOT/changelog.d"
MODE="assemble"

while [ $# -gt 0 ]; do
    case "$1" in
        --dir) DIR="$2"; shift 2 ;;
        --bump) MODE="bump"; shift ;;
        --check) MODE="check"; shift ;;
        assemble) MODE="assemble"; shift ;;
        -*) echo "assemble-changelog: unknown flag: $1" >&2; exit 2 ;;
        *) echo "assemble-changelog: unexpected argument: $1" >&2; exit 2 ;;
    esac
done

# heading shown in the CHANGELOG for a kind
heading_for() {
    case "$1" in
        breaking) printf '### Breaking\n' ;;
        feature)  printf '### Added\n' ;;
        fix)      printf '### Fixed\n' ;;
        upgrade)  printf '### Upgrade\n' ;;
    esac
}

# semver bump level a kind demands
level_for() {
    case "$1" in
        breaking) printf 'major\n' ;;
        feature)  printf 'minor\n' ;;
        fix|upgrade) printf 'patch\n' ;;
    esac
}

is_valid_kind() {
    case " $KINDS " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# kind of a fragment filename: the last dot-segment before .md
# 42.feature.md -> feature ; my.slug.fix.md -> fix
kind_of() {
    local base="${1##*/}"
    base="${base%.md}"
    printf '%s\n' "${base##*.}"
}

# sorted list of fragment files (C locale for stability), one per line
fragment_files() {
    [ -d "$DIR" ] || return 0
    local f
    for f in "$DIR"/*.*.md; do
        [ -e "$f" ] || continue
        printf '%s\n' "$f"
    done | LC_ALL=C sort
}

check_fragments() {
    local rc=0 f kind found=0
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        found=1
        kind="$(kind_of "$f")"
        if ! is_valid_kind "$kind"; then
            printf 'INVALID %s — kind "%s" must be one of: %s\n' "${f##*/}" "$kind" "$KINDS" >&2
            rc=1
        fi
        if [ ! -s "$f" ]; then
            printf 'EMPTY %s — a fragment must carry a note\n' "${f##*/}" >&2
            rc=1
        fi
    done <<EOF
$(fragment_files)
EOF
    [ "$found" = 1 ] || { echo "assemble-changelog: no fragments in $DIR" >&2; return 2; }
    return $rc
}

assemble_section() {
    local any=0 kind f first
    for kind in $KINDS; do
        first=1
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            [ "$(kind_of "$f")" = "$kind" ] || continue
            if [ "$first" = 1 ]; then
                [ "$any" = 1 ] && printf '\n'
                heading_for "$kind"
                printf '\n'
                first=0
                any=1
            fi
            # emit the fragment body verbatim, trailing blank lines trimmed
            # (awk, not sed — deterministic and identical on BSD/GNU)
            awk '{ line[NR] = $0 }
                 END { last = NR
                       while (last > 0 && line[last] ~ /^[[:space:]]*$/) last--
                       for (i = 1; i <= last; i++) print line[i] }' "$f"
        done <<EOF
$(fragment_files)
EOF
    done
    [ "$any" = 1 ] || { echo "assemble-changelog: no fragments in $DIR" >&2; return 2; }
}

compute_bump() {
    local kind f level="" seen="" want=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        kind="$(kind_of "$f")"
        is_valid_kind "$kind" || { echo "assemble-changelog: invalid kind in ${f##*/}" >&2; return 2; }
        seen=1
        level="$(level_for "$kind")"
        case "$level" in
            major) want="major" ;;
            minor) [ "$want" = "major" ] || want="minor" ;;
            patch) [ -n "$want" ] || want="patch" ;;
        esac
    done <<EOF
$(fragment_files)
EOF
    [ -n "$seen" ] || { echo "assemble-changelog: no fragments in $DIR to bump from" >&2; return 2; }

    local prev major minor patch old_ifs
    prev="$(latest_release_tag 2>/dev/null || true)"
    prev="${prev#v}"
    [ -n "$prev" ] || prev="0.0.0"
    old_ifs="$IFS"; IFS=.
    # shellcheck disable=SC2086
    set -- $prev
    IFS="$old_ifs"
    major="$(_semver_num "${1:-0}")"
    minor="$(_semver_num "${2:-0}")"
    patch="$(_semver_num "${3:-0}")"

    case "$want" in
        major) major=$((major + 1)); minor=0; patch=0 ;;
        minor) minor=$((minor + 1)); patch=0 ;;
        patch) patch=$((patch + 1)) ;;
        *) echo "assemble-changelog: could not determine bump level" >&2; return 2 ;;
    esac
    printf '%s.%s.%s\n' "$major" "$minor" "$patch"
}

case "$MODE" in
    assemble) assemble_section ;;
    bump) compute_bump ;;
    check) check_fragments ;;
esac
