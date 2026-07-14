#!/usr/bin/env bash
# Codex SessionStart hook (source=compact only): flag the session so the next
# UserPromptSubmit re-injects the full memory payload through inject.sh's
# compaction-proof per-prompt channel, then exit. Standalone mirror of Claude's
# session_start_memory.sh compact branch — Claude's hook stays untouched.
set -euo pipefail

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
. "$_ARM_REPO/scripts/hooks/lib.sh"

INPUT=$(cat)
SOURCE=$(json_field "$INPUT" "source")
SESSION_ID=$(json_field "$INPUT" "session_id")
CWD=$(json_field "$INPUT" "cwd")
PROJECT=$(detect_project "$CWD")

# Arm on a compaction event, staying agnostic to which one the manifest wires:
#   - SessionStart carries source=compact (Claude parity; the current default)
#   - PreCompact / PostCompact carry a `trigger` field and NO `source`
# Reject only an explicit non-compact source (e.g. SessionStart source=startup), which
# must not trigger a re-inject. This keeps the event choice pure manifest config.
[ -z "$SOURCE" ] || [ "$SOURCE" = "compact" ] || exit 0
[ -n "$PROJECT" ] || exit 0

SENT=$(recompact_sentinel "$SESSION_ID")
[ -n "$SENT" ] || exit 0
mkdir -p "$STATE_DIR"
: > "$SENT"
# Prune sentinels from sessions that compacted but never resumed.
find "$STATE_DIR" -name '*.recompact' -mtime +2 -delete 2>/dev/null || true
exit 0
