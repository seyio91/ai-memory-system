#!/usr/bin/env bash
# Shared infra guard for executor hook contexts: executor roles (AI_MEMORY_ROLE)
# get the shared destructive/additive infra deny-list. AI_MEMORY_GUARD_SCOPE
# widens it: empty/`executor` (default) leaves interactive sessions untouched;
# `all` also guards role-less calls: subagents are denied; the main session is
# asked to confirm only when its permission_mode is default/plan/acceptEdits
# (the modes where Claude shows the prompt) and denied in any other mode
# (bypassPermissions, dontAsk, unknown or missing), since Claude would turn an
# unshown `ask` into allow. Any other scope value is treated as `all` with a
# warning.
#
# AI_MEMORY_GUARD_OUTPUT=opencode (opencode plugin, harnesses/opencode/plugin/ai-memory.ts):
# stdin is the `execute.before` event ({tool, sessionID, agent, input:{command}});
# the shell tool is "shell", with the command in input.command. Every verdict is
# an explicit one-line JSON object on stdout with exit 0, which the plugin parses
# and FAILS CLOSED on (anything else - non-zero exit, empty or unparseable output
# - is treated as deny):
#   {"decision":"allow"}                      (optionally + "systemMessage")
#   {"decision":"deny","reason":"..."}
# Unparseable input or a missing "tool" is denied in every context. Under
# AI_MEMORY_ROLE=explore|validate only the read tools in OC_READ_ALLOWLIST pass
# (allowlist: unknown/new tool names fail safe). Scope rules are otherwise as above.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
. "$REPO/scripts/jsonutil.sh"
. "$REPO/scripts/deny-match.sh"
. "$REPO/scripts/path-match.sh"

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

OC=0
[ "${AI_MEMORY_GUARD_OUTPUT:-}" = opencode ] && OC=1
OC_EMITTED=""
# Read tools allowed for explore/validate under opencode (v2 tool ids, lowercase).
OC_READ_ALLOWLIST="read glob grep webfetch websearch skill question"
if [ "$OC" -eq 1 ]; then
    # Every exit 0 that did not emit a verdict itself becomes an explicit allow.
    # shellcheck disable=SC2329  # invoked via trap
    oc_exit_trap() {
        local rc=$?
        if [ "$rc" -eq 0 ] && [ -z "$OC_EMITTED" ]; then printf '{"decision":"allow"}\n'; fi
    }
    trap oc_exit_trap EXIT
fi

deny() {
    if [ "$OC" -eq 1 ]; then
        OC_EMITTED=1
        printf '{"decision":"deny","reason":%s}\n' "$(json_escape "$1")"
        exit 0
    elif [ "${AI_MEMORY_GUARD_OUTPUT:-}" = copilot-json ]; then
        printf '{"permissionDecision":"deny","permissionDecisionReason":%s}\n' "$(json_escape "$1")"
        exit 0
    else
        printf '%s\n' "$1" >&2
        exit 2
    fi
}

# Main-session Claude (AI_MEMORY_GUARD_SCOPE=all, no role, no agent_id) is asked
# instead of denied when its permission_mode shows prompts (see header).
ask() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":%s}}\n' "$(json_escape "$1$SCOPE_NOTE")"
    exit 0
}

# Main-session deny-list load failures (missing/empty list) fail open with a
# visible warning; other contexts deny. A missing JSON parser is not routed here:
# it denies in every context (see below).
guard_fail() {
    if [ "$CONTEXT" = main ]; then
        if [ "$OC" -eq 1 ]; then
            OC_EMITTED=1
            printf '{"decision":"allow","systemMessage":%s}\n' "$(json_escape "ai-memory guard: ${2:-$1} — deny-list NOT enforced$SCOPE_NOTE")"
            exit 0
        fi
        printf '{"systemMessage":%s}\n' "$(json_escape "ai-memory guard: ${2:-$1} — deny-list NOT enforced$SCOPE_NOTE")"
        exit 0
    fi
    deny "$1$SCOPE_NOTE"
}

# opencode: the plugin always sends a well-formed event; anything else is denied
# before the scope early-exit so a mangled call can never ride the unguarded path.
OC_TOOL=""
if [ "$OC" -eq 1 ]; then
    json_parser_available || deny "no jq/python3, cannot inspect tool call"
    OC_TOOL="$(printf '%s' "$INPUT" | json_get tool)" || OC_TOOL=""
    [ -n "$OC_TOOL" ] || deny "malformed opencode execute.before input (no tool name), refusing to run unguarded"
    # Every tool-name comparison below uses the lowercased name (oc_normalize does too).
    OC_TOOL="$(printf '%s' "$OC_TOOL" | tr '[:upper:]' '[:lower:]')"
fi

# oc_normalize <event json> <tool>: map an opencode execute.before event onto the
# {tool_name, tool_input, cwd} shape path_guard_match handles. Verified on v2.2.6
# (live tool_use + execute.before capture): write {path, content}, edit {path,
# oldString, newString}, shell {command}. `path` may be relative; cwd is the
# plugin-supplied event.directory (else the guard's own cwd); shell also honours
# input.workdir. Code Mode spike (v2.2.6): the patch tool is `patch` with field `patchText`
# (`apply_patch` aliases map to `patch`). Both names are accepted, patchText first, with
# patch/command/input as fallbacks; a missing or non-"*** Begin Patch"
# body is denied by path_guard_match as unparseable. A write-capable tool with no
# extractable target yields an empty target, which path_guard_match denies (fail closed).
oc_normalize() {
    local ev="$1" tool cwd target patch k wd
    tool="$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')"
    cwd="$(printf '%s' "$ev" | json_get directory)"
    [ -n "$cwd" ] || cwd="$(printf '%s' "$ev" | json_get cwd)"
    [ -n "$cwd" ] || cwd="$PWD"
    case "$tool" in
        write|edit|multiedit)
            target="$(printf '%s' "$ev" | json_get_path input path)"
            [ -n "$target" ] || target="$(printf '%s' "$ev" | json_get_path input filePath)"
            [ -n "$target" ] || target="$(printf '%s' "$ev" | json_get_path input file_path)"
            printf '{"tool_name":"Write","tool_input":{"file_path":%s},"cwd":%s}' "$(json_escape "$target")" "$(json_escape "$cwd")"
            ;;
        shell|bash)
            # The tool's own workdir is where the command runs: it, not the plugin
            # directory, is the cwd for relative targets (relative workdir: against directory).
            wd="$(printf '%s' "$ev" | json_get_path input workdir)"
            case "$wd" in
                "") ;;
                /*) cwd="$wd" ;;
                *) cwd="$cwd/$wd" ;;
            esac
            printf '{"tool_name":"Bash","tool_input":{"command":%s},"cwd":%s}' "$(json_escape "$(printf '%s' "$ev" | json_get_path input command)")" "$(json_escape "$cwd")"
            ;;
        patch|apply_patch)
            patch=""
            for k in patchText patch command input; do
                [ -n "$patch" ] || patch="$(printf '%s' "$ev" | json_get_path input "$k")"
            done
            printf '{"tool_name":"apply_patch","tool_input":{"command":%s},"cwd":%s}' "$(json_escape "$patch")" "$(json_escape "$cwd")"
            ;;
        experimental_image_generate)
            # Writes an image to input.path/filePath: same protected-path check as write.
            target="$(printf '%s' "$ev" | json_get_path input path)"
            [ -n "$target" ] || target="$(printf '%s' "$ev" | json_get_path input filePath)"
            [ -n "$target" ] || target="$(printf '%s' "$ev" | json_get_path input file_path)"
            printf '{"tool_name":"Write","tool_input":{"file_path":%s},"cwd":%s}' "$(json_escape "$target")" "$(json_escape "$cwd")"
            ;;
        *) printf '%s' "$ev" ;;
    esac
}

# Raw pre-filter keeps the main session off the JSON parse (~130ms per call); path_guard_match
# re-checks agent_id on the parsed input, so a coincidental match costs time, never a deny.
# A `case`, not `printf | grep -q`: under pipefail grep's early exit SIGPIPEs printf on large input.
PG_SUSPECT=0
case "$INPUT" in *'"agent_id"'*) PG_SUSPECT=1 ;; esac
PG_INPUT="$INPUT"
if [ "$OC" -eq 1 ]; then
    # opencode tools -> the Claude shapes path_guard_match understands (see oc_normalize).
    PG_INPUT="$(oc_normalize "$INPUT" "$OC_TOOL")"
fi
if { [ -n "$ROLE" ] || [ "$PG_SUSPECT" -eq 1 ]; } \
    && PATH_REASON="$(path_guard_match "$PG_INPUT")"; then
    deny "$PATH_REASON"
fi

[ -n "$ROLE" ] || [ "$SCOPE" = all ] || exit 0

# agent_id is present only in subagent tool calls. The raw grep runs first so the
# subagent context is still detected when no JSON parser is available (a missing
# parser denies in every context, below).
CONTEXT=executor
if [ -z "$ROLE" ]; then
    CONTEXT=main
    if printf '%s' "$INPUT" | grep -q '"agent_id"' \
        || [ -n "$(printf '%s' "$INPUT" | json_get agent_id)" ]; then
        CONTEXT=subagent
    fi
fi

if ! json_parser_available; then
    deny "no jq/python3, cannot inspect tool call$SCOPE_NOTE"
fi

# The shell command lives at different JSON paths per harness's PreToolUse stdin:
# Codex/Claude family use tool_input.command (verified against real codex 0.144.1
# stdin); Antigravity uses toolCall.args.CommandLine; Copilot uses a JSON-encoded
# toolArgs string, verified by scripts/tests/fixtures/copilot/pre_tool_use_bash.json.
# Read primary consumers first, then fall back to each real captured shape so a
# wrong path can never silently read empty and fail OPEN.
if [ "$OC" -eq 1 ]; then
    # opencode: input.command, shell tool only (verified, scripts/tests/fixtures/opencode/execute-before-shell*.json).
    CMDLINE=""
    case "$OC_TOOL" in shell|bash) CMDLINE="$(printf '%s' "$INPUT" | json_get_path input command)" ;; esac
else
    CMDLINE="$(printf '%s' "$INPUT" | json_get_path tool_input command)"
    [ -n "$CMDLINE" ] || CMDLINE="$(printf '%s' "$INPUT" | json_get_path toolCall args CommandLine)"
    [ -n "$CMDLINE" ] || CMDLINE="$(printf '%s' "$INPUT" | json_get_encoded_path toolArgs command)"
fi

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
        if [ "$CONTEXT" = main ]; then
            PERM_MODE="$(printf '%s' "$INPUT" | json_get permission_mode)"
            case "$PERM_MODE" in
                default|plan|acceptEdits) ask "$DENY_REASON" ;;
            esac
            DENY_REASON="$DENY_REASON (main session, permission_mode=${PERM_MODE:-unset}: confirmation prompts are not shown in this mode)"
        fi
        deny "$DENY_REASON$SCOPE_NOTE"
    fi
fi

# opencode guarded roles (task/explore/validate): tools that can mutate outside what this
# guard inspects are denied. `execute` is Code Mode (JS calling other tools in-process);
# worktree/artifact/schedule tools mutate state; `subagent` starts a child session whose
# guard we cannot verify. Other unknown tools (MCP) stay allowed for task, as on Claude/Codex.
if [ "$OC" -eq 1 ] && [ -n "$ROLE" ]; then
    case "$OC_TOOL" in
        opencode_session_*|session_*) deny "tool '$OC_TOOL' is not permitted for the $ROLE role (session move/rename could leave the directory that holds the guard plugin)" ;;
        execute|opencode_worktree_*|worktree_*|opencode_artifact_*|artifact_*|opencode_schedule_*|schedule_*|*subagent*)
            deny "tool '$OC_TOOL' is not permitted for the $ROLE role (Code Mode, state-mutating or child-session tool the guard cannot inspect)" ;;
    esac
fi

# opencode read-only roles: allowlist of read tools; everything else (edit, write,
# patch, shell, subagent, MCP tools, ...) is denied.
if [ "$OC" -eq 1 ]; then
    case "$ROLE" in
        explore|validate)
            case " $OC_READ_ALLOWLIST " in
                *" $OC_TOOL "*) : ;;
                *) deny "$ROLE role is read-only: tool '$OC_TOOL' is not a permitted read operation" ;;
            esac
            ;;
    esac
fi

# Copilot allows hook stdout to be empty on allow (Phase 0 postToolUse/preToolUse
# probes); only deny needs its JSON permissionDecision envelope.
if [ "$CONTEXT" = main ] && [ -n "$SCOPE_NOTE" ]; then
    if [ "$OC" -eq 1 ]; then
        OC_EMITTED=1
        printf '{"decision":"allow","systemMessage":%s}\n' "$(json_escape "ai-memory guard: unknown AI_MEMORY_GUARD_SCOPE '$SCOPE_UNKNOWN', treating as all")"
        exit 0
    fi
    printf '{"systemMessage":%s}\n' "$(json_escape "ai-memory guard: unknown AI_MEMORY_GUARD_SCOPE '$SCOPE_UNKNOWN', treating as all")"
fi
exit 0
