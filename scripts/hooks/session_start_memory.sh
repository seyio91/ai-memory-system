#!/usr/bin/env bash
# SessionStart hook: inject full memory (identity + project + index + working) once
# when the session loads.
set -euo pipefail

_ss_resolve() {
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

_ss_self="$(_ss_resolve "${BASH_SOURCE[0]}")"
# This script lives in scripts/hooks/, so the repo root is two levels up.
_SS_REPO="$(cd "$(dirname "$_ss_self")/../.." && pwd)"
. "$_SS_REPO/scripts/hooks/lib.sh"

# Bare/isolated executor opt-out: a lean review run (codex --executor-bare) exports
# AI_MEMORY_SKIP_INJECT=1 to suppress ALL memory injection — no startup base, and no
# compaction sentinel. Mirrors the same gate in inject.sh so both hook faces honor it.
[ -n "${AI_MEMORY_SKIP_INJECT:-}" ] && exit 0

INPUT=$(cat)
CWD=$(json_field "$INPUT" "cwd")
SOURCE=$(json_field "$INPUT" "source")
SESSION_ID=$(json_field "$INPUT" "session_id")
PROJECT=$(detect_project "$CWD")

# After a compaction, SessionStart additionalContext is unreliable. Instead flag
# the session so the next UserPromptSubmit re-injects the full payload through the
# compaction-proof per-prompt channel, then stop (no inline injection here).
if [ "$SOURCE" = "compact" ]; then
    if [ -n "$PROJECT" ]; then
        SENT=$(recompact_sentinel "$SESSION_ID")
        if [ -n "$SENT" ]; then
            mkdir -p "$STATE_DIR"
            : > "$SENT"
            # Prune sentinels from sessions that compacted but never resumed.
            find "$STATE_DIR" -name '*.recompact' -mtime +2 -delete 2>/dev/null || true
        fi
    fi
    exit 0
fi

OUTPUT=$(render_full "$PROJECT")
[ -z "$OUTPUT" ] && exit 0

ESC=$(json_escape "$OUTPUT")
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$ESC"
