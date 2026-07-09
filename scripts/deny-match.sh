#!/usr/bin/env bash
# deny-match.sh — match executor command lines against additive deny-list specs.
# Sourceable and runnable. Public API:
#   deny_match "<cmdline>" <specfile> [<specfile>...]
# Exit 0 means denied and prints a one-line reason; exit 1 means allowed.

_deny_trim() {
    local s="$1"
    while [ "${s# }" != "$s" ] || [ "${s#	}" != "$s" ] || [ "${s#}" != "$s" ]; do
        s="${s# }"; s="${s#	}"; s="${s#}"
    done
    while [ "${s% }" != "$s" ] || [ "${s%	}" != "$s" ] || [ "${s%}" != "$s" ]; do
        s="${s% }"; s="${s%	}"; s="${s%}"
    done
    printf '%s' "$s"
}

_deny_basename() {
    local s="$1"
    printf '%s' "${s##*/}"
}

_deny_is_assignment() {
    local s="$1" name i ch
    case "$s" in
        *=*) ;;
        *) return 1 ;;
    esac
    name="${s%%=*}"
    [ -n "$name" ] || return 1
    case "${name:0:1}" in
        [A-Za-z_]) ;;
        *) return 1 ;;
    esac
    i=1
    while [ "$i" -lt "${#name}" ]; do
        ch="${name:$i:1}"
        case "$ch" in
            [A-Za-z0-9_]) ;;
            *) return 1 ;;
        esac
        i=$((i + 1))
    done
    return 0
}

# Transparent exec-wrappers: they run their argument. An honest agent adds these
# around a long infra command (`timeout 5 terraform apply`, `flock /tmp/l terraform
# apply`), so they are not obfuscation — omitting one is a hole, not a nicety.
# Any wrapper sets DENY_WRAPPED, which makes the caller scan the tail for the
# binary rather than trusting the head (a wrapper's own flag value can sit there).
_deny_is_wrapper() {
    case "$(_deny_basename "$1")" in
        sudo|doas|env|command|exec|nohup|time|timeout|nice|ionice|chrt| \
        setsid|flock|stdbuf|unbuffer|script|watch|xargs|parallel|busybox) return 0 ;;
        *) return 1 ;;
    esac
}

# Binaries whose `-c <payload>` argument IS the command they run. `su`/`runuser`
# belong here, not merely in the wrapper list: `su - deploy -c "terraform apply"`
# is their only real idiom, and treating them as plain wrappers leaves the payload
# an opaque token — coverage in name only.
_deny_takes_c_payload() {
    case "$(_deny_basename "$1")" in
        sh|bash|zsh|su|runuser) return 0 ;;
        *) return 1 ;;
    esac
}

# Real on-disk binaries that a WRAPPER can exec and that re-enter the shell. This is
# the set to hunt for in a wrapper's tail (`timeout 5 sh -c "…"`, `sudo -u root sh -c
# "…"`), because after a wrapper the command head is unreliable — a flag's value can
# sit there. Deliberately EXCLUDES `eval`/`trap`: they are shell builtins with no
# executable on disk, so a wrapper cannot run them (`nice eval …` → No such file), and
# treating `timeout 5 eval "terraform apply"` as a denial would be a false positive.
_deny_wrapper_reachable_payload() {
    case "$(_deny_basename "$1")" in
        sh|bash|zsh|su|runuser|find) return 0 ;;
        *) return 1 ;;
    esac
}

# Wrappers that ALSO carry their own `-c`/`--command` shell-command flag:
# `flock <lock> -c "terraform apply"` is exactly `flock <lock> sh -c "…"`, and
# `script -c "…"` likewise. They are already in the wrapper list (for their trailing
# `flock <lock> terraform apply` form), but their `-c` payload needs extracting too.
# Scoped to these two so we do not extract a `-c` that some unrelated binary defines
# as a non-shell flag (which would be a false positive).
_deny_wrapper_has_command_flag() {
    case "$(_deny_basename "$1")" in
        flock|script) return 0 ;;
        *) return 1 ;;
    esac
}

# Leading tokens that are shell syntax, not a command: subshells, brace groups,
# and compound-statement keywords. `if true; then terraform apply; fi` splits on
# `;` into a segment whose head is `then`.
_deny_is_structural() {
    case "$1" in
        '('|')'|'{'|'}'|'!'|then|do|else|elif|fi|done|in) return 0 ;;
        *) return 1 ;;
    esac
}

_deny_is_shell() {
    case "$(_deny_basename "$1")" in
        sh|bash|zsh) return 0 ;;
        *) return 1 ;;
    esac
}

# Binaries whose plain arguments are shell code: `eval terraform apply`,
# `trap "terraform apply" EXIT`.
_deny_is_eval() {
    case "$(_deny_basename "$1")" in
        eval|trap) return 0 ;;
        *) return 1 ;;
    esac
}

# Re-quote a token so that re-tokenizing a joined payload preserves argument
# boundaries. Joining with bare spaces flattens `sh -c "terraform -chdir=. apply"`
# into `sh -c terraform -chdir=. apply`, losing the -c boundary — the payload then
# looks like a bare `terraform` with a stray flag, and the deny is missed.
_deny_quote_token() {
    local s="$1" out="" ch i=0
    while [ "$i" -lt "${#s}" ]; do
        ch="${s:$i:1}"
        if [ "$ch" = "'" ]; then out="${out}'\\''"; else out="${out}${ch}"; fi
        i=$((i + 1))
    done
    printf "'%s'" "$out"
}

_deny_ere_escape() {
    local s="$1" out="" ch i
    i=0
    while [ "$i" -lt "${#s}" ]; do
        ch="${s:$i:1}"
        # Literal backslash in the case pattern.
        # shellcheck disable=SC1003
        case "$ch" in
            '\'|'.'|'['|']'|'^'|'$'|'*'|'+'|'?'|'('|')'|'{'|'}'|'|')
                out="${out}\\${ch}"
                ;;
            *) out="${out}${ch}" ;;
        esac
        i=$((i + 1))
    done
    printf '%s' "$out"
}

_deny_split_segments() {
    local s="$1" cur="" ch next quote="" i=0
    DENY_SEGMENTS=()
    while [ "$i" -lt "${#s}" ]; do
        ch="${s:$i:1}"
        next=""
        [ $((i + 1)) -lt "${#s}" ] && next="${s:$((i + 1)):1}"
        if [ "$ch" = "\\" ] && [ "$quote" != "'" ]; then
            cur="${cur}${ch}"
            if [ -n "$next" ]; then
                cur="${cur}${next}"
                i=$((i + 2))
                continue
            fi
        elif [ "$ch" = "'" ] && [ "$quote" != '"' ]; then
            if [ "$quote" = "'" ]; then quote=""; else quote="'"; fi
            cur="${cur}${ch}"
        elif [ "$ch" = '"' ] && [ "$quote" != "'" ]; then
            if [ "$quote" = '"' ]; then quote=""; else quote='"'; fi
            cur="${cur}${ch}"
        elif [ -z "$quote" ]; then
            # A LONE `&` backgrounds the left side and runs the right one:
            # `sleep 1 & terraform apply` executes terraform. It is a separator,
            # not a character. Same for the `&` in `|&`.
            if [ "$ch" = $'\n' ] || [ "$ch" = ";" ] || [ "$ch" = "|" ] || [ "$ch" = "&" ] \
               || [ "$ch" = "(" ] || [ "$ch" = ")" ] || [ "$ch" = "{" ] || [ "$ch" = "}" ]; then
                DENY_SEGMENTS[${#DENY_SEGMENTS[@]}]="$(_deny_trim "$cur")"
                cur=""
                if { [ "$ch" = "|" ] && [ "$next" = "|" ]; } || { [ "$ch" = "&" ] && [ "$next" = "&" ]; }; then
                    i=$((i + 1))
                fi
            else
                cur="${cur}${ch}"
            fi
        else
            cur="${cur}${ch}"
        fi
        i=$((i + 1))
    done
    DENY_SEGMENTS[${#DENY_SEGMENTS[@]}]="$(_deny_trim "$cur")"
}

_deny_tokenize_segment() {
    local s="$1" cur="" ch next quote="" i=0
    DENY_TOKENS=()
    while [ "$i" -lt "${#s}" ]; do
        ch="${s:$i:1}"
        next=""
        [ $((i + 1)) -lt "${#s}" ] && next="${s:$((i + 1)):1}"
        if [ "$ch" = "\\" ] && [ "$quote" != "'" ]; then
            if [ -n "$next" ]; then
                cur="${cur}${next}"
                i=$((i + 2))
                continue
            fi
            cur="${cur}${ch}"
        elif [ "$ch" = "'" ] && [ "$quote" != '"' ]; then
            if [ "$quote" = "'" ]; then quote=""; else quote="'"; fi
        elif [ "$ch" = '"' ] && [ "$quote" != "'" ]; then
            if [ "$quote" = '"' ]; then quote=""; else quote='"'; fi
        elif [ -z "$quote" ] && { [ "$ch" = " " ] || [ "$ch" = "	" ] || [ "$ch" = $'\r' ]; }; then
            if [ -n "$cur" ]; then
                DENY_TOKENS[${#DENY_TOKENS[@]}]="$cur"
                cur=""
            fi
        else
            cur="${cur}${ch}"
        fi
        i=$((i + 1))
    done
    [ -n "$cur" ] && DENY_TOKENS[${#DENY_TOKENS[@]}]="$cur"
}

_deny_command_start() {
    local i=0 changed wrapper
    DENY_CMD_START=0
    DENY_WRAPPED=0
    while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
        changed=0
        if _deny_is_structural "${DENY_TOKENS[$i]}"; then
            i=$((i + 1))
            changed=1
        elif _deny_is_assignment "${DENY_TOKENS[$i]}"; then
            i=$((i + 1))
            changed=1
        elif _deny_is_wrapper "${DENY_TOKENS[$i]}"; then
            wrapper="$(_deny_basename "${DENY_TOKENS[$i]}")"
            i=$((i + 1))
            # A wrapper flag may take a separate value (`sudo -u root cmd`), and we
            # cannot know which flags do without a table per wrapper. So we skip
            # flags, stop at the first bare word, and mark the segment WRAPPED —
            # the caller then scans for the binary instead of trusting this index.
            case "$wrapper" in
                sudo|env|time)
                    DENY_WRAPPED=1
                    while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
                        case "${DENY_TOKENS[$i]}" in
                            --) i=$((i + 1)); break ;;
                            -*) i=$((i + 1)) ;;
                            *) break ;;
                        esac
                    done
                    ;;
                *) DENY_WRAPPED=1 ;;
            esac
            changed=1
        fi
        [ "$changed" -eq 1 ] || break
    done
    DENY_CMD_START="$i"
    return 0
}

_deny_filtered_args() {
    local i="$1"
    DENY_FILTERED=()
    i=$((i + 1))
    while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
        case "${DENY_TOKENS[$i]}" in
            -*) ;;
            *) DENY_FILTERED[${#DENY_FILTERED[@]}]="${DENY_TOKENS[$i]}" ;;
        esac
        i=$((i + 1))
    done
}

_deny_spec_run_in_filtered() {
    local start j
    [ "${#DENY_SPEC_WORDS[@]}" -gt 0 ] || return 1
    [ "${#DENY_FILTERED[@]}" -ge "${#DENY_SPEC_WORDS[@]}" ] || return 1
    start=0
    while [ "$start" -le $((${#DENY_FILTERED[@]} - ${#DENY_SPEC_WORDS[@]})) ]; do
        j=0
        while [ "$j" -lt "${#DENY_SPEC_WORDS[@]}" ]; do
            [ "${DENY_FILTERED[$((start + j))]}" = "${DENY_SPEC_WORDS[$j]}" ] || break
            j=$((j + 1))
        done
        [ "$j" -eq "${#DENY_SPEC_WORDS[@]}" ] && return 0
        start=$((start + 1))
    done
    return 1
}

_deny_adjacency_match() {
    local segment="$1" binary="$2" regex word
    regex="$(_deny_ere_escape "$binary")"
    for word in "${DENY_SPEC_WORDS[@]}"; do
        regex="${regex}[[:space:]]+$(_deny_ere_escape "$word")"
    done
    printf '%s' "$segment" | grep -Eq "$regex"
}

# Shell -c payloads. `-c` may be bundled with other short flags (`bash -lc "…"`,
# `bash -xc "…"`) or glued to its argument (`sh -c"…"` tokenizes to `-cterraform apply`).
# Recognising only the bare `-c` token lets every bundled form through.
_deny_shell_payloads() {
    local i tok
    DENY_PAYLOADS=()
    i=1
    while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
        tok="${DENY_TOKENS[$i]}"
        case "$tok" in
            -c|--command)
                [ $((i + 1)) -lt "${#DENY_TOKENS[@]}" ] && DENY_PAYLOADS[${#DENY_PAYLOADS[@]}]="${DENY_TOKENS[$((i + 1))]}"
                ;;
            --command=*)
                DENY_PAYLOADS[${#DENY_PAYLOADS[@]}]="${tok#--command=}"
                ;;
            -*c)
                # bundled short flags ending in c: -lc, -xc, -ic …
                [ $((i + 1)) -lt "${#DENY_TOKENS[@]}" ] && DENY_PAYLOADS[${#DENY_PAYLOADS[@]}]="${DENY_TOKENS[$((i + 1))]}"
                ;;
            -c*)
                # glued: -c<payload>
                DENY_PAYLOADS[${#DENY_PAYLOADS[@]}]="${tok#-c}"
                ;;
            -*c*)
                # bundled with the payload glued after a c: -lc<payload>
                DENY_PAYLOADS[${#DENY_PAYLOADS[@]}]="${tok#*c}"
                ;;
            '<<<')
                # herestring: bash <<< "terraform apply" — the shell executes it
                [ $((i + 1)) -lt "${#DENY_TOKENS[@]}" ] && DENY_PAYLOADS[${#DENY_PAYLOADS[@]}]="${DENY_TOKENS[$((i + 1))]}"
                ;;
            '<<<'*)
                DENY_PAYLOADS[${#DENY_PAYLOADS[@]}]="${tok#<<<}"
                ;;
        esac
        i=$((i + 1))
    done
}

# `find` executes ONLY what follows -exec/-execdir/-ok, up to `;` or `+`. Treating the
# whole command as a wrapper would deny `find . -name terraform -o -name apply`, which
# executes nothing — and a deny-list that blocks legitimate work gets switched off.
_deny_find_payloads() {
    local i tok joined=""
    DENY_PAYLOADS=()
    i=0
    while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
        case "${DENY_TOKENS[$i]}" in
            -exec|-execdir|-ok|-okdir)
                i=$((i + 1))
                joined=""
                while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
                    tok="$(_deny_quote_token "${DENY_TOKENS[$i]}")"
                    case "${DENY_TOKENS[$i]}" in
                        ';'|'+') break ;;
                    esac
                    if [ -n "$joined" ]; then joined="$joined $tok"; else joined="$tok"; fi
                    i=$((i + 1))
                done
                [ -n "$joined" ] && DENY_PAYLOADS[${#DENY_PAYLOADS[@]}]="$joined"
                ;;
        esac
        i=$((i + 1))
    done
}

# `eval "terraform apply"` re-enters the shell just as `sh -c` does. Its payload is
# every non-flag argument, joined — `eval terraform apply` is as real as the quoted form.
#
# Joined RAW, deliberately: `eval` concatenates its arguments and re-parses the result,
# so quoting is flattened by the shell itself. (`eval sh -c "terraform -chdir=x apply"`
# becomes `sh -c terraform -chdir=x apply`, which runs bare `terraform` — no `apply`.)
# Re-quoting here would model a shell that does not exist, and would break
# `trap "terraform apply" EXIT`. Contrast `find -exec`, which execve's an argv and
# therefore DOES preserve argument boundaries.
_deny_eval_payloads() {
    local i tok joined=""
    DENY_PAYLOADS=()
    i=$((DENY_CMD_START + 1))
    while [ "$i" -lt "${#DENY_TOKENS[@]}" ]; do
        tok="${DENY_TOKENS[$i]}"
        case "$tok" in
            -*) ;;
            *) if [ -n "$joined" ]; then joined="$joined $tok"; else joined="$tok"; fi ;;
        esac
        i=$((i + 1))
    done
    [ -n "$joined" ] && DENY_PAYLOADS[0]="$joined"
}

# Substitutions the tokenizer sees as one opaque word, whose bodies are separate
# commands: $(…), `…`, and process substitution <(…) / >(…).
_deny_substitutions() {
    local s="$1" i=0 ch next depth body sq="" dq=""
    DENY_SUBS=()
    while [ "$i" -lt "${#s}" ]; do
        ch="${s:$i:1}"
        # Quote state must model the shell exactly, and must track BOTH quotes.
        # Single quotes suppress substitution (`echo '$(terraform apply)'` prints it).
        # Double quotes do NOT (`echo "$(terraform apply)"` runs it) — and inside them
        # an apostrophe is a literal, not a quote. Tracking only `'` meant `echo "it's
        # $(terraform apply)"` opened a phantom single-quote region and the live
        # substitution was skipped. A contraction is not an exploit; it must not read
        # like one.
        if [ "$ch" = "\\" ] && [ -z "$sq" ]; then
            i=$((i + 2))
            continue
        fi
        if [ -n "$sq" ]; then
            [ "$ch" = "'" ] && sq=""
            i=$((i + 1))
            continue
        fi
        # ANSI-C quoting: in $'…' a backslash ESCAPES, so `$'a\'b'` contains a literal
        # apostrophe and the string ends at the final quote. Treating that `\'` as a
        # terminator inverts quote parity and hides whatever follows.
        if [ "$ch" = "\$" ] && [ -z "$dq" ] && [ "${s:$((i + 1)):1}" = "'" ]; then
            i=$((i + 2))
            while [ "$i" -lt "${#s}" ]; do
                ch="${s:$i:1}"
                if [ "$ch" = "\\" ]; then i=$((i + 2)); continue; fi
                if [ "$ch" = "'" ]; then i=$((i + 1)); break; fi
                i=$((i + 1))
            done
            continue
        fi
        if [ "$ch" = "'" ] && [ -z "$dq" ]; then
            sq="'"
            i=$((i + 1))
            continue
        fi
        if [ "$ch" = '"' ]; then
            if [ -n "$dq" ]; then dq=""; else dq='"'; fi
            i=$((i + 1))
            continue
        fi
        next=""
        [ $((i + 1)) -lt "${#s}" ] && next="${s:$((i + 1)):1}"
        if { [ "$ch" = "\$" ] || [ "$ch" = "<" ] || [ "$ch" = ">" ]; } && [ "$next" = "(" ]; then
            depth=1
            i=$((i + 2))
            body=""
            while [ "$i" -lt "${#s}" ] && [ "$depth" -gt 0 ]; do
                ch="${s:$i:1}"
                if [ "$ch" = "(" ]; then depth=$((depth + 1))
                elif [ "$ch" = ")" ]; then depth=$((depth - 1)); [ "$depth" -eq 0 ] && break
                fi
                body="${body}${ch}"
                i=$((i + 1))
            done
            [ -n "$body" ] && DENY_SUBS[${#DENY_SUBS[@]}]="$body"
        elif [ "$ch" = '`' ]; then
            i=$((i + 1))
            body=""
            while [ "$i" -lt "${#s}" ]; do
                ch="${s:$i:1}"
                [ "$ch" = '`' ] && break
                body="${body}${ch}"
                i=$((i + 1))
            done
            [ -n "$body" ] && DENY_SUBS[${#DENY_SUBS[@]}]="$body"
        fi
        i=$((i + 1))
    done
}

_deny_load_specs() {
    local file line binary rest word
    DENY_SPECS=()
    for file in "$@"; do
        [ -f "$file" ] || continue
        while IFS= read -r line || [ -n "$line" ]; do
            line="$(_deny_trim "$line")"
            case "$line" in ''|'#'*) continue ;; esac
            binary="${line%%[ 	]*}"
            rest="${line#"$binary"}"
            rest="$(_deny_trim "$rest")"
            [ -n "$binary" ] && [ -n "$rest" ] || continue
            DENY_SPECS[${#DENY_SPECS[@]}]="$binary $rest"
        done < "$file"
    done
}

_deny_match_loaded() {
    local cmdline="$1" depth="$2" segment idx primary spec spec_binary spec_rest payload sub p
    [ "$depth" -le 8 ] || { printf '%s\n' "executor deny-list: shell recursion depth exceeded"; return 0; }

    # $(…) / `…` bodies are separate commands. Check them before anything else.
    _deny_substitutions "$cmdline"
    for sub in ${DENY_SUBS[@]+"${DENY_SUBS[@]}"}; do
        if _deny_match_loaded "$sub" $((depth + 1)); then return 0; fi
    done

    _deny_split_segments "$cmdline"
    for segment in "${DENY_SEGMENTS[@]}"; do
        [ -n "$segment" ] || continue
        _deny_tokenize_segment "$segment"
        [ "${#DENY_TOKENS[@]}" -gt 0 ] || continue
        _deny_command_start
        idx="$DENY_CMD_START"
        [ "$idx" -lt "${#DENY_TOKENS[@]}" ] || continue
        primary="$(_deny_basename "${DENY_TOKENS[$idx]}")"

        # Collect payloads BEFORE recursing: recursion overwrites the global
        # DENY_TOKENS/DENY_CMD_START/DENY_WRAPPED that the spec loop below reads.
        # And run the spec loop FIRST, so it never reads a clobbered token list.
        # After a wrapper, `idx` may sit on the wrapper's flag *value* (`timeout 5 …`,
        # `sudo -u root …`), so `primary` is not the real command. Find the actual
        # payload-bearing binary by scanning the tail for a wrapper-reachable one.
        # Without this, `timeout 5 sh -c "terraform apply"` extracts no payload.
        if [ "$DENY_WRAPPED" -eq 1 ] && ! _deny_takes_c_payload "$primary" \
           && [ "$primary" != "find" ]; then
            p="$idx"
            while [ "$p" -lt "${#DENY_TOKENS[@]}" ]; do
                if _deny_wrapper_reachable_payload "${DENY_TOKENS[$p]}"; then
                    primary="$(_deny_basename "${DENY_TOKENS[$p]}")"
                    break
                fi
                p=$((p + 1))
            done
        fi

        DENY_SEG_PAYLOADS=()
        if _deny_takes_c_payload "$primary"; then
            _deny_shell_payloads
            DENY_SEG_PAYLOADS=(${DENY_PAYLOADS[@]+"${DENY_PAYLOADS[@]}"})
        elif _deny_is_eval "$primary"; then
            _deny_eval_payloads
            DENY_SEG_PAYLOADS=(${DENY_PAYLOADS[@]+"${DENY_PAYLOADS[@]}"})
        elif [ "$primary" = "find" ]; then
            _deny_find_payloads
            DENY_SEG_PAYLOADS=(${DENY_PAYLOADS[@]+"${DENY_PAYLOADS[@]}"})
        fi

        # A skipped wrapper may carry its own `-c` shell-command (`flock <lock> -c
        # "terraform apply"`). Scan the consumed prefix [0, idx) for flock/script and,
        # if present, extract its -c payload too.
        p=0
        while [ "$p" -lt "$idx" ]; do
            if _deny_wrapper_has_command_flag "${DENY_TOKENS[$p]}"; then
                _deny_shell_payloads
                DENY_SEG_PAYLOADS=(${DENY_SEG_PAYLOADS[@]+"${DENY_SEG_PAYLOADS[@]}"} ${DENY_PAYLOADS[@]+"${DENY_PAYLOADS[@]}"})
                break
            fi
            p=$((p + 1))
        done

        for spec in "${DENY_SPECS[@]}"; do
            spec_binary="${spec%% *}"
            spec_rest="${spec#* }"
            DENY_SPEC_WORDS=()
            for word in $spec_rest; do DENY_SPEC_WORDS[${#DENY_SPEC_WORDS[@]}]="$word"; done
            # Candidate binary positions. Normally only the command head. After a
            # wrapper (`sudo -u root kubectl …`) the head is unreliable — a flag's
            # value can sit there — so scan the tail for the spec's binary instead.
            p="$idx"
            while [ "$p" -lt "${#DENY_TOKENS[@]}" ]; do
                if [ "$(_deny_basename "${DENY_TOKENS[$p]}")" = "$spec_binary" ]; then
                    _deny_filtered_args "$p"
                    if _deny_spec_run_in_filtered; then
                        printf '%s\n' "executor deny-list: $spec matched command segment '$segment'"
                        return 0
                    fi
                    if _deny_adjacency_match "$segment" "$spec_binary"; then
                        printf '%s\n' "executor deny-list: $spec matched command segment '$segment'"
                        return 0
                    fi
                fi
                [ "$DENY_WRAPPED" -eq 1 ] || break
                p=$((p + 1))
            done
        done

        # Only now recurse into payloads — from here the globals may be clobbered,
        # and we are done with this segment's tokens.
        for payload in ${DENY_SEG_PAYLOADS[@]+"${DENY_SEG_PAYLOADS[@]}"}; do
            if _deny_match_loaded "$payload" $((depth + 1)); then return 0; fi
        done
    done
    return 1
}

deny_match() {
    local cmdline="$1"
    shift
    _deny_load_specs "$@"
    [ "${#DENY_SPECS[@]}" -gt 0 ] || return 1
    _deny_match_loaded "$cmdline" 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    if [ "$#" -lt 2 ]; then
        printf '%s\n' "usage: deny-match.sh <cmdline> <specfile> [<specfile>...]" >&2
        exit 2
    fi
    deny_match "$@"
    exit $?
fi
