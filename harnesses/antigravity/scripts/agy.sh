#!/usr/bin/env bash
# agy.sh — Antigravity launch wrapper. Antigravity is a `hook` archetype: memory
# is injected live per model call by the PreInvocation hook
# (harnesses/antigravity/hooks/preinvocation.sh), NOT materialized into a file.
# This wrapper's only job is to resolve the active project from the launch cwd and
# export it — plus MEMORY_DIR and the cwd — into agy's environment, because
# Antigravity's hook payload carries no workspace handle; the hook reads these env
# vars to pick which project's memory to inject (env inheritance verified live).
# Alias `agy` to this so every launch (interactive, or `agy -p` executor
# delegation) resolves the right project.
#
#   agy.sh [agy args...]
#   alias agy='~/.claude-memory/harnesses/antigravity/scripts/agy.sh'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$(cd "$SCRIPT_DIR/../../../scripts" && pwd)/_lib.sh"   # MEMORY_DIR + detect_active_project

if ! command -v agy >/dev/null 2>&1; then
    echo "agy.sh: agy not found in PATH" >&2
    exit 1
fi

export MEMORY_DIR
# Masks detect_active_project's unpinned-project status under set -e.
# shellcheck disable=SC2155
export AI_MEMORY_PROJECT="$(detect_active_project)"
export AI_MEMORY_CWD="$PWD"

exec agy "$@"
