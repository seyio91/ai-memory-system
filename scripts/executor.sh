#!/usr/bin/env bash
# Select and dispatch the orchestrator's executor. Resolution is driven by the
# harness registry (harnesses/<name>/manifest exec_* block) — no per-harness code
# here. Two roles select independent config, each a `harness[:model]` value:
#   task     -> AI_MEMORY_EXECUTOR_TASK    (write-capable; a plan step)
#   explore  -> AI_MEMORY_EXECUTOR_EXPLORE (read-only scouting)
# Each falls back to the legacy single AI_MEMORY_EXECUTOR, then to claude-subagent.
#
#   executor.sh [--role task|explore] --which          -> 'subagent[:model]' | 'cli:<name>'
#   executor.sh [--role task|explore] --run "<prompt>" -> execs the CLI executor, or prints
#                                                          EXECUTOR_USE_SUBAGENT (exit 3)
#   executor.sh [--role ...] --show                    -> human-readable diagnostics
#
# A registered harness resolves through its manifest: exec=subagent -> subagent
# plane; else exec_cmd (task) / exec_readonly (explore), gated on exec_probe being
# on PATH. A harness with no read-only mode is skipped for `explore` (degrades to
# the subagent Explore plane), never run write-capable. An unregistered name falls
# back to a legacy AI_MEMORY_EXECUTOR_CMD_<key> template.
#
# Exit codes: 0 resolved | 1 preferred unavailable + no fallback |
#             2 unknown executor / usage error | 3 --run resolved to subagent
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"
. "$SCRIPT_DIR/manifest.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
# Registry location (override for tests / non-standard layouts).
HARNESSES_DIR="${AI_MEMORY_HARNESSES_DIR:-$REPO_ROOT/harnesses}"

FALLBACK="${AI_MEMORY_EXECUTOR_FALLBACK-claude-subagent}"
ROLE="task"

first_word() { set -f; set -- $1; set +f; printf '%s' "${1:-}"; }
shq() { local s="${1:-}" sq="'" esc="'\\''"; s="${s//$sq/$esc}"; printf "'%s'" "$s"; }
expand_memdir() { printf '%s' "${1//\$MEMORY_DIR/$MEMORY_DIR}"; }

# The configured value for the active role: role var -> legacy var -> claude-subagent.
role_value() {
    local v=""
    case "$ROLE" in
        task)    v="${AI_MEMORY_EXECUTOR_TASK-}" ;;
        explore) v="${AI_MEMORY_EXECUTOR_EXPLORE-}" ;;
    esac
    [ -n "$v" ] || v="${AI_MEMORY_EXECUTOR-}"
    [ -n "$v" ] || v="claude-subagent"
    printf '%s' "$v"
}

harness_manifest() {
    local mf="$HARNESSES_DIR/$1/manifest"
    [ -f "$mf" ] && printf '%s' "$mf"
}

cmd_template() {
    local key="$1" var tmpl
    case "$key" in *[!A-Za-z0-9_-]*) printf ''; return 0 ;; esac
    var="AI_MEMORY_EXECUTOR_CMD_${key//-/_}"
    eval "tmpl=\${${var}:-}"
    printf '%s' "$tmpl"
}

# resolve_value <harness[:model]> — sets R_PLANE (subagent|cli), R_NAME, R_MODEL,
# R_CMD (cli command template, {prompt} unsubstituted). Returns:
#   0 resolved | 1 CLI unavailable | 2 unknown / no execute face
R_PLANE="" R_NAME="" R_MODEL="" R_CMD=""
resolve_value() {
    local value="$1" harness model mf cmd mflag probe
    harness="${value%%:*}"; model=""
    case "$value" in *:*) model="${value#*:}" ;; esac
    R_PLANE="" R_NAME="$harness" R_MODEL="$model" R_CMD=""

    # subagent plane: legacy sentinel or a manifest exec=subagent.
    if [ "$harness" = "claude-subagent" ]; then R_PLANE=subagent; return 0; fi

    mf="$(harness_manifest "$harness")"
    if [ -n "$mf" ]; then
        if [ "$(manifest_get "$mf" exec)" = subagent ]; then R_PLANE=subagent; return 0; fi
        if [ "$ROLE" = explore ]; then
            cmd="$(manifest_get "$mf" exec_readonly)"
            if [ -z "$cmd" ]; then
                printf 'executor: harness %s has no read-only mode (exec_readonly) — exploration degrades to the subagent Explore plane\n' "$harness" >&2
                R_PLANE=subagent; return 0
            fi
        else
            cmd="$(manifest_get "$mf" exec_cmd)"
            if [ -z "$cmd" ]; then
                printf 'executor: harness %s has no execute face (no exec_cmd)\n' "$harness" >&2
                return 2
            fi
        fi
        # thread model (append the filled model flag) when a model was requested
        if [ -n "$model" ]; then
            mflag="$(manifest_get "$mf" exec_model_flag)"
            [ -n "$mflag" ] && cmd="$cmd ${mflag//\{model\}/$model}"
        fi
        cmd="$(expand_memdir "$cmd")"
        # availability probe: exec_probe, else the first word of exec_cmd
        probe="$(manifest_get "$mf" exec_probe)"
        [ -n "$probe" ] || probe="$(first_word "$(expand_memdir "$(manifest_get "$mf" exec_cmd)")")"
        if ! command -v "$probe" >/dev/null 2>&1 && [ ! -x "$probe" ]; then
            printf 'executor: %s unavailable (%s not found)\n' "$harness" "$probe" >&2
            return 1
        fi
        R_PLANE=cli; R_CMD="$cmd"; return 0
    fi

    # legacy generic CLI template
    local tmpl bin
    tmpl="$(cmd_template "$harness")"
    if [ -z "$tmpl" ]; then
        printf 'executor: unknown executor %s (register a harness manifest, set AI_MEMORY_EXECUTOR_CMD_%s, or use claude-subagent)\n' "$harness" "$harness" >&2
        return 2
    fi
    case "$tmpl" in *'{prompt}'*) : ;; *) printf 'executor: AI_MEMORY_EXECUTOR_CMD_%s must contain {prompt}\n' "$harness" >&2; return 2 ;; esac
    bin="$(first_word "$tmpl")"
    if ! command -v "$bin" >/dev/null 2>&1; then
        printf 'executor: %s unavailable (%s not in PATH)\n' "$harness" "$bin" >&2; return 1
    fi
    R_PLANE=cli; R_CMD="$tmpl"; return 0
}

# resolve — resolve the active role's value, applying the fallback chain.
# Sets R_* on success. Returns 0 | 1 (unavailable, no fallback) | 2 (unknown).
resolve() {
    local value rc
    value="$(role_value)"
    resolve_value "$value"; rc=$?
    if [ "$rc" -eq 0 ]; then return 0; fi
    if [ "$rc" -eq 2 ]; then return 2; fi
    if [ -n "$FALLBACK" ]; then
        printf 'executor: %s unavailable; falling back to %s\n' "$value" "$FALLBACK" >&2
        resolve_value "$FALLBACK"; rc=$?
        [ "$rc" -eq 0 ] && return 0
        return "$rc"
    fi
    printf 'executor: %s unavailable and no fallback set\n' "$value" >&2
    return 1
}

# Print the resolved plane token: 'subagent', 'subagent:<model>', or 'cli:<name>'.
plane_token() {
    case "$R_PLANE" in
        subagent) [ -n "$R_MODEL" ] && printf 'subagent:%s\n' "$R_MODEL" || printf 'subagent\n' ;;
        cli)      printf 'cli:%s\n' "$R_NAME" ;;
    esac
}

# --- arg parse: optional --role, then the mode ---
while [ "$#" -gt 0 ]; do
    case "$1" in
        --role) ROLE="${2:-task}"; shift 2 ;;
        --role=*) ROLE="${1#*=}"; shift ;;
        *) break ;;
    esac
done
case "$ROLE" in task|explore) ;; *) printf 'executor: --role must be task|explore\n' >&2; exit 2 ;; esac

MODE="${1:-}"
case "$MODE" in
    --which)
        resolve || exit $?
        plane_token
        ;;
    --run)
        PROMPT="${2:-}"
        if [ -z "$PROMPT" ]; then
            printf 'executor --run: missing prompt argument\n' >&2; exit 2
        fi
        resolve || exit $?
        if [ "$R_PLANE" = subagent ]; then
            printf 'EXECUTOR_USE_SUBAGENT\n'; exit 3
        fi
        q="$(shq "$PROMPT")"
        cmd="${R_CMD//\{prompt\}/$q}"
        # Advertise the role to the executor process (and any hooks it spawns) so a
        # hook-capable harness can enforce it — e.g. the Antigravity PreToolUse guard
        # applies the deny-list for both roles and denies writes when explore. Unset
        # for interactive sessions, which stay unguarded.
        export AI_MEMORY_ROLE="$ROLE"
        eval "exec ${cmd} </dev/null"
        ;;
    --show)
        printf 'role                        = %s\n' "$ROLE"
        printf 'AI_MEMORY_EXECUTOR_TASK     = %s\n' "${AI_MEMORY_EXECUTOR_TASK-<unset>}"
        printf 'AI_MEMORY_EXECUTOR_EXPLORE  = %s\n' "${AI_MEMORY_EXECUTOR_EXPLORE-<unset>}"
        printf 'AI_MEMORY_EXECUTOR (legacy) = %s\n' "${AI_MEMORY_EXECUTOR-<unset>}"
        printf 'AI_MEMORY_EXECUTOR_FALLBACK = %s\n' "${FALLBACK:-<empty>}"
        printf 'resolved value              = %s\n' "$(role_value)"
        if resolve 2>/dev/null; then
            printf 'resolved plane              = %s\n' "$(plane_token)"
            [ "$R_PLANE" = cli ] && printf 'resolved command            = %s\n' "$R_CMD"
        else
            printf 'resolved plane              = <unresolved, rc=%s>\n' "$?"
        fi
        ;;
    *)
        printf 'usage: executor.sh [--role task|explore] --which | --run "<prompt>" | --show\n' >&2
        exit 2
        ;;
esac
