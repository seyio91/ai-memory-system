#!/usr/bin/env bash
# Compatibility shim (release N — delete in N+1).
#
# Before the codex-sessionstart-base-load flip, ~/.codex/hooks.json registered
# THIS path for SessionStart (compaction_arm). The flip routes SessionStart
# through the shared scripts/hooks/session_start_memory.sh instead, and re-running
# install.sh rewrites hooks.json to point there. But hooks.json is only rewritten
# by install.sh: a manual `git pull` that crosses the flip without re-installing
# would leave a stale entry aimed here. This shim keeps that entry working by
# delegating to the shared script — which handles BOTH branches (source=startup →
# inject the full base; source=compact → arm the recompact sentinel). It defaults
# AI_MEMORY_HOOK_FORMAT=md because the stale entry was registered without the
# format env the engine now threads in for codex.
set -euo pipefail

: "${AI_MEMORY_HOOK_FORMAT:=md}"
export AI_MEMORY_HOOK_FORMAT

_arm_resolve() {
    local p="$1" t
    while [ -L "$p" ]; do
        t="$(readlink "$p")"
        case "$t" in
            /*) p="$t" ;;
            *)  p="$(dirname "$p")/$t" ;;
        esac
    done
    ( cd "$(dirname "$p")" && printf '%s/%s\n' "$(pwd)" "$(basename "$p")" )
}

_arm_self="$(_arm_resolve "${BASH_SOURCE[0]}")"
_ARM_REPO="$(cd "$(dirname "$_arm_self")/../../.." && pwd)"
exec bash "$_ARM_REPO/scripts/hooks/session_start_memory.sh" "$@"
