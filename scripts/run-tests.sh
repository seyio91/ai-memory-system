#!/usr/bin/env bash
#
# run-tests.sh — end-to-end test runner for the memory system.
#
# Runs the full scripts/tests/test_*.sh suite, then the scripts/taskprovider/tests/
# Python unittest suite, then lint-memory.sh, validate-skills.sh, a doc-vs-code
# consistency check (check-docs.sh), and a shellcheck static-analysis stage —
# all six gate the exit code — in a HERMETIC
# environment: it scrubs the developer-shell variables that
# would otherwise steer a test into a live backend or the real tree
# (MEMORY_TASK_PROVIDER, NOTION_*, MEMORY_DIR, AI_MEMORY_PROJECTS_ROOT,
# AI_MEMORY_EXECUTOR*, AI_MEMORY_ROLE). Each test owns its own sandbox + cleanup;
# this runner just guarantees a clean baseline so results are reproducible on any
# machine / in CI.
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
        -u AI_MEMORY_EXECUTOR -u AI_MEMORY_EXECUTOR_FALLBACK \
        -u AI_MEMORY_ROLE "$@"
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

# Python suite. Lives outside scripts/tests/ (it is a package, not a bash script),
# so the loop above cannot see it — it went ungated until 2026-07-09. Enforce the
# provider<->test pairing here too: adding providers/<name>.py needs no factory edit
# (by design), so nothing else would ever notice a provider shipping with no test.
PY_TESTS="$MEM/scripts/taskprovider/tests"
py_status="skipped"
py_rc=0
if [ -d "$PY_TESTS" ]; then
    printf '\n== taskprovider (python) ==\n'
    if ! command -v python3 >/dev/null 2>&1; then
        py_status="setup error (no python3)"
        py_rc=2
        printf '  ERROR no python3 on PATH; the taskprovider suite cannot run\n'
    else
        pair_out="$(bash "$HERE/check-provider-tests.sh" "$MEM/scripts/taskprovider" 2>&1)"
        if [ $? -ne 0 ]; then
            py_rc=1
            printf '%s\n' "$pair_out" | sed 's/^/  /'
        fi
        hermetic env PYTHONPATH="$MEM/scripts" python3 -m unittest discover \
            -s "$PY_TESTS" -t "$MEM/scripts" >"$LOGDIR/py.log" 2>&1
        unittest_rc=$?
        ran="$(grep -E '^Ran [0-9]+ test' "$LOGDIR/py.log" | tail -1)"
        if [ "$unittest_rc" -ne 0 ]; then
            py_rc=1
            sed 's/^/        /' "$LOGDIR/py.log"
        fi
        if [ "$py_rc" -eq 0 ]; then
            py_status="clean (${ran:-no tests found})"
            printf '  PASS  %-32s %s\n' "unittest discover" "$ran"
        else
            py_status="failed"
        fi
    fi
fi

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

# Doc-vs-code. Nothing else tests a doc against the code it describes, and doc
# rot here is a recorded, recurring gotcha. Gate on the exit code, not on output:
# check-docs.sh exits 0 clean / 1 findings / 2 setup error, and an exit-2 (table
# format changed, so zero rows parsed) must NOT masquerade as clean — that is the
# fail-open shape this stage exists to prevent.
dvc_status="skipped"
dvc_rc=0
printf '\n== doc-vs-code ==\n'
hermetic bash "$HERE/check-docs.sh" >"$LOGDIR/dvc.log" 2>&1; dvc_rc=$?
if [ "$dvc_rc" -eq 0 ]; then
    dvc_status="clean ($(tail -1 "$LOGDIR/dvc.log"))"
    printf '  PASS  %-32s %s\n' "check-docs" "$(tail -1 "$LOGDIR/dvc.log")"
else
    sed 's/^/  /' "$LOGDIR/dvc.log" || true
    if [ "$dvc_rc" -eq 1 ]; then
        dvc_status="$(grep -c '^FAIL' "$LOGDIR/dvc.log" 2>/dev/null || printf '0') finding(s)"
    else
        dvc_status="setup error (exit $dvc_rc)"
    fi
fi

# Static analysis. Two floors against the single root .shellcheckrc (a nested rc
# would REPLACE it, not merge): production at `info` because SC2086 — unquoted
# expansion — is info-level and a `warning` gate could never fire on it; tests at
# `warning` because their info-level hits are test idioms (SC2015 `[ c ] && _ok ||
# _bad`, SC2030/SC2031 deliberate subshells). shellcheck resolves the rc from each
# file's parent dirs, so cwd is irrelevant.
#
# NB: a comment whose line STARTS with "# shellcheck " is parsed as a directive, not
# prose — hence the "NB:" prefixes here. (SC1072/SC1073, caught by this very stage.)
#
# NB: shellcheck is a DEV/CI-only dependency; the system's runtime bet is zero
# dependencies. If it is absent we SKIP with a notice and do not gate — otherwise a
# fresh machine (or a consumer instance running the suite) fails for lacking a linter.
sc_status="skipped"
sc_rc=0
printf '\n== shellcheck ==\n'
if ! command -v shellcheck >/dev/null 2>&1; then
    sc_status="skipped (not installed; dev/CI only)"
    printf '  SKIP  shellcheck not on PATH — static analysis not run\n'
else
    find "$MEM/scripts" "$MEM/harnesses" -name '*.sh' -type f \
        ! -path "$MEM/scripts/tests/*" -exec shellcheck -S info -f gcc {} + \
        >"$LOGDIR/sc.prod" 2>/dev/null
    find "$MEM/scripts/tests" -name '*.sh' -type f \
        -exec shellcheck -S warning -f gcc {} + >"$LOGDIR/sc.test" 2>/dev/null
    sc_prod=$(grep -c . "$LOGDIR/sc.prod" 2>/dev/null); sc_prod=${sc_prod:-0}
    sc_test=$(grep -c . "$LOGDIR/sc.test" 2>/dev/null); sc_test=${sc_test:-0}
    if [ "$sc_prod" -gt 0 ] || [ "$sc_test" -gt 0 ]; then
        sc_rc=1
        sed "s|^$MEM/||; s/^/  /" "$LOGDIR/sc.prod" "$LOGDIR/sc.test" 2>/dev/null | grep -v '^  ==>' || true
        sc_status="$((sc_prod + sc_test)) finding(s)"
    else
        sc_status="clean (prod @ info, tests @ warning)"
        printf '  PASS  %-32s %s\n' "shellcheck" "0 findings"
    fi
fi

printf '\n== summary ==\n'
printf '  tests: %d passed, %d failed%s\n' "$pass" "$fail" \
    "$( [ -n "$failed_names" ] && printf ' —%s' "$failed_names" )"
printf '  python: %s\n' "$py_status"
[ "$DO_LINT" = 1 ] && printf '  lint:  %s\n' "$lint_status"
[ "$DO_LINT" = 1 ] && printf '  skills: %s\n' "$vs_status"
printf '  doc-vs-code: %s\n' "$dvc_status"
printf '  shellcheck: %s\n' "$sc_status"

[ "$fail" -eq 0 ] && [ "$py_rc" -eq 0 ] && [ "$lint_errors" -eq 0 ] && [ "$vs_rc" -eq 0 ] \
    && [ "$dvc_rc" -eq 0 ] && [ "$sc_rc" -eq 0 ]
