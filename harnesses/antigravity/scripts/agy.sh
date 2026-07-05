#!/usr/bin/env bash
# agy.sh — Antigravity launch wrapper (refresh=launch). Rebuilds the memory
# context (AGENTS.md-style) from the memory tree via the shared builder, then
# exec's `agy` with all arguments passed through. The Antigravity analogue of
# codex-mem.sh: alias `agy` to this so every launch sees fresh memory.
#
#   agy.sh [agy args...]              # rebuild context, then `agy ...`
#   alias agy='~/.claude-memory/harnesses/antigravity/scripts/agy.sh'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MEM_SCRIPTS="$(cd "$SCRIPT_DIR/../../../scripts" && pwd)"

# Where Antigravity reads the global context, and the never-touched user overlay.
AGY_CONTEXT="${AGY_CONTEXT_FILE:-$HOME/.gemini/config/AGENTS.md}"
AGY_OVERLAY="${AGY_OVERLAY_FILE:-$HOME/.gemini/config/AGENTS.local.md}"

if ! command -v agy >/dev/null 2>&1; then
    echo "agy.sh: agy not found in PATH" >&2
    exit 1
fi

bash "$MEM_SCRIPTS/build-context-md.sh" "$AGY_CONTEXT" "agy" "$AGY_OVERLAY"

exec agy "$@"
