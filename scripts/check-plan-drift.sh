#!/usr/bin/env bash
# Plan scope-drift check: files changed in a range vs the union of the plan's
# `**Files touched:**` globs.
#
# Usage:  check-plan-drift.sh <plan> --repo <path> --range <a...b> [--phase N]
# Prints  drift: <file>   one per file outside the plan's set.
# Exit    0 clean, 1 drift, 3 not applicable (plan created before
#         PLAN_CONTRACT_SINCE), 2 anything else (usage, unreadable plan, bad
#         ref, git failure, no Files touched). Never 0 on a failed diff.
#
# --repo and --range are required: the caller names the checkout it actually
# reviewed, so a primary checkout sitting on main is never diffed by accident.
# When --repo shares the memory root's object store, or its top level is itself
# a memory tree (doctrine/orchestrator.md), projects/<plan-project>/** is
# ignored (plan/todo/baseline bookkeeping rides the branch).
set -uo pipefail
. "$(dirname "$0")/_lib.sh"

usage() {
    printf 'usage: %s <plan> --repo <path> --range <a...b> [--phase N]\n' "$(basename "$0")" >&2
    exit 2
}

die() { printf 'ERROR %s\n' "$1" >&2; exit 2; }

PLAN="" REPO="" RANGE="" PHASE=""
while [ "$#" -gt 0 ]; do
    case "$1" in
        --repo)  [ "$#" -ge 2 ] || usage; REPO="$2"; shift 2 ;;
        --range) [ "$#" -ge 2 ] || usage; RANGE="$2"; shift 2 ;;
        --phase) [ "$#" -ge 2 ] || usage; PHASE="$2"; shift 2 ;;
        --) shift; break ;;
        -*) usage ;;
        *)  [ -z "$PLAN" ] || usage; PLAN="$1"; shift ;;
    esac
done
if [ "$#" -gt 0 ]; then
    [ "$#" -eq 1 ] && [ -z "$PLAN" ] || usage
    PLAN="$1"
fi

[ -n "$PLAN" ] && [ -n "$REPO" ] && [ -n "$RANGE" ] || usage
case "$RANGE" in -*) usage ;; esac
case "$PHASE" in
    "") ;;
    *[!0-9]*) usage ;;
esac

[ -r "$PLAN" ] && [ -f "$PLAN" ] || die "plan not readable: $PLAN"

created="$(extract_fm_field "$PLAN" created)"
case "$created" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]) ;;
    *) die "plan has no well-formed created: date ('$created')" ;;
esac
[[ "$created" < "$PLAN_CONTRACT_SINCE" ]] && exit 3

plan_dir="$(cd "$(dirname "$PLAN")" && pwd)" || die "plan not readable: $PLAN"
project_dir="$(dirname "$plan_dir")"
[ "$(basename "$project_dir")" = archive ] && project_dir="$(dirname "$project_dir")"
project="$(basename "$project_dir")"

patterns="$(awk -v want="$PHASE" '
    { t = $0; sub(/\r$/, "", t); sub(/^ ? ? ?/, "", t) }
    match(t, /^(```+|~~~+)/) {
        m = substr(t, 1, RLENGTH)
        if (fence == "") { fence = m; next }
        if (substr(m, 1, 1) == substr(fence, 1, 1) && RLENGTH >= length(fence) && t ~ /^(`+|~+)[[:space:]]*$/) { fence = ""; next }
    }
    fence != "" { next }
    /^### Phase [0-9]+ — / { split($0, a, " "); phase = a[3]; next }
    /^(## |### )/ { phase = ""; next }
    phase != "" && (want == "" || phase == want) && /^\*\*Files touched:\*\*/ {
        line = $0
        while (match(line, /`[^`]+`/)) {
            print substr(line, RSTART + 1, RLENGTH - 2)
            line = substr(line, RSTART + RLENGTH)
        }
    }
' "$PLAN")"
[ -n "$patterns" ] || die "no Files touched in plan${PHASE:+ phase $PHASE}: $PLAN"

# common_dir <checkout> — absolute, symlink-resolved git common dir.
common_dir() {
    local c
    c="$(git -C "$1" rev-parse --git-common-dir 2>/dev/null)" || return 1
    case "$c" in /*) ;; *) c="$1/$c" ;; esac
    (cd "$c" && pwd -P)
}

exclude_project=0
repo_common="$(common_dir "$REPO")" || die "not a git checkout: $REPO"
mem_common="$(common_dir "$MEMORY_DIR" 2>/dev/null)" || mem_common=""
[ -n "$mem_common" ] && [ "$repo_common" = "$mem_common" ] && exclude_project=1
repo_top="$(git -C "$REPO" rev-parse --show-toplevel 2>/dev/null)" || repo_top=""
[ -n "$repo_top" ] && [ -f "$repo_top/doctrine/orchestrator.md" ] && exclude_project=1

pats=()
while IFS= read -r pat; do
    case "$pat" in */) pat="$pat*" ;; esac
    pats[${#pats[@]}]="$pat"
done <<EOP
$patterns
EOP

changed_file="$(mktemp)" || die "mktemp failed"
trap 'rm -f "$changed_file"' EXIT
git -C "$REPO" diff -z --no-renames --name-only "$RANGE" -- >"$changed_file" 2>/dev/null \
    || die "git diff failed for range '$RANGE' in $REPO"

drift=0
while IFS= read -r -d '' f; do
    if [ "$exclude_project" -eq 1 ]; then
        case "$f" in "projects/$project/"*) continue ;; esac
    fi
    matched=0
    for pat in "${pats[@]}"; do
        # shellcheck disable=SC2254
        case "$f" in $pat) matched=1; break ;; esac
    done
    if [ "$matched" -eq 0 ]; then
        printf 'drift: %s\n' "$f"
        drift=1
    fi
done <"$changed_file"

exit "$drift"
