#!/usr/bin/env bash
# check-provider-tests.sh: every taskprovider provider must ship a matching test.
. "$(dirname "$0")/_assert.sh"

CHECK="$SCRIPTS_DIR/check-provider-tests.sh"

TMP="$(mktemp -d 2>/dev/null || mktemp -d -t pairing)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/providers" "$TMP/tests"
: >"$TMP/providers/__init__.py"
: >"$TMP/tests/__init__.py"

printf 'PROVIDER = None\n' >"$TMP/providers/local.py"
: >"$TMP/tests/test_local.py"
set +e
out=$(bash "$CHECK" "$TMP" 2>&1); code=$?
set -e
assert_exit 0 "$code" "a paired provider passes"

printf 'PROVIDER = None\n' >"$TMP/providers/jira.py"
set +e
out=$(bash "$CHECK" "$TMP" 2>&1); code=$?
set -e
assert_exit 1 "$code" "a provider with no test fails"
assert_contains "$out" "provider jira has no tests/test_jira.py" "error names the unpaired provider"

rm -f "$TMP/providers/jira.py"
set +e
out=$(bash "$CHECK" "$TMP" 2>&1); code=$?
set -e
assert_exit 0 "$code" "__init__.py is not mistaken for a provider"

set +e
out=$(bash "$CHECK" "$TMP/nope" 2>&1); code=$?
set -e
assert_exit 2 "$code" "missing package dir is a setup error, not a pass"

set +e
out=$(bash "$CHECK" 2>&1); code=$?
set -e
assert_exit 0 "$code" "the real taskprovider tree is fully paired"

finish
