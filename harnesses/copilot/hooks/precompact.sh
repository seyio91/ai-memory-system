#!/usr/bin/env bash
# precompact.sh — Copilot preCompact hook: arm the shared recompact sentinel.
set -euo pipefail

_pc_resolve() {
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

_pc_self="$(_pc_resolve "${BASH_SOURCE[0]}")"
_PC_REPO="$(cd "$(dirname "$_pc_self")/../../.." && pwd)"
. "$_PC_REPO/scripts/hooks/lib.sh"

emit_empty() {
    printf '{}\n'
    exit 0
}

[ -n "${AI_MEMORY_SKIP_INJECT:-}" ] && emit_empty

INPUT="$(cat)"
SESSION_ID="$(json_field "$INPUT" "sessionId")"
if [ -z "$SESSION_ID" ]; then
    SESSION_ID="$(json_field "$INPUT" "session_id")"
fi

SENT="$(recompact_sentinel "$SESSION_ID")"
if [ -n "$SENT" ]; then
    mkdir -p "$STATE_DIR"
    : > "$SENT"
    find "$STATE_DIR" -name '*.recompact' -mtime +2 -delete 2>/dev/null || true
fi

emit_empty
