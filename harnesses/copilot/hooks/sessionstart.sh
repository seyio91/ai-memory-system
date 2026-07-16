#!/usr/bin/env bash
# sessionstart.sh — Copilot sessionStart hook: inject full project memory using
# Copilot's flat {"additionalContext": "..."} envelope.
set -euo pipefail

_cs_resolve() {
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

_cs_self="$(_cs_resolve "${BASH_SOURCE[0]}")"
_CS_REPO="$(cd "$(dirname "$_cs_self")/../../.." && pwd)"
. "$_CS_REPO/scripts/hooks/lib.sh"

[ -n "${AI_MEMORY_SKIP_INJECT:-}" ] && { printf '{}\n'; exit 0; }

INPUT="$(cat)"
CWD="$(json_field "$INPUT" "cwd")"
PROJECT="$(detect_project "$CWD")"
export AI_MEMORY_CWD="$CWD"
export AI_MEMORY_HOOK_FORMAT="${AI_MEMORY_HOOK_FORMAT:-md}"

PAYLOAD="$(render_full "$PROJECT")"

# Copilot accepts an empty object for "no extra context"; use that instead of an
# empty string so non-memory sessions stay fully dormant.
[ -n "$PAYLOAD" ] || { printf '{}\n'; exit 0; }

printf '{"additionalContext":%s}\n' "$(json_escape "$PAYLOAD")"
