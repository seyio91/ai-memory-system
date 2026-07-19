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
    printf '%s' "$payload" | AI_MEMORY_CHUNK_INDEX="$idx" AI_MEMORY_CHUNK_TOTAL="$total" python3 -c '
import os, sys

MAX = 9000
MARKER = b"[ai-memory: memory base truncated \xe2\x80\x94 raise session_chunks in the harness manifest]\n"
idx = int(os.environ["AI_MEMORY_CHUNK_INDEX"])
total = int(os.environ["AI_MEMORY_CHUNK_TOTAL"])
data = sys.stdin.buffer.read()
if not data:
    sys.exit(0)

slices = []
current = b""
for line in data.splitlines(keepends=True):
    if not current:
        current = line
    elif len(current) + len(line) <= MAX:
        current += line
    else:
        slices.append(current)
        current = line
if current:
    slices.append(current)

if idx > len(slices):
    sys.exit(0)

# Hook entries registered 1..N are NOT guaranteed to be delivered in registration
# order -- Claude ran them concurrently and concatenated by completion (observed
# 2026-07-18: chunks arrived 2,3,4,1,5). Slices are cut at arbitrary line
# boundaries, so an out-of-order chunk bisects a <memory:*> block. Frame every
# slice with its index so a reader can reassemble regardless of arrival order.
# This is a transport frame, deliberately not balanced against the content tags
# it may bisect. Inert on codex, which does deliver in order.
NOTE = (b" note=\"ordered fragments of one memory payload; hook delivery order is"
        b" not guaranteed -- concatenate by index\"")

def emit(body, of):
    # No separator before the footer: whether a trailing newline was original or
    # inserted would be ambiguous on strip, breaking byte-identical reassembly.
    # Only the final slice can lack one (slices are cut keeping line ends), so at
    # most one chunk closes on the same line as its last byte.
    head = b"<memory:chunk index=\"%d\" of=\"%d\"%s>\n" % (
        idx, of, NOTE if idx == 1 else b"")
    sys.stdout.buffer.write(head + body + b"</memory:chunk>\n")

overflow = len(slices) > total
if overflow and idx == total:
    out = slices[idx - 1]
    sep = b"" if out.endswith(b"\n") or not out else b"\n"
    while out and len(out) + len(sep) + len(MARKER) > MAX:
        lines = out.splitlines(keepends=True)
        if len(lines) <= 1:
            out = b""
            sep = b""
            break
        out = b"".join(lines[:-1])
        sep = b"" if out.endswith(b"\n") or not out else b"\n"
    emit(out + sep + MARKER, total)
    sys.exit(0)
if overflow and idx > total:
    sys.exit(0)

emit(slices[idx - 1], len(slices))
'
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
