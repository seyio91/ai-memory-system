#!/usr/bin/env bash
# Shared helpers for memory hooks. Sourced by session_start_memory.sh (SessionStart)
# and inject_memory.sh (UserPromptSubmit). Not executed directly.
set -euo pipefail

# Resolve MEMORY_DIR. This file is symlinked into ~/.claude/hooks, so the repo
# root is two levels up from its *real* location — resolving the symlink lets the
# hook find the tree wherever it was installed, with no ~/.claude-memory needed.
# config.local.sh (stamped by install.sh with the install dir) is then the
# authoritative override, matching scripts/_lib.sh. A pre-set MEMORY_DIR env is
# honored as the bootstrap default.
_mc_resolve() {
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
if [ -z "${MEMORY_DIR:-}" ]; then
    _mc_self="$(_mc_resolve "${BASH_SOURCE[0]}")"
    MEMORY_DIR="$(cd "$(dirname "$_mc_self")/../.." && pwd)"
fi
[ -f "$MEMORY_DIR/config.local.sh" ] && . "$MEMORY_DIR/config.local.sh"

# Per-session signal files (e.g. post-compaction reload). Not git-managed.
STATE_DIR="${MEMORY_STATE_DIR:-$MEMORY_DIR/.sessions}"

# Path of the post-compaction reload sentinel for a session. Empty if no id.
# $1 = session id
recompact_sentinel() {
    [ -n "${1:-}" ] || return 0
    printf '%s/%s.recompact' "$STATE_DIR" "$1"
}

# Escape an arbitrary string as a JSON string (including surrounding quotes).
# Falls back jq -> python3 -> hand-rolled sed/awk so the hook works without jq.
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

# Read a JSON field from a string via python3 (graceful empty fallback).
json_field() {
    # $1 = json blob, $2 = key
    printf '%s' "$1" | python3 -c "import json,sys; print(json.loads(sys.stdin.read()).get('$2',''))" 2>/dev/null || echo ""
}

# Resolve the active project by walking up from cwd to the nearest
# .claude/memory-project marker. No marker -> empty (generic Claude, no memory
# system) until the repo is onboarded via /pin. There is intentionally no global
# fallback: the project is whichever repo you are actually in.
# $1 = cwd
detect_project() {
    local cwd="$1" dir proj=""
    dir="$cwd"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -f "$dir/.claude/memory-project" ]; then
            proj=$(tr -d '[:space:]' < "$dir/.claude/memory-project")
            break
        fi
        dir=$(dirname "$dir")
    done
    printf '%s' "$proj"
}

# Assemble the full memory payload (identity + project + index + working) into stdout.
# No project -> empty output: outside an onboarded repo the memory system stays
# dormant and Claude runs generic.
# $1 = project name (may be empty).
assemble_full_memory() {
    local project="$1" out=""

    [ -z "$project" ] && return 0

    if [ -f "$MEMORY_DIR/identity.md" ]; then
        out+="<memory:identity>"$'\n'
        out+=$(cat "$MEMORY_DIR/identity.md")
        out+=$'\n'"</memory:identity>"$'\n'
    fi

    if [ -n "$project" ] && [ -f "$MEMORY_DIR/projects/$project/memory.md" ]; then
        out+="<memory:project name=\"$project\">"$'\n'
        out+=$(cat "$MEMORY_DIR/projects/$project/memory.md")
        out+=$'\n'"</memory:project>"$'\n'
    fi

    if [ -f "$MEMORY_DIR/index.md" ]; then
        out+="<memory:index>"$'\n'
        out+=$(cat "$MEMORY_DIR/index.md")
        out+=$'\n'"</memory:index>"$'\n'
    fi

    if [ -n "$project" ]; then
        local working="$MEMORY_DIR/projects/$project/working.md"
        if [ -f "$working" ] && [ -s "$working" ]; then
            out+="<memory:working>"$'\n'
            out+=$(cat "$working")
            out+=$'\n'"</memory:working>"$'\n'
        fi
    fi

    printf '%s' "$out"
}

# Assemble the lightweight per-prompt breadcrumb: the active-project pointer plus
# absolute paths to the memory files and a directive to re-read them if they have
# fallen out of context (compaction recovery). Empty if no project.
# $1 = project name, $2 = cwd.
assemble_breadcrumb() {
    local project="$1" cwd="$2" out=""
    [ -z "$project" ] && return 0

    out+="<memory:active project=\"$project\" cwd=\"$cwd\">"$'\n'
    [ -f "$MEMORY_DIR/identity.md" ] && out+="identity: $MEMORY_DIR/identity.md"$'\n'
    [ -f "$MEMORY_DIR/projects/$project/memory.md" ] && out+="project: $MEMORY_DIR/projects/$project/memory.md"$'\n'
    [ -f "$MEMORY_DIR/index.md" ] && out+="index: $MEMORY_DIR/index.md"$'\n'
    local working="$MEMORY_DIR/projects/$project/working.md"
    [ -f "$working" ] && [ -s "$working" ] && out+="working: $working"$'\n'
    out+="If these are not already in context (e.g. after compaction), read them before proceeding."

    printf '%s' "$out"
}
