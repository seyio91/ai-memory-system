#!/usr/bin/env bash
#
# run-tests.sh — end-to-end test runner for the memory system.
#
# Runs the full scripts/tests/test_*.sh suite, then the lint-memory.sh content
# check, in a HERMETIC environment: it scrubs the developer-shell variables that
# would otherwise steer a test into a live backend or the real tree
# (MEMORY_TASK_PROVIDER, NOTION_*, MEMORY_DIR, AI_MEMORY_PROJECTS_ROOT,
# AI_MEMORY_EXECUTOR*). Each test owns its own sandbox + cleanup; this runner just
# guarantees a clean baseline so results are reproducible on any machine / in CI.
#
# Usage: run-tests.sh [--no-lint] [-v]
#   --no-lint   skip the lint-memory.sh pass (tests only)
#   -v          stream each test's full output (default: only failures)
#
# Exit: 0 if everything passes, 1 otherwise.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
MEM="$(cd "$HERE/.." && pwd)"
TESTS="$HERE/tests"

DO_LINT=1
VERBOSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --no-lint) DO_LINT=0; shift ;;
        -v|--verbose) VERBOSE=1; shift ;;
        *) echo "run-tests: unknown arg: $1" >&2; exit 2 ;;
    esac
done

[ -d "$TESTS" ] || { echo "run-tests: no tests dir at $TESTS" >&2; exit 2; }

# Hermetic baseline — nothing from the invoking shell should reach a test.
hermetic() {
    env -u MEMORY_TASK_PROVIDER -u NOTION_STATUS_KIND -u NOTION_TOKEN \
        -u NOTION_DATA_SOURCE_ID -u MEMORY_DIR -u AI_MEMORY_PROJECTS_ROOT \
        -u AI_MEMORY_EXECUTOR -u AI_MEMORY_EXECUTOR_FALLBACK "$@"
}

LOGDIR="$(mktemp -d 2>/dev/null || mktemp -d -t runtests)"
trap 'rm -rf "$LOGDIR"' EXIT

pass=0 fail=0
failed_names=""

printf '== test suite (hermetic) ==\n'
for t in "$TESTS"/test_*.sh; do
    [ -e "$t" ] || continue
    name="$(basename "$t")"
    log="$LOGDIR/$name.log"
    if hermetic bash "$t" >"$log" 2>&1; then
        printf '  PASS  %-32s %s\n' "$name" "$(grep -E ' passed,' "$log" | tail -1)"
        pass=$((pass + 1))
        [ "$VERBOSE" = 1 ] && sed 's/^/        /' "$log"
    else
        printf '  FAIL  %s\n' "$name"
        sed 's/^/        /' "$log"
        fail=$((fail + 1))
        failed_names="$failed_names $name"
    fi
done

lint_status="skipped"
lint_errors=0
if [ "$DO_LINT" = 1 ]; then
    printf '\n== lint-memory ==\n'
    # lint-memory.sh exits 1 on ANY finding (warn or error), so its exit code
    # can't gate the run. Failure = a real ERROR: line; WARN: lines are advisory.
    hermetic bash "$HERE/lint-memory.sh" >"$LOGDIR/lint.log" 2>&1 || true
    # grep -c always prints a count (and exits 1 when 0 — harmless here).
    lint_errors=$(grep -c '^ERROR' "$LOGDIR/lint.log" 2>/dev/null); lint_errors=${lint_errors:-0}
    lint_warns=$(grep -c '^WARN' "$LOGDIR/lint.log" 2>/dev/null); lint_warns=${lint_warns:-0}
    grep -E '^(WARN|ERROR)' "$LOGDIR/lint.log" | sed 's/^/  /' || true
    if [ "$lint_errors" -gt 0 ]; then
        lint_status="$lint_errors error(s)"
    else
        lint_status="clean ($lint_warns warning(s))"
    fi
fi

vs_status="skipped"
vs_rc=0
if [ "$DO_LINT" = 1 ]; then
    printf '\n== validate-skills ==\n'
    # Exits 0 clean, 1 on ERROR, 2 on setup error. Gate on the exit code so an
    # exit-2 (no skills dir) can't masquerade as clean (it emits no ERROR: line).
    hermetic bash "$HERE/validate-skills.sh" >"$LOGDIR/vs.log" 2>&1; vs_rc=$?
    vs_warns=$(grep -c '^WARN' "$LOGDIR/vs.log" 2>/dev/null); vs_warns=${vs_warns:-0}
    if [ "$vs_rc" -eq 0 ]; then
        vs_status="clean ($vs_warns warning(s))"
    elif [ "$vs_rc" -eq 1 ]; then
        vs_errors=$(grep -c '^ERROR' "$LOGDIR/vs.log" 2>/dev/null); vs_errors=${vs_errors:-0}
        vs_status="$vs_errors error(s)"
    else
        vs_status="setup error (exit $vs_rc)"
    fi
    grep -E '^(WARN|ERROR)' "$LOGDIR/vs.log" | sed 's/^/  /' || true
fi

printf '\n== summary ==\n'
printf '  tests: %d passed, %d failed%s\n' "$pass" "$fail" \
    "$( [ -n "$failed_names" ] && printf ' —%s' "$failed_names" )"
[ "$DO_LINT" = 1 ] && printf '  lint:  %s\n' "$lint_status"
[ "$DO_LINT" = 1 ] && printf '  skills: %s\n' "$vs_status"

[ "$fail" -eq 0 ] && [ "$lint_errors" -eq 0 ] && [ "$vs_rc" -eq 0 ]
