#!/usr/bin/env bash
# Select and dispatch the orchestrator's executor — the selection layer above
# codex-mem.sh. Reads config.local.sh (via _lib.sh).
#
#   executor.sh --which            -> prints 'subagent' or 'cli:<key>'
#   executor.sh --run "<prompt>"   -> execs the CLI executor, or prints
#                                     EXECUTOR_USE_SUBAGENT (exit 3) for the subagent plane
#   executor.sh --show             -> human-readable diagnostics
#
# Exit codes: 0 resolved | 1 preferred unavailable + no fallback |
#             2 unknown executor / usage error | 3 --run resolved to subagent
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

EXECUTOR="${AI_MEMORY_EXECUTOR:-claude-subagent}"
# Unset -> default claude-subagent; set-but-empty -> no fallback (hard-fail).
FALLBACK="${AI_MEMORY_EXECUTOR_FALLBACK-claude-subagent}"

first_word() { set -f; set -- $1; set +f; printf '%s' "${1:-}"; }

# Look up the command template for a generic CLI key (empty if unset/invalid name).
cmd_template() {
    local key="$1" var tmpl
    case "$key" in *[!A-Za-z0-9_]*) printf ''; return 0 ;; esac
    var="AI_MEMORY_EXECUTOR_CMD_${key}"
    eval "tmpl=\${${var}:-}"
    printf '%s' "$tmpl"
}

# Single-quote a string for safe eval.
shq() { local s="${1:-}" sq="'" esc="'\\''"; s="${s//$sq/$esc}"; printf "'%s'" "$s"; }

# Exec the resolved CLI executor for <key> with <prompt>. Does not return.
run_cli() {
    local key="$1" prompt="$2" tmpl q cmd
    if [ "$key" = "codex" ]; then
        exec "$SCRIPT_DIR/codex-mem.sh" --executor "$prompt" </dev/null
    fi
    tmpl="$(cmd_template "$key")"
    q="$(shq "$prompt")"
    cmd="${tmpl//\{prompt\}/$q}"
    eval "exec ${cmd} </dev/null"
}

# Resolve a single executor key with NO fallback.
# Prints 'subagent' or 'cli:<key>' on success (0).
# Returns 1 = CLI binary unavailable, 2 = unknown key / bad template.
resolve_one() {
    local key="$1" tmpl bin
    if [ "$key" = "claude-subagent" ]; then
        printf 'subagent\n'; return 0
    fi
    if [ "$key" = "codex" ]; then
        bin=codex
    else
        tmpl="$(cmd_template "$key")"
        if [ -z "$tmpl" ]; then
            printf 'executor: unknown executor %s (set AI_MEMORY_EXECUTOR_CMD_%s or use a built-in)\n' "$key" "$key" >&2
            return 2
        fi
        case "$tmpl" in
            *'{prompt}'*) : ;;
            *) printf 'executor: AI_MEMORY_EXECUTOR_CMD_%s must contain {prompt}\n' "$key" >&2; return 2 ;;
        esac
        bin="$(first_word "$tmpl")"
    fi
    if command -v "$bin" >/dev/null 2>&1; then
        printf 'cli:%s\n' "$key"; return 0
    fi
    printf 'executor: %s unavailable (%s not in PATH)\n' "$key" "$bin" >&2
    return 1
}

# Resolve with fallback. Prints plane; returns 0/1/2.
resolve() {
    local out rc
    out="$(resolve_one "$EXECUTOR")"; rc=$?
    if [ "$rc" -eq 0 ]; then printf '%s\n' "$out"; return 0; fi
    if [ "$rc" -eq 2 ]; then return 2; fi
    # rc=1 unavailable -> try fallback if set
    if [ -n "$FALLBACK" ]; then
        printf 'executor: %s unavailable; falling back to %s\n' "$EXECUTOR" "$FALLBACK" >&2
        out="$(resolve_one "$FALLBACK")"; rc=$?
        [ "$rc" -eq 0 ] && { printf '%s\n' "$out"; return 0; }
        return "$rc"
    fi
    printf 'executor: %s unavailable and no fallback set\n' "$EXECUTOR" >&2
    return 1
}

MODE="${1:-}"
case "$MODE" in
    --which)
        resolve; exit $?
        ;;
    --run)
        PROMPT="${2:-}"
        if [ -z "$PROMPT" ]; then
            printf 'executor --run: missing prompt argument\n' >&2; exit 2
        fi
        PLANE="$(resolve)"; rc=$?
        [ "$rc" -eq 0 ] || exit "$rc"
        case "$PLANE" in
            subagent) printf 'EXECUTOR_USE_SUBAGENT\n'; exit 3 ;;
            cli:*)    run_cli "${PLANE#cli:}" "$PROMPT" ;;
        esac
        ;;
    --show)
        printf 'AI_MEMORY_EXECUTOR          = %s\n' "$EXECUTOR"
        printf 'AI_MEMORY_EXECUTOR_FALLBACK = %s\n' "${FALLBACK:-<empty>}"
        if PLANE="$(resolve 2>/dev/null)"; then
            printf 'resolved plane              = %s\n' "$PLANE"
        else
            printf 'resolved plane              = <unresolved, rc=%s>\n' "$?"
        fi
        ;;
    *)
        printf 'usage: executor.sh --which | --run "<prompt>" | --show\n' >&2
        exit 2
        ;;
esac
