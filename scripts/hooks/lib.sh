#!/usr/bin/env bash
# Shared hook behavior for harnesses that use the Claude/Codex hook contract.
# Rendering stays format-parameterized; harness registration and envelopes stay
# outside this file.
set -euo pipefail

_hook_resolve() {
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

_hook_self="$(_hook_resolve "${BASH_SOURCE[0]}")"
_HOOK_REPO="$(cd "$(dirname "$_hook_self")/../.." && pwd)"

. "$_HOOK_REPO/scripts/_lib.sh"
. "$_HOOK_REPO/scripts/content-core.sh"
. "$_HOOK_REPO/scripts/formatters/xml.sh"
. "$_HOOK_REPO/scripts/formatters/md.sh"

STATE_DIR="${MEMORY_STATE_DIR:-$MEMORY_DIR/.sessions}"

recompact_sentinel() {
    [ -n "${1:-}" ] || return 0
    printf '%s/%s.recompact' "$STATE_DIR" "$1"
}

json_escape() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$1" | jq -Rs .
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$1" | python3 -c "import json,sys; print(json.dumps(sys.stdin.read()))"
    else
        printf '%s' "$1" \
            | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' \
            | awk 'BEGIN{printf "\""} {if(NR>1) printf "\\n"; printf "%s",$0} END{printf "\""}'
    fi
}

json_field() {
    printf '%s' "$1" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('$2',''))" 2>/dev/null || echo ""
}

detect_project() {
    local cwd="$1" dir proj=""
    dir="$cwd"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -f "$dir/.agents/memory-project" ]; then
            proj=$(tr -d '[:space:]' < "$dir/.agents/memory-project")
            break
        fi
        if [ -f "$dir/.claude/memory-project" ]; then
            proj=$(tr -d '[:space:]' < "$dir/.claude/memory-project")
            break
        fi
        dir=$(dirname "$dir")
    done
    printf '%s' "$proj"
}

render_full() {
    local project="$1" format="${AI_MEMORY_HOOK_FORMAT:-xml}"
    [ -z "$project" ] && return 0
    case "$format" in
        xml) content_sections "$project" identity project index working | xml_render_full ;;
        md)  content_sections "$project" identity project index domain working | md_render ;;
        *)   printf 'unsupported AI_MEMORY_HOOK_FORMAT: %s\n' "$format" >&2; return 2 ;;
    esac
}

render_breadcrumb() {
    local project="$1" cwd="${2:-}" format="${AI_MEMORY_HOOK_FORMAT:-xml}"
    [ -z "$project" ] && return 0
    case "$format" in
        xml) content_sections "$project" identity project index working | xml_render_breadcrumb "$project" "$cwd" ;;
        md)  content_sections "$project" identity project index working | md_render_breadcrumb "$project" "$cwd" ;;
        *)   printf 'unsupported AI_MEMORY_HOOK_FORMAT: %s\n' "$format" >&2; return 2 ;;
    esac
}
