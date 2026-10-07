#!/usr/bin/env bash
# new-project.sh: scaffolds from _template, refuses dup + missing arg.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

# --- missing arg -> exit 1 ---
set +e
out=$(bash "$SCRIPTS_DIR/new-project.sh" 2>&1); code=$?
set -e
assert_exit 1 "$code" "missing arg exits 1"
assert_contains "$out" "usage" "missing arg prints usage"

# --- create -> scaffolds the tree from _template ---
set +e
out=$(bash "$SCRIPTS_DIR/new-project.sh" acme 2>&1); code=$?
set -e
assert_exit 0 "$code" "create exits 0"
assert_file "$MEM/projects/acme/memory.md"           "memory.md scaffolded"
assert_file "$MEM/projects/acme/todo.md"             "todo.md scaffolded"
assert_file "$MEM/projects/acme/plans/.gitkeep"      "plans/ scaffolded"
assert_file "$MEM/projects/acme/archive/working/.gitkeep" "archive/working/ scaffolded"
assert_contains "$(cat "$MEM/projects/acme/memory.md")" "## Known Constraints / Gotchas" "copied required sections"
# Regression (shipped): the copy was verbatim, so new projects carried
# `topic: <name>` and `# Project: <name>`.
assert_contains "$(cat "$MEM/projects/acme/memory.md")" "topic: acme" "topic set to the project name"
assert_contains "$(cat "$MEM/projects/acme/memory.md")" "# Project: acme" "heading set to the project name"
assert_eq "" "$(grep -rl '<name>' "$MEM/projects/acme" || true)" "no <name> placeholder left in the scaffold"

# --- a name outside [A-Za-z0-9._-] -> exit 1, nothing created ---
set +e
out=$(bash "$SCRIPTS_DIR/new-project.sh" 'bad/name' 2>&1); code=$?
set -e
assert_exit 1 "$code" "invalid name exits 1"
assert_not_file "$MEM/projects/bad/name/memory.md" "invalid name creates nothing"

# --- duplicate -> exit 1, does not clobber ---
set +e
out=$(bash "$SCRIPTS_DIR/new-project.sh" acme 2>&1); code=$?
set -e
assert_exit 1 "$code" "duplicate exits 1"
assert_contains "$out" "already exists" "duplicate reports already-exists"

finish
