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
# Always resolve the hook's REAL repo root from its symlinked location. This is
# the source of the shared engine (scripts/content-core.sh + formatters), which
# must load from the real install even when MEMORY_DIR is overridden to a
# content-only tree (as the test suite does). MEMORY_DIR — the content root —
# defaults to the same repo but is honored if pre-set. The hook lives at
# harnesses/claude/hooks/, so the repo root is THREE levels up from its real path.
_mc_self="$(_mc_resolve "${BASH_SOURCE[0]}")"
_MC_REPO="$(cd "$(dirname "$_mc_self")/../../.." && pwd)"
if [ -z "${MEMORY_DIR:-}" ]; then
    MEMORY_DIR="$_MC_REPO"
fi
[ -f "$MEMORY_DIR/config.local.sh" ] && . "$MEMORY_DIR/config.local.sh"

# Shared content selection + XML serialization (single source of what/order).
. "$_MC_REPO/scripts/content-core.sh"
. "$_MC_REPO/scripts/formatters/xml.sh"

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

# Resolve the active project by walking up from cwd to the nearest marker: the
# harness-neutral .agents/memory-project, falling back to the legacy
# .claude/memory-project (pre-Phase-6 pins) at the same level. No marker -> empty
# (generic Claude, no memory system) until the repo is onboarded via /pin. There
# is intentionally no global fallback: the project is whichever repo you are in.
# $1 = cwd
detect_project() {
    local cwd="$1" dir proj=""
    dir="$cwd"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -f "$dir/.agents/memory-project" ]; then
            proj=$(tr -d '[:space:]' < "$dir/.agents/memory-project")
            break
        fi
        if [ -f "$dir/.claude/memory-project" ]; then   # legacy fallback
            proj=$(tr -d '[:space:]' < "$dir/.claude/memory-project")
            break
        fi
        dir=$(dirname "$dir")
    done
    printf '%s' "$proj"
}

# skill_dir_for <name> — print the invoked skill's dir across ALL skill roots
# (generic skills/, local skills-local/, remote .skill-cache/) and return 0, else
# return 1. Routes through _lib.sh:resolve_skill_dir (the centralized enumerator) so
# the boundary hooks agree with the rest of the skills toolchain — a skill is no
# longer only in skills/. _lib is sourced lazily (only the boundary hooks call this,
# so injection hooks stay lean); falls back to skills/<name> if _lib is unavailable.
skill_dir_for() {
    local name="$1" d
    if ! command -v resolve_skill_dir >/dev/null 2>&1 && [ -f "$MEMORY_DIR/scripts/_lib.sh" ]; then
        . "$MEMORY_DIR/scripts/_lib.sh"
    fi
    if command -v resolve_skill_dir >/dev/null 2>&1; then
        d="$(resolve_skill_dir "$name" 2>/dev/null)"
        [ -n "$d" ] && { printf '%s\n' "$d"; return 0; }
    fi
    [ -d "$MEMORY_DIR/skills/$name" ] && { printf '%s\n' "$MEMORY_DIR/skills/$name"; return 0; }
    return 1
}

# Assemble the full memory payload (identity + project + index + working) into stdout.
# No project -> empty output: outside an onboarded repo the memory system stays
# dormant and Claude runs generic. Selection comes from content-core; the xml
# formatter serializes it.
# $1 = project name (may be empty).
assemble_full_memory() {
    local project="$1"
    [ -z "$project" ] && return 0
    content_sections "$project" identity project index working | xml_render_full
}

# Assemble the lightweight per-prompt breadcrumb: the active-project pointer plus
# absolute paths to the memory files and a directive to re-read them if they have
# fallen out of context (compaction recovery). Empty if no project.
# $1 = project name, $2 = cwd.
assemble_breadcrumb() {
    local project="$1" cwd="$2"
    [ -z "$project" ] && return 0
    content_sections "$project" identity project index working | xml_render_breadcrumb "$project" "$cwd"
}
