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
                    # Directories via builtins: the guard may run with a PATH lacking readlink.
                    if [ -d "$cand" ]; then
                        link="$(cd -P "$cand" 2>/dev/null && pwd -P)" || link=""
                    else
                        link="$(readlink "$cand" 2>/dev/null)" || link=""
                    fi
                    if [ -z "$link" ]; then
                        cur="$cand"
                    else
                        case "$link" in /*) cur="/" ;; esac
                        rest="$link/$rest"
                    fi
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

_pg_expand_home() {
    case "$1" in
        '~') printf '%s' "${HOME:-}" ;;
        \~/*) printf '%s' "${HOME:-}/${1#\~/}" ;;
        '$HOME/'*) printf '%s' "${HOME:-}/${1#\$HOME/}" ;;
        '${HOME}/'*) printf '%s' "${HOME:-}/${1#\$\{HOME\}/}" ;;
        *) printf '%s' "$1" ;;
    esac
}

_pg_is_dir_dest() { # <path> <cwd>
    local p
    case "$1" in */) return 0 ;; esac
    p="$(_pg_expand_home "$1")"
    [ -n "$p" ] || return 1
    [ -d "$(_pg_realpath "$p" "$2")" ]
}

_pg_is_protected() { # <path> <cwd>
    local p base="$2" re
    p="$(_pg_expand_home "$1")"
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

_pg_redirect_targets() { # <segment>: unquoted > and >> targets into PG_REDIRS
    local s="$1" ch quote="" i=0 n="${#1}" cur="" in_word=0 want=0
    PG_REDIRS=()
    while [ "$i" -lt "$n" ]; do
        ch="${s:$i:1}"
        if [ "$ch" = "\\" ] && [ "$quote" != "'" ] && [ $((i + 1)) -lt "$n" ]; then
            [ "$want" -eq 1 ] && { in_word=1; cur="${cur}${s:$((i + 1)):1}"; }
            i=$((i + 2))
            continue
        elif [ "$ch" = "'" ] && [ "$quote" != '"' ]; then
            if [ "$quote" = "'" ]; then quote=""; else quote="'"; fi
            [ "$want" -eq 1 ] && in_word=1
        elif [ "$ch" = '"' ] && [ "$quote" != "'" ]; then
            if [ "$quote" = '"' ]; then quote=""; else quote='"'; fi
            [ "$want" -eq 1 ] && in_word=1
        elif [ -n "$quote" ]; then
            [ "$want" -eq 1 ] && cur="${cur}${ch}"
        elif [ "$ch" = ">" ]; then
            if [ "$want" -eq 1 ] && [ "$in_word" -eq 0 ]; then :; else
                [ "$in_word" -eq 1 ] && PG_REDIRS[${#PG_REDIRS[@]}]="$cur"
                cur=""; in_word=0; want=1
            fi
        elif [ "$ch" = " " ] || [ "$ch" = "	" ] || [ "$ch" = $'\r' ] || [ "$ch" = "<" ]; then
            if [ "$in_word" -eq 1 ]; then PG_REDIRS[${#PG_REDIRS[@]}]="$cur"; cur=""; in_word=0; want=0; fi
        elif [ "$want" -eq 1 ]; then
            in_word=1; cur="${cur}${ch}"
        fi
        i=$((i + 1))
    done
    [ "$in_word" -eq 1 ] && PG_REDIRS[${#PG_REDIRS[@]}]="$cur"
    return 0
}

_pg_bash_match() { # <command> <cwd>
    local cmd="$1" cwd0="$2" cwd="$2" seg i tok p idx base writes arg last src
    local args derived skip redir_re='^[0-9]*&?[<>]' redir_op_re='^[0-9]*&?[<>]+&?$'
    _deny_split_segments "$cmd"
    for seg in "${DENY_SEGMENTS[@]}"; do
        [ -n "$seg" ] || continue
        _deny_tokenize_segment "$seg"
        [ "${#DENY_TOKENS[@]}" -gt 0 ] || continue

        _pg_redirect_targets "$seg"
        for tok in ${PG_REDIRS[@]+"${PG_REDIRS[@]}"}; do
            tok="${tok#|}"
            if [ -n "$tok" ] && _pg_is_protected "$tok" "$cwd"; then
                PG_HIT="$tok"; return 0
            fi
        done

        _deny_command_start
        idx="$DENY_CMD_START"
        if [ "$(_deny_basename "${DENY_TOKENS[$idx]:-}")" = cd ] && [ "$DENY_WRAPPED" -eq 0 ]; then
            # Non-literal or missing target: fall back to the original cwd.
            i=$((idx + 1))
            while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
                case "${DENY_TOKENS[$i]}" in -) ;; --) i=$((i + 1)) ;; -*) i=$((i + 1)); continue ;; esac
                break
            done
            arg="${DENY_TOKENS[$i]:-}"
            case "$arg" in
                ''|-|*[\$\`\*\?\[]*) cwd="$cwd0" ;;
                *) cwd="$(_pg_realpath "$(_pg_expand_home "$arg")" "$cwd")" ;;
            esac
            continue
        fi
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
                skip=0
                while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
                    tok="${DENY_TOKENS[$i]}"
                    i=$((i + 1))
                    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
                    if [[ "$tok" =~ $redir_re ]]; then
                        [[ "$tok" =~ $redir_op_re ]] && skip=1
                        continue
                    fi
                    case "$tok" in
                        -r|--reference) [ "$base" = truncate ] && skip=1 ;;
                        -S|--suffix) { [ "$base" = cp ] || [ "$base" = mv ]; } && skip=1 ;;
                        -*) ;;
                        *) args[${#args[@]}]="$tok" ;;
                    esac
                done
                if { [ "$base" = cp ] || [ "$base" = mv ]; } && [ "${#args[@]}" -gt 1 ]; then
                    last="${args[$((${#args[@]} - 1))]}"
                    derived=()
                    if _pg_is_dir_dest "$last" "$cwd"; then
                        for src in "${args[@]:0:$((${#args[@]} - 1))}"; do
                            src="${src%/}"
                            [ -n "$src" ] && derived[${#derived[@]}]="${last%/}/${src##*/}"
                        done
                    fi
                    if [ "$base" = cp ]; then args=("$last"); fi
                    for src in ${derived[@]+"${derived[@]}"}; do args[${#args[@]}]="$src"; done
                elif [ "$base" = cp ] && [ "${#args[@]}" -gt 0 ]; then
                    args=("${args[$((${#args[@]} - 1))]}")
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

_pg_patch_match() { # <patch text> <cwd>
    local patch="$1" cwd="$2" line path first="" last="" n=0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%$'\r'}"
        [ -n "$first" ] || first="$line"
        last="$line"
        case "$line" in
            "*** Add File: "*) path="${line#\*\*\* Add File: }" ;;
            "*** Update File: "*) path="${line#\*\*\* Update File: }" ;;
            "*** Delete File: "*) path="${line#\*\*\* Delete File: }" ;;
            "*** Move to: "*) path="${line#\*\*\* Move to: }" ;;
            "*** Begin Patch"|"*** End Patch"|"*** End of File") continue ;;
            "*** "*) PG_UNPARSED=1; return 0 ;;
            *) continue ;;
        esac
        path="$(_deny_trim "$path")"
        if [ -z "$path" ]; then PG_UNPARSED=1; return 0; fi
        n=$((n + 1))
        if _pg_is_protected "$path" "$cwd"; then PG_HIT="$path"; return 0; fi
    done <<< "$patch"
    if [ "$first" != "*** Begin Patch" ] || [ "$last" != "*** End Patch" ] || [ "$n" -eq 0 ]; then
        PG_UNPARSED=1; return 0
    fi
    return 1
}

path_guard_match() {
    local input="$1" tool target cwd cmd
    PG_HIT=""; PG_UNPARSED=0
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
        apply_patch)
            cmd="$(printf '%s' "$input" | json_get_path tool_input command)"
            if _pg_patch_match "$cmd" "$cwd"; then
                if [ "$PG_UNPARSED" -eq 1 ]; then
                    printf '%s\n' "path-guard: cannot parse apply_patch targets; $_pg_route"
                else
                    printf '%s\n' "path-guard: $PG_HIT is protected; $_pg_route"
                fi
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
