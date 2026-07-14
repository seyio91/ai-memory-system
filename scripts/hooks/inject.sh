#!/usr/bin/env bash
# UserPromptSubmit-style injector. The hook envelope is shared by Claude and
# Codex; content rendering is selected with AI_MEMORY_HOOK_FORMAT.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

TRIGGER="${MEMORY_RELOAD_TRIGGER:-@memory}"
EVENT="${AI_MEMORY_HOOK_EVENT:-UserPromptSubmit}"

INPUT="$(cat)"
PROMPT="$(json_field "$INPUT" "prompt")"
CWD="$(json_field "$INPUT" "cwd")"
SESSION_ID="$(json_field "$INPUT" "session_id")"
PROJECT="$(detect_project "$CWD")"
export AI_MEMORY_CWD="$CWD"

emit() {
    [ -z "$1" ] && exit 0
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":%s}}\n' "$EVENT" "$(json_escape "$1")"
    exit 0
}

SENT="$(recompact_sentinel "$SESSION_ID")"
if [ -n "$SENT" ] && [ -f "$SENT" ]; then
    rm -f "$SENT"
    [ -n "$PROJECT" ] && emit "$(render_full "$PROJECT")"
fi

case "$PROMPT" in
    *"$TRIGGER"*) emit "$(render_full "$PROJECT")" ;;
esac

emit "$(render_breadcrumb "$PROJECT" "$CWD")"
