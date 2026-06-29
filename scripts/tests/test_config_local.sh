#!/usr/bin/env bash
# _lib.sh config loader: a gitignored config.local.sh next to the memory tree
# ($MEMORY_DIR) is sourced on load, so per-environment vars reach scripts.
. "$(dirname "$0")/_assert.sh"

# Each case runs in a command-substitution subshell that sources _lib.sh fresh
# with MEMORY_DIR pinned to a sandbox; assertions run in this (parent) shell so
# the pass/fail counters survive.

# --- no config.local.sh -> default applies ---
SB1="$(new_sandbox)"
got=$( export MEMORY_DIR="$SB1"; unset AI_MEMORY_PROJECTS_ROOT
       . "$SCRIPTS_DIR/_lib.sh"; projects_root )
assert_eq "$HOME/Projects" "$got" "no config.local.sh -> default projects_root"

# --- config.local.sh sets AI_MEMORY_PROJECTS_ROOT ---
SB2="$(new_sandbox)"
printf 'export AI_MEMORY_PROJECTS_ROOT="/tmp/from-config"\n' > "$SB2/config.local.sh"
got=$( export MEMORY_DIR="$SB2"; unset AI_MEMORY_PROJECTS_ROOT
       . "$SCRIPTS_DIR/_lib.sh"; projects_root )
assert_eq "/tmp/from-config" "$got" "config.local.sh sets projects_root"

# --- config.local.sh wins over a pre-set env var (assignment runs at source) ---
SB3="$(new_sandbox)"
printf 'export AI_MEMORY_PROJECTS_ROOT="/tmp/config-wins"\n' > "$SB3/config.local.sh"
got=$( export MEMORY_DIR="$SB3"; export AI_MEMORY_PROJECTS_ROOT="/tmp/env-loses"
       . "$SCRIPTS_DIR/_lib.sh"; projects_root )
assert_eq "/tmp/config-wins" "$got" "config.local.sh overrides pre-set env var"

# --- config.local.sh can set arbitrary vars (e.g. MEMORY_TASK_PROVIDER) ---
SB4="$(new_sandbox)"
printf 'export MEMORY_TASK_PROVIDER="notion"\n' > "$SB4/config.local.sh"
got=$( export MEMORY_DIR="$SB4"; unset MEMORY_TASK_PROVIDER
       . "$SCRIPTS_DIR/_lib.sh"; printf '%s' "${MEMORY_TASK_PROVIDER:-}" )
assert_eq "notion" "$got" "config.local.sh exports arbitrary vars"

# --- config is read from MEMORY_DIR, not the real tree (isolation) ---
SB5="$(new_sandbox)"
printf 'export AI_MEMORY_PROJECTS_ROOT="/tmp/sandbox-only"\n' > "$SB5/config.local.sh"
got=$( export MEMORY_DIR="$SB5"; unset AI_MEMORY_PROJECTS_ROOT
       . "$SCRIPTS_DIR/_lib.sh"; printf '%s' "$MEMORY_DIR" )
assert_eq "$SB5" "$got" "MEMORY_DIR override honored (config sourced from sandbox)"

rm -rf "$SB1" "$SB2" "$SB3" "$SB4" "$SB5"
finish
