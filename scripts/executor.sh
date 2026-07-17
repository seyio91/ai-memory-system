#!/usr/bin/env bash
# Select and dispatch the orchestrator's executor. Resolution is driven by the
# harness registry (harnesses/<name>/manifest exec_* block) — no per-harness code
# here. Three roles select independent config, each a `harness[:model]` value:
#   task     -> AI_MEMORY_EXECUTOR_TASK     (write-capable; a plan step)
#   explore  -> AI_MEMORY_EXECUTOR_EXPLORE  (read-only scouting)
#   validate -> AI_MEMORY_EXECUTOR_VALIDATE (read-only check of executor output; defaults to 'subagent', NOT the legacy var)
# Task/explore fall back to the legacy single AI_MEMORY_EXECUTOR, then to 'subagent'.
# 'subagent' is orchestrator-relative: the calling harness's own subagent plane
# (Claude's Agent tool, Copilot's background agents, ...). 'claude-subagent' is
# its accepted legacy alias.
#
#   executor.sh [--role task|explore|validate] --which          -> 'subagent[:model]' | 'cli:<name>'
#   executor.sh [--role task|explore|validate] --run [--clean] "<prompt>" -> execs the CLI executor, or
#                                                                   prints EXECUTOR_USE_SUBAGENT (exit 3)
#     NB: a cli: --run runs a minutes-long, one-shot agentic loop — the caller must dispatch it as a
#     background task (the orchestrator's run_in_background), never a foreground timeout-bound Bash call.
#     --clean: emit ONLY the final agent message (uniform across harnesses) for a cli: executor that
#     declares exec_last_message (e.g. codex `-o {file}`); a harness without it passes its raw stream
#     through unchanged (e.g. agy `-p`, already just the final message).
#   executor.sh [--role ...] --show                    -> human-readable diagnostics
#
# A registered harness resolves through its manifest: exec=subagent -> subagent
# plane; else exec_cmd (task) / exec_readonly (explore/validate), gated on
# exec_probe being on PATH. A harness with no read-only mode is skipped for
# `explore`/`validate` (degrades to the subagent plane), never run write-capable.
# An unregistered name falls back to a legacy AI_MEMORY_EXECUTOR_CMD_<key> template.
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

FALLBACK="${AI_MEMORY_EXECUTOR_FALLBACK-subagent}"
ROLE="task"

# Deliberate first-word split with globbing disabled.
# shellcheck disable=SC2086
first_word() { set -f; set -- $1; set +f; printf '%s' "${1:-}"; }
shq() { local s="${1:-}" sq="'" esc="'\\''"; s="${s//$sq/$esc}"; printf "'%s'" "$s"; }
expand_memdir() { printf '%s' "${1//\$MEMORY_DIR/$MEMORY_DIR}"; }

# The configured value for the active role.
role_value() {
    local v=""
    case "$ROLE" in
        task)     v="${AI_MEMORY_EXECUTOR_TASK-}" ;;
        explore)  v="${AI_MEMORY_EXECUTOR_EXPLORE-}" ;;
        validate) v="${AI_MEMORY_EXECUTOR_VALIDATE-}"; [ -n "$v" ] || v="subagent"; printf '%s' "$v"; return 0 ;;
    esac
    [ -n "$v" ] || v="${AI_MEMORY_EXECUTOR-}"
    [ -n "$v" ] || v="subagent"
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
# R_CMD (cli command template, {prompt} unsubstituted), R_LASTMSG (the harness's
# exec_last_message flag template with {file} unsubstituted, or "" if it declares
# none — see the --run --clean handler). Returns:
#   0 resolved | 1 CLI unavailable | 2 unknown / no execute face
R_PLANE="" R_NAME="" R_MODEL="" R_CMD="" R_LASTMSG=""
resolve_value() {
    local value="$1" harness model mf cmd mflag probe
    harness="${value%%:*}"; model=""
    case "$value" in *:*) model="${value#*:}" ;; esac
    R_PLANE="" R_NAME="$harness" R_MODEL="$model" R_CMD="" R_LASTMSG=""

    # subagent plane: the canonical 'subagent' sentinel, its legacy alias
    # 'claude-subagent' (kept so existing config.local.sh files keep working),
    # or a manifest exec=subagent. The sentinel is orchestrator-relative — it
    # means "the calling harness's OWN subagent mechanism" (Claude's Agent
    # tool, Copilot's background agents, ...), never a specific harness.
    if [ "$harness" = "subagent" ] || [ "$harness" = "claude-subagent" ]; then R_PLANE=subagent; return 0; fi

    mf="$(harness_manifest "$harness")"
    if [ -n "$mf" ]; then
        if [ "$(manifest_get "$mf" exec)" = subagent ]; then R_PLANE=subagent; return 0; fi
        case "$ROLE" in explore|validate)
            cmd="$(manifest_get "$mf" exec_readonly)"
            if [ -z "$cmd" ]; then
                printf 'executor: harness %s has no read-only mode (exec_readonly) — %s degrades to the subagent plane\n' "$harness" "$ROLE" >&2
                R_PLANE=subagent; R_MODEL=""; return 0
            fi
            ;;
        *)
            cmd="$(manifest_get "$mf" exec_cmd)"
            if [ -z "$cmd" ]; then
                printf 'executor: harness %s has no execute face (no exec_cmd)\n' "$harness" >&2
                return 2
            fi
            ;;
        esac
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
        # optional clean-output flag template (e.g. codex `-o {file}`); "" if absent.
        R_LASTMSG="$(expand_memdir "$(manifest_get "$mf" exec_last_message)")"
        R_PLANE=cli; R_CMD="$cmd"; return 0
    fi

    # legacy generic CLI template
    local tmpl bin
    tmpl="$(cmd_template "$harness")"
    if [ -z "$tmpl" ]; then
        printf 'executor: unknown executor %s (register a harness manifest, set AI_MEMORY_EXECUTOR_CMD_%s, or use subagent)\n' "$harness" "$harness" >&2
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
        # NB: `shift 2` with only one arg left is a NO-OP that returns 1, and this
        # script runs `set -uo pipefail` (no -e) — so a trailing `--role` used to
        # leave $1 == "--role" and spin this loop forever. Demand the value first.
        --role)
            [ "$#" -ge 2 ] || {
                printf 'executor: --role needs a value (task|explore|validate)\n' >&2
                exit 2
            }
            ROLE="$2"; shift 2 ;;
        --role=*) ROLE="${1#*=}"; shift ;;
        *) break ;;
    esac
done
case "$ROLE" in task|explore|validate) ;; *) printf 'executor: --role must be task|explore|validate\n' >&2; exit 2 ;; esac

MODE="${1:-}"
case "$MODE" in
    --which)
        resolve || exit $?
        plane_token
        ;;
    --run)
        # Parse the remaining args: an optional --clean flag (either side of the
        # prompt) plus exactly one prompt. --clean makes a cli: executor emit ONLY
        # the final agent message, uniform across harnesses (see below).
        shift  # drop --run
        CLEAN=0; PROMPT=""; HAVE_PROMPT=0
        while [ "$#" -gt 0 ]; do
            case "$1" in
                --clean) CLEAN=1 ;;
                *)
                    if [ "$HAVE_PROMPT" -eq 0 ]; then PROMPT="$1"; HAVE_PROMPT=1
                    else printf 'executor --run: unexpected extra argument: %s\n' "$1" >&2; exit 2; fi ;;
            esac
            shift
        done
        if [ "$HAVE_PROMPT" -eq 0 ]; then
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
        # --clean + a harness that declares exec_last_message (e.g. codex `-o {file}`):
        # can't `exec` here (process replacement leaves nothing to post-process), so run
        # the CLI writing its final message to a temp file, then emit only that file and
        # propagate the CLI's exit code. A harness with no exec_last_message (e.g. agy,
        # whose `-p` output is already just the final message) falls through to the plain
        # exec path — --clean is a no-op pass-through there.
        if [ "$CLEAN" -eq 1 ] && [ -n "$R_LASTMSG" ]; then
            tmp="$(mktemp)" || { printf 'executor --run: mktemp failed\n' >&2; exit 1; }
            errlog="$(mktemp)" || { rm -f "$tmp"; printf 'executor --run: mktemp failed\n' >&2; exit 1; }
            trap 'rm -f "$tmp" "$errlog"' EXIT
            lastflag="${R_LASTMSG//\{file\}/$(shq "$tmp")}"
            # The CLI writes its final message to $tmp (exec_last_message flag). Discard
            # its stdout, and capture its stderr — codex puts its human transcript there,
            # verified — to $errlog rather than letting it pollute our output. On SUCCESS
            # we emit ONLY the final message (with exactly one trailing newline); on
            # FAILURE we additionally replay the captured stderr so the caller can debug,
            # and always propagate the CLI's exit code.
            eval "${cmd} ${lastflag} </dev/null >/dev/null 2>$(shq "$errlog")"
            rc=$?
            [ -s "$tmp" ] && printf '%s\n' "$(cat "$tmp")"
            [ "$rc" -ne 0 ] && cat "$errlog" >&2
            exit "$rc"
        fi
        eval "exec ${cmd} </dev/null"
        ;;
    --show)
        printf 'role                         = %s\n' "$ROLE"
        printf 'AI_MEMORY_EXECUTOR_TASK      = %s\n' "${AI_MEMORY_EXECUTOR_TASK-<unset>}"
        printf 'AI_MEMORY_EXECUTOR_EXPLORE   = %s\n' "${AI_MEMORY_EXECUTOR_EXPLORE-<unset>}"
        printf 'AI_MEMORY_EXECUTOR_VALIDATE  = %s\n' "${AI_MEMORY_EXECUTOR_VALIDATE-<unset>}"
        printf 'AI_MEMORY_EXECUTOR (legacy)  = %s\n' "${AI_MEMORY_EXECUTOR-<unset>}"
        printf 'AI_MEMORY_EXECUTOR_FALLBACK  = %s\n' "${FALLBACK:-<empty>}"
        printf 'resolved value               = %s\n' "$(role_value)"
        if resolve 2>/dev/null; then
            printf 'resolved plane               = %s\n' "$(plane_token)"
            [ "$R_PLANE" = cli ] && printf 'resolved command             = %s\n' "$R_CMD"
        else
            printf 'resolved plane               = <unresolved, rc=%s>\n' "$?"
        fi
        ;;
    *)
        printf 'usage: executor.sh [--role task|explore|validate] --which | --run [--clean] "<prompt>" | --show\n' >&2
        exit 2
        ;;
esac
