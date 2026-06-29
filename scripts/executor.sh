#!/usr/bin/env bash
# Select and dispatch the orchestrator's executor — the selection layer above
# codex-mem.sh. Reads config.local.sh (via _lib.sh).
#
#   executor.sh --which            -> prints 'subagent' or 'cli:<key>'
#   executor.sh --run "<prompt>"   -> execs the CLI executor, or prints
#                                     EXECUTOR_USE_SUBAGENT (exit 3) for the subagent plane
#   executor.sh --show             -> human-readable diagnostics
#
# Exit codes: 0 resolved | 1 preferred unavailable + no fallback |
#             2 unknown executor / usage error | 3 --run resolved to subagent
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

EXECUTOR="${AI_MEMORY_EXECUTOR:-claude-subagent}"
# Unset -> default claude-subagent; set-but-empty -> no fallback (hard-fail).
FALLBACK="${AI_MEMORY_EXECUTOR_FALLBACK-claude-subagent}"

# Resolve a single executor key with NO fallback.
# Prints 'subagent' or 'cli:<key>' on success (0).
resolve_one() {
    local key="$1"
    if [ "$key" = "claude-subagent" ]; then
        printf 'subagent\n'; return 0
    fi
    printf 'executor: unknown executor %s\n' "$key" >&2
    return 2
}

resolve() { resolve_one "$EXECUTOR"; }

MODE="${1:-}"
case "$MODE" in
    --which) resolve; exit $? ;;
    *) printf 'usage: executor.sh --which | --run "<prompt>" | --show\n' >&2; exit 2 ;;
esac
