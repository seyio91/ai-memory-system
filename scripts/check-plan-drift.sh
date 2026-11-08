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
# When --repo shares the memory root's object store, projects/<plan-project>/**
# is ignored (plan/todo/baseline bookkeeping rides the branch).
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

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "not a git checkout: $REPO"

plan_dir="$(cd "$(dirname "$PLAN")" && pwd)" || die "plan not readable: $PLAN"
project="$(basename "$(dirname "$plan_dir")")"

patterns="$(awk -v want="$PHASE" '
    /^### Phase [0-9]+ — / { split($0, a, " "); phase = a[3]; next }
    /^##+ / { phase = ""; next }
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

changed="$(git -C "$REPO" -c core.quotepath=off diff --no-renames --name-only "$RANGE" -- 2>/dev/null)" \
    || die "git diff failed for range '$RANGE' in $REPO"

drift=0
while IFS= read -r f; do
    [ -n "$f" ] || continue
    if [ "$exclude_project" -eq 1 ]; then
        case "$f" in "projects/$project/"*) continue ;; esac
    fi
    matched=0
    while IFS= read -r pat; do
        # shellcheck disable=SC2254
        case "$f" in $pat) matched=1; break ;; esac
    done <<EOP
$patterns
EOP
    if [ "$matched" -eq 0 ]; then
        printf 'drift: %s\n' "$f"
        drift=1
    fi
done <<EOC
$changed
EOC

exit "$drift"
