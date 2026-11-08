#!/usr/bin/env bash
# opencode executor wrapper. Invoked by executor.sh via the manifest exec_* lines:
#   opencode-mem.sh run --auto <prompt> [-m <model>] [--last-message <file>]
#   opencode-mem.sh run --agent ai-memory-explore <prompt> [-m <model>] [--last-message <file>]
#
#  * `--probe` (sole argument): exit 0 iff a binary resolves, print nothing (executor.sh exec_probe_cmd).
#  * Resolves the binary: `opencode` on PATH, else ~/.opencode/bin/opencode (exit 127 if neither).
#  * Exports OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 so skills are not listed twice.
#  * Forces `run --standalone`. Plain `opencode run` hands the job to the shared background
#    service, which keeps the plugin set it started with; the ai-memory guard plugin is the only
#    thing stopping a denied command under --auto, so it must load in a private server.
#  * --last-message <file> (anywhere in argv, stripped before opencode sees it): run with
#    `--format json`, stream stdout through, and on exit write ONLY the last assistant text
#    (last type=="text" event, .part.text) to <file>, and only when the run exited 0, every stream
#    line parses, and that text is non-empty; otherwise <file> is left empty, a reason goes to
#    stderr and the exit is non-zero. Any type=="error" message goes to stderr.
#  * Propagates opencode's exit code; a JSON-mode error event forces a non-zero exit.
#  * Exports OPENCODE_CONFIG_CONTENT with permission.execute=deny (Code Mode), merged into any caller
#    value; a caller value that is not exactly one JSON object is refused.
#  * Refuses to launch a `run` unless the ai-memory guard plugin will load:
#    ${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}/plugins/ai-memory.ts (opencode's global
#    config dir) must resolve to this repo's harnesses/opencode/plugin/ai-memory.ts. Project-local
#    plugins are not accepted: a session move leaves their directory, and the guard with it.
#    There is no override: the check is unconditional.
set -uo pipefail

BIN=""
if command -v opencode >/dev/null 2>&1; then
    BIN="$(command -v opencode)"
elif [ -x "$HOME/.opencode/bin/opencode" ]; then
    BIN="$HOME/.opencode/bin/opencode"
else
    [ "${1:-}" = --probe ] && exit 1
    echo "opencode-mem: opencode not found (PATH or \$HOME/.opencode/bin/opencode)" >&2
    exit 127
fi
[ "${1:-}" = --probe ] && exit 0

export OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1

# Disable the Code Mode `execute` tool: it runs JS that calls other tools in-process, which may
# bypass the plugin's execute.before guard. Merge into any caller-provided config, never clobber it.
if [ -n "${OPENCODE_CONFIG_CONTENT:-}" ]; then
    if ! command -v jq >/dev/null 2>&1; then
        echo "opencode-mem: jq is required to merge OPENCODE_CONFIG_CONTENT" >&2
        exit 1
    fi
    CFG="$(printf '%s' "$OPENCODE_CONFIG_CONTENT" | jq -ces 'if length == 1 and (.[0] | type) == "object" then .[0] | .permission = ((.permission // {}) + {execute: "deny"}) else error("not exactly one JSON object") end')" \
        || { echo "opencode-mem: OPENCODE_CONFIG_CONTENT is not exactly one JSON object, refusing to run without the execute deny" >&2; exit 1; }
else
    CFG='{"permission":{"execute":"deny"}}'
fi
export OPENCODE_CONFIG_CONTENT="$CFG"

LASTMSG=""
HAVE_FORMAT=0
ARGS=()
while [ "$#" -gt 0 ]; do
    case "$1" in
        --last-message)
            [ "$#" -ge 2 ] || { echo "opencode-mem: --last-message needs a file" >&2; exit 2; }
            LASTMSG="$2"; shift 2; continue ;;
        --last-message=*) LASTMSG="${1#*=}"; shift; continue ;;
        --format|--format=*) HAVE_FORMAT=1 ;;
    esac
    ARGS+=("$1"); shift
done

# --standalone is a global flag; place it right after the `run` subcommand.
if [ "${ARGS[0]:-}" = run ]; then
    ARGS=(run --standalone ${ARGS[@]+"${ARGS[@]:1}"})
fi

# Guard registration: under --auto the ai-memory plugin is the only enforcement layer, so a `run`
# must not start unless it will load. Verified = a candidate path is readable and resolves to this
# repo's plugin file.
real() { # real <path>: physical path with symlinks resolved, empty on failure
    if command -v realpath >/dev/null 2>&1; then realpath "$1" 2>/dev/null
    else perl -MCwd=realpath -e 'print realpath(shift)' "$1" 2>/dev/null; fi
}
if [ "${ARGS[0]:-}" = run ]; then
    SELF="$(real "${BASH_SOURCE[0]}")"
    WANT="$(real "$(dirname "$SELF")/../plugin/ai-memory.ts")"
    GCFG="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}/plugins/ai-memory.ts"
    ok=0
    if [ -n "$WANT" ] && [ -r "$GCFG" ] && [ "$(real "$GCFG")" = "$WANT" ]; then ok=1; fi
    if [ "$ok" -ne 1 ]; then
        {
            echo "opencode-mem: refusing to run: the ai-memory guard plugin is not installed where opencode will load it."
            echo "  expected a GLOBAL symlink (project-local is not accepted) to ${WANT:-<harnesses/opencode/plugin/ai-memory.ts>} at:"
            echo "    $GCFG"
            echo "  install it (install.sh)."
        } >&2
        exit 1
    fi
fi

if [ -z "$LASTMSG" ]; then
    exec "$BIN" ${ARGS[@]+"${ARGS[@]}"}
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "opencode-mem: jq is required for --last-message" >&2
    exit 1
fi
[ "$HAVE_FORMAT" -eq 1 ] || ARGS+=(--format json)

STREAM="$(mktemp "${TMPDIR:-/tmp}/opencode-mem.XXXXXX")" || { echo "opencode-mem: mktemp failed" >&2; exit 1; }
trap 'rm -f "$STREAM"' EXIT
"$BIN" ${ARGS[@]+"${ARGS[@]}"} | tee "$STREAM"
ps=("${PIPESTATUS[@]}")
rc="${ps[0]}"
# A failed capture (tee) means $STREAM may be incomplete yet still end on a valid JSON boundary.
capfail=0
[ "${ps[1]:-1}" -eq 0 ] || capfail=1

# Clean output is all-or-nothing. The file is truncated first (never stale text), then written
# ONLY if the run exited 0, every stream line parses (a skipped malformed line could promote an
# earlier text), there is no error event, and the last text event has non-empty text.
: > "$LASTMSG" 2>/dev/null || { echo "opencode-mem: cannot write $LASTMSG" >&2; exit 1; }

errs="$(jq -Rrn '[inputs | select(length > 0) | fromjson? | select(type == "object" and .type == "error")] | .[] | (first((if (.error | type) == "object" then (.error.message, .error.type) elif (.error | type) == "string" then .error else empty end) | select(type == "string" and length > 0))) // "opencode reported an error event with no message"' "$STREAM" 2>/dev/null || true)"
if [ -n "$errs" ]; then
    printf 'opencode-mem: %s\n' "$errs" >&2
    [ "$rc" -ne 0 ] || rc=1
fi

fail=""
if [ "$rc" -ne 0 ]; then
    fail="opencode exited $rc"
elif [ "$capfail" -ne 0 ]; then
    fail="capture of the event stream failed (tee exit ${ps[1]:-?})"
elif ! jq -Rjn '[inputs | select(length > 0) | fromjson] as $ev
    | if ($ev | length) > 0 and ($ev | last | type) != "object" then error("last line is not a JSON object") else . end
    | [$ev[] | select(type == "object" and .type == "text")] | last
    | if . == null then ""
      elif (.part.text | type) == "string" then .part.text
      else error("part.text is not a string") end' "$STREAM" > "$LASTMSG" 2>/dev/null; then
    fail="malformed JSON line, non-object last line or non-string part.text in the event stream"
elif [ ! -s "$LASTMSG" ]; then
    fail="no final assistant text in the event stream"
fi
if [ -n "$fail" ]; then
    : > "$LASTMSG" 2>/dev/null
    echo "opencode-mem: no last-message written: $fail" >&2
    [ "$rc" -ne 0 ] || rc=1
    exit "$rc"
fi
exit "$rc"
