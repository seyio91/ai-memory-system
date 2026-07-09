#!/usr/bin/env bash
# pretooluse.sh — Antigravity PreToolUse guard: preventive enforcement for
# executor delegations. Registered globally in ~/.gemini/config/hooks.json, so it
# fires for EVERY agy tool call, but it self-gates on AI_MEMORY_ROLE (set only by
# executor.sh when the orchestrator delegates). Interactive `agy` — where the human
# is driving and AI_MEMORY_ROLE is unset — is left unguarded.
#
# Two layers:
#   1. Deny-list (both roles): a tool whose shell CommandLine matches the shared
#      scripts/deny-list.txt (terraform/kubectl apply, gh/bkt/az merge, helm, …) is
#      hard-blocked — the O/E/V "never apply/merge to running infra" rule, enforced.
#   2. Read-only (explore/validate roles): only a known read-tool allowlist is permitted;
#      everything else (run_command, all file writes) is denied. An allowlist is
#      used deliberately — Antigravity's live tool names drift from the doc-derived
#      names (e.g. list_dir, not list_directory), so denying-by-name is unreliable;
#      allowing-by-name fails safe.
#
# stdin  : Antigravity PreToolUse JSON ({"toolCall":{"name":...,"args":{"CommandLine":...}}}).
# stdout : {"decision":"allow"} | {"decision":"deny","reason":...}
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../../.." && pwd)"
. "$REPO/scripts/jsonutil.sh"
. "$REPO/scripts/deny-match.sh"

# Read tools permitted for the read-only `explore`/`validate` roles. Names confirmed from the
# binary tool enum + live transcripts (list_dir/list_permissions are live-verified).
# run_command is deliberately absent: read-only sessions get no shell (they can
# still read via view_file/grep_search/code_search/list_dir/read_url_content/etc.).
READ_ALLOWLIST="view_file view_file_outline view_code_item view_content_chunk \
list_dir list_directory grep_search code_search find find_all_references \
read_resource read_notebook read_terminal read_url_content read_browser_page \
list_resources search_web internal_search retrieve_content retrieve_memory \
capture_browser_screenshot capture_browser_console_logs list_browser_pages \
browser_get_dom browser_get_network_request browser_list_network_requests \
list_permissions ask_question notify_user"

INPUT="$(cat)"
ROLE="${AI_MEMORY_ROLE:-}"

allow() { printf '{"decision":"allow"}\n'; exit 0; }
deny()  { printf '{"decision":"deny","reason":%s}\n' "$(json_escape "$1")"; exit 0; }

# Unguarded outside an executor delegation (interactive agy).
[ -n "$ROLE" ] || allow

if ! json_parser_available; then
    deny "no jq/python3, cannot inspect tool call"
fi

NAME="$(printf '%s' "$INPUT" | json_get_path toolCall name)"
CMDLINE="$(printf '%s' "$INPUT" | json_get_path toolCall args CommandLine)"

# Layer 1 — shared deny-list (task + explore): block destructive/additive infra.
# A missing OR EMPTY spec file must DENY, not skip: an absent (or truncated) rules
# file is indistinguishable from a disarmed guard, and this hook's own repo is a
# place an executor can write. Existence is not armed-ness — `: > deny-list.txt`
# disarms just as effectively as `rm`.
if [ ! -f "$REPO/scripts/deny-list.txt" ]; then
    deny "executor deny-list missing at scripts/deny-list.txt — refusing to run unguarded"
fi
# A rule needs a binary AND a subcommand; a file of bare words loads zero specs.
# Match what _deny_load_specs accepts, or "armed" and "has rules" drift apart.
if ! grep -qE '^[[:space:]]*[^#[:space:]]+[[:space:]]+[^[:space:]]' "$REPO/scripts/deny-list.txt" 2>/dev/null; then
    deny "executor deny-list at scripts/deny-list.txt has no usable rules — refusing to run unguarded"
fi
if [ -n "$CMDLINE" ]; then
    DENY_SPEC_FILES="$REPO/scripts/deny-list.txt"
    [ -f "$REPO/scripts/deny-list.local.txt" ] && DENY_SPEC_FILES="$DENY_SPEC_FILES $REPO/scripts/deny-list.local.txt"
    if DENY_REASON="$(deny_match "$CMDLINE" $DENY_SPEC_FILES)"; then
        deny "$DENY_REASON"
    fi
fi

# Layer 2 — read-only allowlist for the explore/validate roles.
case "$ROLE" in
    explore|validate)
        case " $READ_ALLOWLIST " in
            *" $NAME "*) : ;;
            *) deny "$ROLE role is read-only: tool '${NAME:-<unknown>}' is not a permitted read operation" ;;
        esac
        ;;
esac

allow
