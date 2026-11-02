#!/usr/bin/env bash
# path-match.sh — deny guarded-context writes to guard config and plans.
# Sourceable and runnable. Public API:
#   path_guard_match "<hook input json>"
# Exit 0 means denied and prints a one-line reason; exit 1 means allowed.
# Guarded = AI_MEMORY_ROLE set or agent_id in the input; the main session is never denied.

_pg_realpath() { # <path> <base-for-relative>
    local rest="$1" cur="/" comp cand link n=0
    case "$rest" in /*) ;; *) rest="$2/$rest" ;; esac
    while [ -n "$rest" ]; do
        comp="${rest%%/*}"
        if [ "$comp" = "$rest" ]; then rest=""; else rest="${rest#*/}"; fi
        case "$comp" in
            ""|.) ;;
            ..) cur="${cur%/*}"; [ -n "$cur" ] || cur="/" ;;
            *)
                cand="${cur%/}/$comp"
                if [ -L "$cand" ]; then
                    n=$((n + 1))
                    [ "$n" -le 40 ] || { printf '%s' "$cand"; return 0; }
                    link="$(readlink "$cand")"
                    case "$link" in /*) cur="/" ;; esac
                    rest="$link/$rest"
                else
                    cur="$cand"
                fi
                ;;
        esac
    done
    printf '%s' "$cur"
}

_PG_FILE="$(_pg_realpath "${BASH_SOURCE[0]}" "$PWD")"
_PG_DIR="${_PG_FILE%/*}"
_PG_ROOT="${_PG_DIR%/*}"

. "$_PG_DIR/jsonutil.sh"
. "$_PG_DIR/deny-match.sh"

_pg_route="guard config and plans change only via the orchestrator; report this deny or the plan divergence in your return"

_pg_glob_to_regex() {
    local g="$1" out="" ch i=0
    while [ "$i" -lt "${#g}" ]; do
        ch="${g:$i:1}"
        case "$ch" in
            '*')
                if [ "${g:$((i + 1)):1}" = '*' ]; then out="${out}.*"; i=$((i + 1)); else out="${out}[^/]*"; fi
                ;;
            '?') out="${out}[^/]" ;;
            '.'|'['|']'|'('|')'|'{'|'}'|'+'|'^'|'$'|'|'|\\) out="${out}\\${ch}" ;;
            *) out="${out}${ch}" ;;
        esac
        i=$((i + 1))
    done
    printf '^%s$' "$out"
}

_pg_load() {
    local file="$_PG_DIR/protected-paths.txt" line
    _PG_RES=()
    [ -f "$file" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        line="$(_deny_trim "$line")"
        case "$line" in
            ''|'#'*) continue ;;
            \~/*) [ -n "${HOME:-}" ] || continue
                   line="$(_pg_realpath "$HOME/${line#\~/}" /)" ;;
            *) line="$_PG_ROOT/$line" ;;
        esac
        _PG_RES[${#_PG_RES[@]}]="$(_pg_glob_to_regex "$line")"
    done < "$file"
    [ "${#_PG_RES[@]}" -gt 0 ]
}

_pg_is_protected() { # <path> <cwd>
    local p="$1" base="$2" re
    case "$p" in
        '~') p="${HOME:-}" ;;
        \~/*) p="${HOME:-}/${p#\~/}" ;;
        '$HOME/'*) p="${HOME:-}/${p#\$HOME/}" ;;
        '${HOME}/'*) p="${HOME:-}/${p#\$\{HOME\}/}" ;;
    esac
    [ -n "$p" ] || return 1
    p="$(_pg_realpath "$p" "$base")"
    for re in "${_PG_RES[@]}"; do
        if [[ "$p" =~ $re ]] || [[ "$p/" =~ $re ]]; then return 0; fi
    done
    return 1
}

_pg_guarded() {
    [ -z "${AI_MEMORY_ROLE:-}" ] || return 0
    if json_parser_available; then
        [ -n "$(printf '%s' "$1" | json_get agent_id)" ]
    else
        printf '%s' "$1" | grep -q '"agent_id"'
    fi
}

_pg_bash_match() { # <command> <cwd>
    local cmd="$1" cwd="$2" seg i tok rest p idx base writes arg last
    local args
    _deny_split_segments "$cmd"
    for seg in "${DENY_SEGMENTS[@]}"; do
        [ -n "$seg" ] || continue
        _deny_tokenize_segment "$seg"
        [ "${#DENY_TOKENS[@]}" -gt 0 ] || continue

        i=0
        while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
            tok="${DENY_TOKENS[$i]}"
            i=$((i + 1))
            case "$tok" in *'>'*) ;; *) continue ;; esac
            rest="${tok#*>}"; rest="${rest#>}"; rest="${rest#|}"
            if [ -z "$rest" ] && [ "$i" -lt "${#DENY_TOKENS[@]}" ]; then rest="${DENY_TOKENS[$i]}"; fi
            if [ -n "$rest" ] && _pg_is_protected "$rest" "$cwd"; then
                PG_HIT="$rest"; return 0
            fi
        done

        _deny_command_start
        idx="$DENY_CMD_START"
        p="$idx"
        while [ "$p" -lt "${#DENY_TOKENS[@]}" ]; do
            base="$(_deny_basename "${DENY_TOKENS[$p]}")"
            writes=0
            case "$base" in
                cp|mv|rm|truncate|tee) writes=1 ;;
                sed)
                    i=$((p + 1))
                    while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
                        case "${DENY_TOKENS[$i]}" in
                            --in-place*|-i*|-[a-zA-Z]*i*) writes=1; break ;;
                        esac
                        i=$((i + 1))
                    done
                    ;;
            esac
            if [ "$writes" -eq 1 ]; then
                args=()
                i=$((p + 1))
                while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
                    case "${DENY_TOKENS[$i]}" in -*) ;; *) args[${#args[@]}]="${DENY_TOKENS[$i]}" ;; esac
                    i=$((i + 1))
                done
                if [ "$base" = cp ] && [ "${#args[@]}" -gt 0 ]; then
                    last="${args[$((${#args[@]} - 1))]}"
                    args=("$last")
                fi
                for arg in ${args[@]+"${args[@]}"}; do
                    if _pg_is_protected "$arg" "$cwd"; then PG_HIT="$arg"; return 0; fi
                done
                break
            fi
            [ "$DENY_WRAPPED" -eq 1 ] || break
            p=$((p + 1))
        done
    done
    return 1
}

path_guard_match() {
    local input="$1" tool target cwd cmd
    PG_HIT=""
    _pg_guarded "$input" || return 1
    if ! json_parser_available; then
        printf '%s\n' "path-guard: no jq/python3, cannot inspect tool call; $_pg_route"
        return 0
    fi
    if ! _pg_load; then
        printf '%s\n' "path-guard: scripts/protected-paths.txt missing or empty, refusing to run unguarded; $_pg_route"
        return 0
    fi
    tool="$(printf '%s' "$input" | json_get tool_name)"
    cwd="$(printf '%s' "$input" | json_get cwd)"
    [ -n "$cwd" ] || cwd="$PWD"
    case "$tool" in
        Write|Edit|NotebookEdit)
            target="$(printf '%s' "$input" | json_get_path tool_input file_path)"
            [ -n "$target" ] || target="$(printf '%s' "$input" | json_get_path tool_input notebook_path)"
            if [ -z "$target" ]; then
                printf '%s\n' "path-guard: cannot extract target path for $tool; $_pg_route"
                return 0
            fi
            if _pg_is_protected "$target" "$cwd"; then
                printf '%s\n' "path-guard: $target is protected; $_pg_route"
                return 0
            fi
            return 1
            ;;
        Bash)
            cmd="$(printf '%s' "$input" | json_get_path tool_input command)"
            [ -n "$cmd" ] || return 1
            if _pg_bash_match "$cmd" "$cwd"; then
                printf '%s\n' "path-guard: command writes protected path $PG_HIT; $_pg_route"
                return 0
            fi
            return 1
            ;;
        *) return 1 ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    path_guard_match "${1:-$(cat)}"
    exit $?
fi
