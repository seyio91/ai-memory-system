#!/usr/bin/env bash
# context.sh — opencode `context` hook script. The plugin (plugin/ai-memory.ts)
# spawns this once per MODEL CALL and pushes our stdout onto event.system.
#
# opencode rebuilds event.system fresh on every model call and pushes do NOT
# persist (verified: scripts/tests/fixtures/opencode/context-after-tool.json, the
# 2nd call of a session, holds only opencode's stock entries). So there is no
# session state: EVERY call emits the full `<memory:*>` xml payload, which also
# makes compaction recovery automatic.
#
# stdin  : {"directory":..., "sessionID":...} (the event, with its messages, is not sent)
# stdout : the full payload (ends with the <memory:working> section), or nothing
#          when there is no active project for `directory` or the build fails.
# Never exits non-zero: a failing injector must not break the session; failures
# are logged on stderr and degrade to no injection.
set -uo pipefail

log() { printf 'ai-memory opencode context.sh: %s\n' "$*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=/dev/null
. "$REPO/scripts/hooks/lib.sh" 2>/dev/null || { log "cannot load scripts/hooks/lib.sh"; exit 0; }
set +e +u

[ -n "${AI_MEMORY_SKIP_INJECT:-}" ] && exit 0

INPUT="$(cat)"
DIR="$(json_field "$INPUT" directory)"
[ -n "$DIR" ] || DIR="$PWD"

PROJECT="$(detect_active_project "$DIR")"
[ -n "$PROJECT" ] || exit 0
export AI_MEMORY_CWD="$DIR"

OUT="$(render_full "$PROJECT")" || OUT=""
if [ -z "$OUT" ]; then
    log "payload build failed or empty for project $PROJECT (session $(json_field "$INPUT" sessionID)); no injection"
    exit 0
fi

ALERT="$(render_initiative_alert "$PROJECT" 2>/dev/null || true)"
if [ -n "$ALERT" ]; then
    case "$OUT" in
        *'<memory:working>'*) OUT="${OUT/<memory:working>/$ALERT$'\n'<memory:working>}" ;;
        *) OUT="$OUT"$'\n'"$ALERT" ;;
    esac
fi

printf '%s' "$OUT"
exit 0
