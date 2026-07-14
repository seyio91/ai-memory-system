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

deny() {
    printf '%s\n' "$1" >&2
    exit 2
}

[ -n "$ROLE" ] || exit 0

if ! json_parser_available; then
    deny "no jq/python3, cannot inspect tool call"
fi

CMDLINE="$(printf '%s' "$INPUT" | json_get_path toolCall args CommandLine)"

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

exit 0
