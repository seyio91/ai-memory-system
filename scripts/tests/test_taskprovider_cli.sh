#!/usr/bin/env bash
# taskprovider CLI: JSON boundary against the local provider.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"
export MEMORY_TASK_PROVIDER=local
export PYTHONPATH="$SCRIPTS_DIR"
seed_min_tree "$MEM"
mkdir -p "$MEM/projects/alpha"

set +e
out=$(python3 -m taskprovider ping 2>&1); code=$?
set -e
assert_exit 0 "$code" "ping exits 0"
assert_contains "$out" '"ok": true' "ping returns JSON"

set +e
out=$(python3 -m taskprovider nope 2>&1); code=$?
set -e
assert_exit 2 "$code" "unknown verb exits non-zero"
assert_contains "$out" '"error"' "unknown verb returns JSON error"

set +e
out=$(python3 -m taskprovider capture alpha "CLI Task" "from cli" 2>&1); code=$?
set -e
assert_exit 0 "$code" "capture exits 0"
assert_contains "$out" '"ref": "cli-task"' "capture returns ref"

long_summary="$(python3 -c 'print("x" * 501)')"
set +e
out=$(python3 -m taskprovider capture alpha "Too Long" "$long_summary" 2>&1); code=$?
set -e
assert_exit 1 "$code" "over-cap capture exits non-zero"
set +e
json_error=$(printf '%s' "$out" | python3 -c 'import json, sys; print(json.load(sys.stdin)["error"])' 2>/dev/null); parse_code=$?
set -e
assert_exit 0 "$parse_code" "over-cap capture stdout parses as JSON error"
assert_contains "$json_error" "summary is 501 chars; maximum is 500." "over-cap capture error includes summary cap"

set +e
out=$(python3 -m taskprovider list alpha backlog 2>&1); code=$?
set -e
assert_exit 0 "$code" "list exits 0"
assert_contains "$out" '"ref": "cli-task"' "list includes captured task"
assert_contains "$out" '"status": "backlog"' "list includes backlog status"

set +e
out=$(python3 -m taskprovider set-status cli-task started 2>&1); code=$?
set -e
assert_exit 0 "$code" "set-status exits 0"
assert_contains "$out" '"ok": true' "set-status returns JSON"

set +e
out=$(python3 -m taskprovider list alpha started 2>&1); code=$?
set -e
assert_exit 0 "$code" "started list exits 0"
assert_contains "$out" '"ref": "cli-task"' "started list includes task"
assert_contains "$out" '"status": "started"' "started list includes status"

finish
