#!/usr/bin/env bash
# skill-data root helpers + CLI.
. "$(dirname "$0")/_assert.sh"

LIB="$SCRIPTS_DIR/_lib.sh"
SDD="$SCRIPTS_DIR/skill-data-dir.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"
unset AI_MEMORY_SKILL_DATA

. "$LIB"

assert_eq "$MEM/.skill-data" "$(skill_data_root)" "skill_data_root defaults to MEMORY_DIR/.skill-data"

export AI_MEMORY_SKILL_DATA="$MEM/custom-data"
assert_eq "$MEM/custom-data" "$(skill_data_root)" "skill_data_root honors AI_MEMORY_SKILL_DATA"

out="$(bash "$SDD" renovate-manager)"
assert_eq "$MEM/custom-data/renovate-manager" "$out" "skill-data-dir prints the skill dir"
assert_file "$MEM/custom-data/renovate-manager" "skill-data-dir creates the skill dir"

finish
