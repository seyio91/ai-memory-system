#!/usr/bin/env bash
# SessionStart hook: inject full memory (identity + project + index + working) once
# when the session loads.
set -euo pipefail

source "$(dirname "$0")/memory_common.sh"

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

OUTPUT=$(assemble_full_memory "$PROJECT")
[ -z "$OUTPUT" ] && exit 0

ESC=$(json_escape "$OUTPUT")
printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":%s}}\n' "$ESC"
