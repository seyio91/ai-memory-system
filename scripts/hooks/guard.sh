#!/usr/bin/env bash
# Shared infra guard for executor hook contexts: executor roles (AI_MEMORY_ROLE)
# get the shared destructive/additive infra deny-list. AI_MEMORY_GUARD_SCOPE
# widens it: empty/`executor` (default) leaves interactive sessions untouched;
# `all` also guards role-less calls (subagents denied, main session asked); any
# other value is treated as `all` with a warning.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO/scripts/jsonutil.sh"
. "$REPO/scripts/deny-match.sh"

INPUT="$(cat)"
ROLE="${AI_MEMORY_ROLE:-}"
SCOPE="${AI_MEMORY_GUARD_SCOPE:-}"
SCOPE="${SCOPE#"${SCOPE%%[![:space:]]*}"}"
SCOPE="${SCOPE%"${SCOPE##*[![:space:]]}"}"
SCOPE_NOTE=""
case "$SCOPE" in
    ""|[eE][xX][eE][cC][uU][tT][oO][rR]) SCOPE=executor ;;
    [aA][lL][lL]) SCOPE=all ;;
    *) SCOPE_UNKNOWN="$SCOPE"; SCOPE=all
       SCOPE_NOTE=" (unknown AI_MEMORY_GUARD_SCOPE '$SCOPE_UNKNOWN', treating as all)" ;;
esac

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

# Main-session Claude (AI_MEMORY_GUARD_SCOPE=all, no role, no agent_id) is asked
# instead of denied, and fails open with a visible warning.
ask() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$(json_escape "$1$SCOPE_NOTE")"
    exit 0
}

guard_fail() {
    if [ "$CONTEXT" = main ]; then
        printf '{"systemMessage":%s}\n' "$(json_escape "ai-memory guard: ${2:-$1} — deny-list NOT enforced$SCOPE_NOTE")"
        exit 0
    fi
    deny "$1$SCOPE_NOTE"
}

[ -n "$ROLE" ] || [ "$SCOPE" = all ] || exit 0

# agent_id is present only in subagent tool calls. The raw grep runs first so a
# subagent is still detected (and denied) when no JSON parser is available.
CONTEXT=executor
if [ -z "$ROLE" ]; then
    CONTEXT=main
    if printf '%s' "$INPUT" | grep -q '"agent_id"' \
        || [ -n "$(printf '%s' "$INPUT" | json_get agent_id)" ]; then
        CONTEXT=subagent
    fi
fi

if ! json_parser_available; then
    guard_fail "no jq/python3, cannot inspect tool call"
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
    guard_fail "executor deny-list missing at scripts/deny-list.txt — refusing to run unguarded" \
        "deny-list missing at scripts/deny-list.txt"
fi
if ! grep -qE '^[[:space:]]*[^#[:space:]]+[[:space:]]+[^[:space:]]' "$REPO/scripts/deny-list.txt" 2>/dev/null; then
    guard_fail "executor deny-list at scripts/deny-list.txt has no usable rules — refusing to run unguarded" \
        "deny-list at scripts/deny-list.txt has no usable rules"
fi

if [ -n "$CMDLINE" ]; then
    DENY_SPEC_ARGV=( "$REPO/scripts/deny-list.txt" )
    [ -f "$REPO/scripts/deny-list.local.txt" ] && DENY_SPEC_ARGV+=( "$REPO/scripts/deny-list.local.txt" )
    if DENY_REASON="$(deny_match "$CMDLINE" "${DENY_SPEC_ARGV[@]}")"; then
        [ "$CONTEXT" = main ] && ask "$DENY_REASON"
        deny "$DENY_REASON$SCOPE_NOTE"
    fi
fi

# Copilot allows hook stdout to be empty on allow (Phase 0 postToolUse/preToolUse
# probes); only deny needs its JSON permissionDecision envelope.
if [ "$CONTEXT" = main ] && [ -n "$SCOPE_NOTE" ]; then
    printf '{"systemMessage":%s}\n' "$(json_escape "ai-memory guard: unknown AI_MEMORY_GUARD_SCOPE '$SCOPE_UNKNOWN', treating as all")"
fi
exit 0
