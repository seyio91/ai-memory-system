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
: "${MEMORY_DIR:=$_HOOK_REPO}"
export MEMORY_DIR

. "$_HOOK_REPO/scripts/_lib.sh"
. "$_HOOK_REPO/scripts/content-core.sh"
. "$_HOOK_REPO/scripts/formatters/xml.sh"
. "$_HOOK_REPO/scripts/formatters/md.sh"

STATE_DIR="${MEMORY_STATE_DIR:-$MEMORY_DIR/.sessions}"

recompact_sentinel() {
    [ -n "${1:-}" ] || return 0
    printf '%s/%s.recompact' "$STATE_DIR" "$1"
}

# session_pin_file <session_id> — path of the session's project pin, or empty when
# the harness supplied no session_id (then there is no pin and resolution falls
# back to the cwd walk, exactly as before this existed).
#
# The pin records the project resolved at SessionStart so a session that cd's
# elsewhere keeps writing memory to the project it is ABOUT. Deliberately a file
# keyed by session, not an environment variable: env inherits into child
# processes, so an executor launched in a sibling repo would resolve the
# ORCHESTRATOR's project instead of the sibling's — strictly worse than the bug
# this fixes, and the reason executors and subagents keep cwd resolution.
session_pin_file() {
    [ -n "${1:-}" ] || return 0
    printf '%s/%s.project' "$STATE_DIR" "$1"
}

# Pins outlive their session and must be swept. Retention is deliberately longer
# than the .recompact sweep (-mtime +2): a sentinel is consumed on the very next
# prompt, whereas a pin must survive a multi-day session. Pruning a live
# session's pin degrades to cwd resolution — it never corrupts.
SESSION_PIN_RETAIN_DAYS="${AI_MEMORY_PIN_RETAIN_DAYS:-7}"

prune_session_pins() {
    [ -d "$STATE_DIR" ] || return 0
    find "$STATE_DIR" -name '*.project' -mtime "+$SESSION_PIN_RETAIN_DAYS" -delete 2>/dev/null || true
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

json_escape_nonempty_stream() {
    python3 -c 'import json,sys
data = sys.stdin.buffer.read()
if not data:
    sys.exit(3)
print(json.dumps(data.decode("utf-8")))'
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
        xml) content_sections "$project" identity orchestrator project index working | xml_render_full ;;
        md)  content_sections "$project" identity orchestrator project index domain working | md_render ;;
        *)   printf 'unsupported AI_MEMORY_HOOK_FORMAT: %s\n' "$format" >&2; return 2 ;;
    esac
}

# _initiative_targets_project <initiative-file> <project> — the CHEAP half of
# the match test below: true when <initiative-file> is kind:initiative,
# status:active, carries a slug, and its "## Targets" section has a
# "### <project>/..." entry. Pure frontmatter reads + one awk scan, no
# initiative-status.sh involved — extracted so check-memory-size.sh's size
# prefilter (_cms_project_targeted) can reuse the EXACT same match logic to
# prove an alert is empty without paying initiative-status.sh's ~0.9s cost.
_initiative_targets_project() {
    local initiative="$1" project="$2" kind status slug
    kind="$(extract_fm_field "$initiative" kind 2>/dev/null || true)"
    status="$(extract_fm_field "$initiative" status 2>/dev/null || true)"
    slug="$(extract_fm_field "$initiative" slug 2>/dev/null || true)"
    [ "$kind" = "initiative" ] && [ "$status" = "active" ] && [ -n "$slug" ] || return 1
    awk -v prefix="$project/" '
        /^## Targets[[:space:]]*$/ { in_targets = 1; next }
        in_targets && /^## / { exit }
        in_targets && /^### / && index(substr($0, 5), prefix) == 1 { found = 1; exit }
        END { exit(found ? 0 : 1) }
    ' "$initiative" >/dev/null 2>&1
}

# _initiative_has_target <project> — true when ANY active initiative under
# $MEMORY_DIR/initiatives targets <project>, using ONLY the cheap predicate
# above (no initiative-status.sh subprocess). check-memory-size.sh's prefilter
# calls this first: when it says "no", the alert is provably empty and the
# byte/line bound can proceed unmodified; only a "yes" earns the cost of
# fetching the real alert text.
_initiative_has_target() {
    local project="$1" dir initiative
    dir="$MEMORY_DIR/initiatives"
    [ -d "$dir" ] || return 1
    for initiative in "$dir"/*.md; do
        [ -f "$initiative" ] || continue
        _initiative_targets_project "$initiative" "$project" && return 0
    done
    return 1
}

# _compute_initiative_alert_lines <project> — the expensive, format-neutral
# half of render_initiative_alert: scans initiatives/*.md for a Target under
# this project (via _initiative_targets_project above) and shells out to
# initiative-status.sh (the ~0.9s-per-call cost) for each match. Sets the
# global $_IA_LINES rather than printing to stdout, deliberately: a caller
# capturing this via $(...) would have any trailing newline silently
# stripped, which would desync the byte-identical output
# render_initiative_alert composes from it.
_IA_LINES=""
_compute_initiative_alert_lines() {
    local project="$1" dir initiative slug output stale
    _IA_LINES=""
    dir="$MEMORY_DIR/initiatives"
    [ -d "$dir" ] || return 0

    for initiative in "$dir"/*.md; do
        [ -f "$initiative" ] || continue
        _initiative_targets_project "$initiative" "$project" || continue
        slug="$(extract_fm_field "$initiative" slug 2>/dev/null || true)"
        if output="$(
            (
                ulimit -t 5 2>/dev/null || true
                bash "$MEMORY_DIR/scripts/initiative-status.sh" "$slug" 2>/dev/null
            )
        )"; then
            stale="$(printf '%s\n' "$output" | awk '
                /^## Stale targets[[:space:]]*$/ { in_stale = 1; next }
                in_stale && /^## / { exit }
                in_stale && /^WARN: / { print }
            ')"
            if [ -n "$stale" ]; then
                _IA_LINES="$_IA_LINES$stale"$'\n'
            fi
        fi
    done
}

# render_initiative_alert <project> — per-format wrapper around
# _compute_initiative_alert_lines. A caller that has already paid the scan
# cost once (check-memory-size.sh --payload, across several harness/working
# combinations for the same project) can skip paying it again by exporting
# AI_MEMORY_PRECOMPUTED_ALERT_SET=1 and AI_MEMORY_PRECOMPUTED_ALERT=<lines>;
# absent that, behavior is exactly what it was before this seam existed
# (session_start_memory.sh never sets it).
render_initiative_alert() {
    local project="$1" format="${AI_MEMORY_HOOK_FORMAT:-xml}" lines
    [ -n "$project" ] || return 0
    if [ -n "${AI_MEMORY_PRECOMPUTED_ALERT_SET:-}" ]; then
        lines="${AI_MEMORY_PRECOMPUTED_ALERT:-}"
    else
        _compute_initiative_alert_lines "$project"
        lines="$_IA_LINES"
    fi

    [ -n "$lines" ] || return 0
    case "$format" in
        xml) printf '<memory:initiative-alert>\n%s</memory:initiative-alert>' "$lines" ;;
        md)  printf '# === INITIATIVE ALERT ===\n\n%s' "$lines" ;;
    esac
}

hook_chunk_spec() {
    local spec="${AI_MEMORY_HOOK_CHUNK:-}"
    [ -n "$spec" ] || spec="1/1"
    printf '%s' "$spec"
}

# A malformed AI_MEMORY_HOOK_CHUNK must fail CLOSED everywhere: emit_hook_chunk
# already rejects it (rc=2, no output), so is_first/is_last must not default it
# to 1/1 — that would consume the recompact sentinel / emit breadcrumbs from an
# invocation that then emits no payload. Unset/empty stays 1/1 (Claude's shape).
hook_chunk_valid() {
    local spec idx total
    spec="$(hook_chunk_spec)"
    case "$spec" in
        */*) idx="${spec%%/*}"; total="${spec#*/}" ;;
        *)   return 1 ;;
    esac
    case "$idx"   in ''|*[!0-9]*) return 1 ;; esac
    case "$total" in ''|*[!0-9]*) return 1 ;; esac
    [ "$idx" -ge 1 ] && [ "$total" -ge 1 ] && [ "$idx" -le "$total" ]
}

hook_chunk_index() {
    hook_chunk_valid || return 1
    local spec
    spec="$(hook_chunk_spec)"
    printf '%s' "${spec%%/*}"
}

hook_chunk_total() {
    hook_chunk_valid || return 1
    local spec
    spec="$(hook_chunk_spec)"
    printf '%s' "${spec#*/}"
}

hook_chunk_is_first() {
    hook_chunk_valid && [ "$(hook_chunk_index)" = 1 ]
}

hook_chunk_is_last() {
    hook_chunk_valid && [ "$(hook_chunk_index)" = "$(hook_chunk_total)" ]
}

emit_hook_chunk() {
    local payload="$1" spec idx total
    spec="$(hook_chunk_spec)"
    if [ "$spec" = "1/1" ]; then
        printf '%s' "$payload"
        return 0
    fi
    case "$spec" in
        */*) ;;
        *) printf 'invalid AI_MEMORY_HOOK_CHUNK: %s\n' "$spec" >&2; return 2 ;;
    esac
    idx="${spec%%/*}"
    total="${spec#*/}"
    case "$idx" in ''|*[!0-9]*) printf 'invalid AI_MEMORY_HOOK_CHUNK: %s\n' "$spec" >&2; return 2 ;; esac
    case "$total" in ''|*[!0-9]*) printf 'invalid AI_MEMORY_HOOK_CHUNK: %s\n' "$spec" >&2; return 2 ;; esac
    [ "$idx" -ge 1 ] && [ "$total" -ge 1 ] || { printf 'invalid AI_MEMORY_HOOK_CHUNK: %s\n' "$spec" >&2; return 2; }
    printf '%s' "$payload" \
        | AI_MEMORY_CHUNK_INDEX="$idx" AI_MEMORY_CHUNK_TOTAL="$total" python3 "$_HOOK_REPO/scripts/payload-slices.py"
}

# render_breadcrumb <project> [cwd] [session_id] [cwd_project]
# The trailing two are optional: absent them the breadcrumb renders exactly as it
# did before session pinning existed.
render_breadcrumb() {
    local project="$1" cwd="${2:-}" session="${3:-}" cwd_project="${4:-}" format="${AI_MEMORY_HOOK_FORMAT:-xml}"
    [ -z "$project" ] && return 0
    case "$format" in
        xml) content_sections "$project" identity orchestrator project index working | xml_render_breadcrumb "$project" "$cwd" "$session" "$cwd_project" ;;
        md)  content_sections "$project" identity orchestrator project index working | md_render_breadcrumb "$project" "$cwd" "$session" "$cwd_project" ;;
        *)   printf 'unsupported AI_MEMORY_HOOK_FORMAT: %s\n' "$format" >&2; return 2 ;;
    esac
}
