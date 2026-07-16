#!/usr/bin/env bash
#
# check-docs.sh — assert the documented env-var table matches the code.
#
# Doc rot recurs because nothing tests a doc against the code it describes. The
# env-var table in docs/scripts.md is a structured single source
# (`Var | Default | Used by`), so it yields two mechanical assertions:
#
#   forward  every documented var appears somewhere in the code roots.
#            Catches a var that was renamed or deleted but left documented
#            (MEMORY_SESSIONS_DIR: documented in 2 files, present in 0).
#
#   strict   every documented var appears in the script its `Used by` column
#            names -- or in any file that script sources, transitively.
#            Catches a var documented against the wrong consumer.
#
# Source-following is required, not a nicety: "Used by" means whose BEHAVIOUR
# the var affects, not which file holds the string. lint-memory.sh never
# mentions AI_MEMORY_PROJECTS_ROOT -- it calls projects_root() in _lib.sh. And
# one hop is not enough: scripts/hooks/inject.sh -> scripts/hooks/lib.sh ->
# _lib.sh is a depth-2 chain. Hence a transitive closure
# with a visited-set cycle guard.
#
# A `Used by` cell that names no script (e.g. "All scripts", "NotionProvider")
# must be listed in .docscheck-exempt WITH A REASON, or it fails. That keeps
# prose from silently creeping back into a machine-checked column.
#
# NB: matches are literal and include comments. AI_MEMORY_EXECUTOR_CMD_<key>
# passes only because executor.sh names the placeholder in a comment (the code
# builds the name dynamically). Deliberate: the true positive this gate exists
# for had ZERO occurrences of any kind. See the doc-vs-code-consistency-test plan.
#
# NB: enumerate with find(1), never ls(1). A wrapper that degrades `ls` to empty
# output turns this check into a silent pass -- the exact fail-open class it
# exists to prevent.
#
# Usage: check-docs.sh [root]
#   root  memory tree root; defaults to the parent of this script's dir.
#
# Exit: 0 clean, 1 one or more findings, 2 setup error.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="${1:-$(cd "$HERE/.." && pwd)}"

TABLE="$ROOT/docs/scripts.md"
EXEMPT="$ROOT/.docscheck-exempt"

[ -f "$TABLE" ] || { printf 'check-docs: no table at %s\n' "$TABLE" >&2; exit 2; }

# Code roots. install.sh / migrations/ may be absent in a fixture; not an error.
ROOTS="$ROOT/scripts $ROOT/harnesses"
[ -f "$ROOT/install.sh" ] && ROOTS="$ROOTS $ROOT/install.sh"
[ -d "$ROOT/migrations" ] && ROOTS="$ROOTS $ROOT/migrations"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# --- helpers ---------------------------------------------------------------

# resolve_script <basename> -> absolute path, or empty. Searches only the code
# roots, so archive/ and .skill-cache/ copies can never satisfy a check.
resolve_script() {
    find "$ROOT/scripts" "$ROOT/harnesses" "$ROOT/migrations" -name "$1" -type f 2>/dev/null | head -1
}

# sources_of <file> -> basenames of .sh files it sources.
# Matches the trailing /<basename>.sh rather than the token after `.`/`source`:
# `source "$(dirname "$0")/../shared/lib.sh"` contains a space inside $( ), so a
# naive \s+(\S+) capture grabs `"$(dirname` and silently finds nothing.
#
# NB: the s### delimiter is '#', NOT '|'. The alternation (\.|source) contains a
# literal '|', so a s|...| form ends the pattern early and sed dies with
# "parentheses not balanced". stderr is deliberately NOT suppressed here: when
# this regex first broke, a 2>/dev/null turned the error into an empty result and
# every source-following check silently reported "not found".
sources_of() {
    sed -n -E 's#^[[:space:]]*(\.|source)[[:space:]]+.*/([A-Za-z0-9_.-]+\.sh).*#\2#p' "$1"
}

# closure <file> <visited-file> -- append file and everything it transitively
# sources. The visited file is BOTH the result and the cycle guard: state lives
# on disk, so the `| while` subshell below still accumulates correctly.
# No per-call temp file -- a shared one would be truncated by the recursive
# call while the caller was still reading it.
#
# CLOSURE_MAX makes the cycle guard OBSERVABLE. Without the guard, a cyclic
# graph recurses until fork() fails; the dead subshells vanish, `seen` already
# holds the right files, and var_reachable still returns the right answer. The
# bug is real but invisible from the outside -- so a test cannot pin the guard.
# Overflowing into a flag file turns "the guard was removed" into a loud exit 2.
# (`exit` here would only leave the `| while` subshell.)
CLOSURE_MAX=256

closure() {
    local f="$1" seen="$2" base path
    grep -qxF -- "$f" "$seen" 2>/dev/null && return 0
    printf '%s\n' "$f" >>"$seen"
    if [ "$(wc -l <"$seen")" -gt "$CLOSURE_MAX" ]; then
        : >"$TMP/overflow"
        return 0
    fi
    sources_of "$f" | while IFS= read -r base; do
        [ -n "$base" ] || continue
        path="$(resolve_script "$base")"
        [ -n "$path" ] || continue
        closure "$path" "$seen"
    done
}

# var_reachable <var> <script-path> -- var appears in the script or its closure.
# Aborts the whole run if the closure overflowed: a source graph that deep means
# the cycle guard is broken, and any verdict computed from it is untrustworthy.
# Fail closed -- never report "clean" from a traversal that did not terminate.
var_reachable() {
    local var="$1" start="$2" seen="$TMP/seen" f
    : >"$seen"
    rm -f "$TMP/overflow"
    closure "$start" "$seen"
    if [ -f "$TMP/overflow" ]; then
        printf 'check-docs: source closure exceeded %d files from %s — cycle guard broken\n' \
            "$CLOSURE_MAX" "$start" >&2
        exit 2
    fi
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -q -F -- "$var" "$f" 2>/dev/null && return 0
    done <"$seen"
    return 1
}

# is_exempt <var>
is_exempt() {
    [ -f "$EXEMPT" ] || return 1
    grep -v '^[[:space:]]*#' "$EXEMPT" 2>/dev/null \
        | awk '{print $1}' \
        | grep -qxF -- "$1"
}

# --- parse the table -------------------------------------------------------
# A row looks like:  | `VAR` | default | used by |
# Only rows whose Var cell starts with an uppercase letter are env vars; the
# `config.local.sh` row (a file, not a var) is skipped by that rule.
awk -F'|' '/^\|[[:space:]]*`[A-Z]/ {
    v = $2; gsub(/[ `\t]/, "", v)
    u = $4
    print v "\t" u
}' "$TABLE" >"$TMP/rows"

rc=0
findings=0
rows=0

while IFS="$(printf '\t')" read -r var usedby; do
    [ -n "$var" ] || continue
    rows=$((rows + 1))

    # -- forward axis: the var exists somewhere in the code roots.
    # This script is excluded from its own search. Its header comments name
    # MEMORY_SESSIONS_DIR, AI_MEMORY_PROJECTS_ROOT and AI_MEMORY_EXECUTOR_CMD_<key>
    # as worked examples; without the exclusion, a deleted var could be
    # re-documented and pass the forward axis forever on the strength of a comment
    # in the checker that exists to catch it. Found by fixture probe, not review.
    # shellcheck disable=SC2086  # ROOTS is a deliberate space-separated list
    if ! grep -rIl --exclude=check-docs.sh -- "$var" $ROOTS >/dev/null 2>&1; then
        printf 'FAIL  %-28s documented, but absent from all code roots\n' "$var"
        findings=$((findings + 1))
        rc=1
        continue
    fi

    # -- strict axis: the var reaches the script(s) the `Used by` cell names.
    printf '%s' "$usedby" \
        | grep -oE '[A-Za-z0-9_.-]+\.(sh|py)' \
        | sort -u >"$TMP/scripts"

    if [ ! -s "$TMP/scripts" ]; then
        if is_exempt "$var"; then
            continue
        fi
        printf 'FAIL  %-28s `Used by` names no script and is not in .docscheck-exempt\n' "$var"
        findings=$((findings + 1))
        rc=1
        continue
    fi

    while IFS= read -r s; do
        [ -n "$s" ] || continue
        path="$(resolve_script "$s")"
        if [ -z "$path" ]; then
            printf 'FAIL  %-28s `Used by` names %s, which does not exist\n' "$var" "$s"
            findings=$((findings + 1))
            rc=1
            continue
        fi
        case "$s" in
            *.py) grep -q -F -- "$var" "$path" || {
                    printf 'FAIL  %-28s not found in %s\n' "$var" "$s"
                    findings=$((findings + 1)); rc=1
                  } ;;
            *)    var_reachable "$var" "$path" || {
                    printf 'FAIL  %-28s not found in %s (nor anything it sources)\n' "$var" "$s"
                    findings=$((findings + 1)); rc=1
                  } ;;
        esac
    done <"$TMP/scripts"
done <"$TMP/rows"

if [ "$rows" -eq 0 ]; then
    printf 'check-docs: parsed 0 rows from %s — the table format changed\n' "$TABLE" >&2
    exit 2
fi

if [ "$rc" -eq 0 ]; then
    printf 'check-docs: %d rows, 0 findings\n' "$rows"
else
    printf 'check-docs: %d rows, %d finding(s)\n' "$rows" "$findings"
fi
exit "$rc"
