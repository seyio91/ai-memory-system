#!/usr/bin/env bash
# posttooluse.sh — Copilot postToolUse hook: re-inject once after compaction.
set -euo pipefail

_pt_resolve() {
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

_pt_self="$(_pt_resolve "${BASH_SOURCE[0]}")"
_PT_REPO="$(cd "$(dirname "$_pt_self")/../../.." && pwd)"
. "$_PT_REPO/scripts/hooks/lib.sh"

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
CWD="$(json_field "$INPUT" "cwd")"

SENT="$(recompact_sentinel "$SESSION_ID")"
[ -n "$SENT" ] && [ -f "$SENT" ] || emit_empty

PROJECT="$(detect_project "$CWD")"
export AI_MEMORY_CWD="$CWD"
export AI_MEMORY_HOOK_FORMAT="${AI_MEMORY_HOOK_FORMAT:-md}"

PAYLOAD="$(render_full "$PROJECT")"
rm -f "$SENT"

[ -n "$PAYLOAD" ] || emit_empty

printf '{"additionalContext":%s}\n' "$(json_escape "$PAYLOAD")"
