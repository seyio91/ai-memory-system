#!/usr/bin/env bash
# UserPromptSubmit-style injector. The hook envelope is shared by Claude and
# Codex; content rendering is selected with AI_MEMORY_HOOK_FORMAT.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

# Bare/isolated executor opt-out: a lean review run (codex --executor-bare) exports
# AI_MEMORY_SKIP_INJECT=1 to suppress ALL memory injection — base AND breadcrumb.
# Mirrors the same gate in session_start_memory.sh.
[ -n "${AI_MEMORY_SKIP_INJECT:-}" ] && exit 0

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

emit_chunked() {
    local payload="$1" esc
    [ -z "$payload" ] && exit 0
    if ! esc=$(emit_hook_chunk "$payload" | json_escape_nonempty_stream); then
        exit 0
    fi
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":%s}}\n' "$EVENT" "$esc"
    exit 0
}

SENT="$(recompact_sentinel "$SESSION_ID")"
if [ -n "$SENT" ] && [ -f "$SENT" ]; then
    if hook_chunk_is_last; then
        rm -f "$SENT"
    fi
    [ -n "$PROJECT" ] && emit_chunked "$(render_full "$PROJECT")"
    exit 0
fi

# The explicit-reload trigger re-injects the full payload, so it must fan out
# across chunks exactly like the post-compact path (a single message gets capped).
case "$PROMPT" in
    *"$TRIGGER"*) emit_chunked "$(render_full "$PROJECT")" ;;
esac

if ! hook_chunk_is_first; then
    exit 0
fi

emit "$(render_breadcrumb "$PROJECT" "$CWD")"
