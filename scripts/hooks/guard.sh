#!/usr/bin/env bash
# Shared infra guard for executor hook contexts. Interactive sessions are left
# untouched; executor roles get the shared destructive/additive infra deny-list.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO/scripts/jsonutil.sh"
. "$REPO/scripts/deny-match.sh"

INPUT="$(cat)"
ROLE="${AI_MEMORY_ROLE:-}"

json_get_encoded_path() {
    local outer="$1" expr k
    shift
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'import json,sys
try:
    d = json.load(sys.stdin)
    v = json.loads(d.get(sys.argv[1], ""))
    for k in sys.argv[2:]:
        v = v.get(k) if isinstance(v, dict) else None
        if v is None: break
    print("" if v is None else v)
except Exception:
    print("")' "$outer" "$@" 2>/dev/null
    elif command -v jq >/dev/null 2>&1; then
        expr='(.[$outer] | fromjson?'
        for k in "$@"; do expr="${expr} | .[\"$k\"]"; done
        expr="${expr}) // empty"
        jq -r --arg outer "$outer" "$expr" 2>/dev/null
    else
        echo ""
    fi
}

deny() {
    if [ "${AI_MEMORY_GUARD_OUTPUT:-}" = copilot-json ]; then
        printf '{"permissionDecision":"deny","permissionDecisionReason":%s}\n' "$(json_escape "$1")"
        exit 0
    else
        printf '%s\n' "$1" >&2
        exit 2
    fi
}

[ -n "$ROLE" ] || exit 0

if ! json_parser_available; then
    deny "no jq/python3, cannot inspect tool call"
fi

# The shell command lives at different JSON paths per harness's PreToolUse stdin:
# Codex/Claude family use tool_input.command (verified against real codex 0.144.1
# stdin); Antigravity uses toolCall.args.CommandLine; Copilot uses a JSON-encoded
# toolArgs string, verified by scripts/tests/fixtures/copilot/pre_tool_use_bash.json.
# Read primary consumers first, then fall back to each real captured shape so a
# wrong path can never silently read empty and fail OPEN.
CMDLINE="$(printf '%s' "$INPUT" | json_get_path tool_input command)"
[ -n "$CMDLINE" ] || CMDLINE="$(printf '%s' "$INPUT" | json_get_path toolCall args CommandLine)"
[ -n "$CMDLINE" ] || CMDLINE="$(printf '%s' "$INPUT" | json_get_encoded_path toolArgs command)"

if [ ! -f "$REPO/scripts/deny-list.txt" ]; then
    deny "executor deny-list missing at scripts/deny-list.txt — refusing to run unguarded"
fi
if ! grep -qE '^[[:space:]]*[^#[:space:]]+[[:space:]]+[^[:space:]]' "$REPO/scripts/deny-list.txt" 2>/dev/null; then
    deny "executor deny-list at scripts/deny-list.txt has no usable rules — refusing to run unguarded"
fi

if [ -n "$CMDLINE" ]; then
    DENY_SPEC_ARGV=( "$REPO/scripts/deny-list.txt" )
    [ -f "$REPO/scripts/deny-list.local.txt" ] && DENY_SPEC_ARGV+=( "$REPO/scripts/deny-list.local.txt" )
    if DENY_REASON="$(deny_match "$CMDLINE" "${DENY_SPEC_ARGV[@]}")"; then
        deny "$DENY_REASON"
    fi
fi

# Copilot allows hook stdout to be empty on allow (Phase 0 postToolUse/preToolUse
# probes); only deny needs its JSON permissionDecision envelope.
exit 0
