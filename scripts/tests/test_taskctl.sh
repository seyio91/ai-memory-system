#!/usr/bin/env bash
# taskctl wrapper: ping + capture + list round-trip against a temp MEMORY_DIR
# using the local provider (default). Proves the wrapper wires PYTHONPATH and
# MEMORY_DIR through to the Python CLI.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"
mkdir -p "$MEM/projects/demo"

TASKCTL="$SCRIPTS_DIR/taskctl"
assert_file "$TASKCTL" "taskctl exists"
[ -x "$TASKCTL" ] && _ok "taskctl is executable" || { _bad "taskctl is executable"; }

set +e
out=$("$TASKCTL" ping 2>&1); code=$?
set -e
assert_exit 0 "$code" "ping exits 0"
assert_contains "$out" '"ok": true' "ping returns JSON ok"

set +e
out=$("$TASKCTL" capture demo "Wrapper Task" "via taskctl" 2>&1); code=$?
set -e
assert_exit 0 "$code" "capture exits 0"
assert_contains "$out" '"ref": "wrapper-task"' "capture returns ref"
assert_file "$MEM/tasks/wrapper-task.md" "task file written under tasks/"

set +e
out=$("$TASKCTL" list demo backlog 2>&1); code=$?
set -e
assert_exit 0 "$code" "list exits 0"
assert_contains "$out" '"ref": "wrapper-task"' "list includes captured task"

# MEMORY_DIR override is honored: a different empty root sees no tasks.
OTHER="$(new_sandbox)"
mkdir -p "$OTHER/projects/demo"
set +e
out=$(MEMORY_DIR="$OTHER" "$TASKCTL" list demo backlog 2>&1); code=$?
set -e
rm -rf "$OTHER"
assert_exit 0 "$code" "list (other root) exits 0"
assert_contains "$out" '"tasks": []' "MEMORY_DIR override isolates the store"

finish
