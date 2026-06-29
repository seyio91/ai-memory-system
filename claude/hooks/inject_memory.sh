#!/usr/bin/env bash
# UserPromptSubmit hook. This is the compaction-proof channel: its additionalContext
# rides the newest turn every prompt, so it cannot be summarized away (the
# SessionStart block can). Three cases:
#   1. First prompt after a compaction (sentinel set by session_start_memory.sh)
#      -> re-inject the FULL payload, then clear the sentinel.
#   2. Prompt contains the "@memory" marker -> re-inject the FULL payload.
#   3. Otherwise -> lightweight breadcrumb (project pointer + memory file paths +
#      a re-read directive) so the anchor and recovery hints are always fresh.
set -euo pipefail

source "$(dirname "$0")/memory_common.sh"

TRIGGER="${MEMORY_RELOAD_TRIGGER:-@memory}"

INPUT=$(cat)
PROMPT=$(json_field "$INPUT" "prompt")
CWD=$(json_field "$INPUT" "cwd")
SESSION_ID=$(json_field "$INPUT" "session_id")
PROJECT=$(detect_project "$CWD")

emit() { # emit <payload-string> ; exits
    [ -z "$1" ] && exit 0
    printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$(json_escape "$1")"
    exit 0
}

# 1) Post-compaction reload: consume the sentinel and re-inject full payload.
SENT=$(recompact_sentinel "$SESSION_ID")
if [ -n "$SENT" ] && [ -f "$SENT" ]; then
    rm -f "$SENT"
    [ -n "$PROJECT" ] && emit "$(assemble_full_memory "$PROJECT")"
fi

# 2) Explicit full reload on request.
case "$PROMPT" in
    *"$TRIGGER"*) emit "$(assemble_full_memory "$PROJECT")" ;;
esac

# 3) Lightweight breadcrumb. Nothing to assert without a project.
emit "$(assemble_breadcrumb "$PROJECT" "$CWD")"
