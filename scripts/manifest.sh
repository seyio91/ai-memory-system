#!/usr/bin/env bash
# manifest.sh — read declarative per-harness manifests. A manifest is a flat
# `key = value` file (│ `#` comments, blank lines ignored), optionally followed
# by named sections. Values may use `~` and `$HOME`, expanded at read time.
# Manifests are DATA, not code — never sourced/executed — so a manifest can
# declare a harness without granting it shell in the installer. Sourced by
# install.sh, validate-manifest.sh, the archetype drivers, and executor.sh.
#
#   manifest_get <file> <key>   -> value (trimmed, ~/$HOME expanded), empty if absent
#   manifest_keys <file>        -> all declared keys, one per line
#   manifest_hooks <file>       -> [hooks] role/event lines, role<TAB>event[:matcher]

_mf_trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# _mf_expand <value> — expand a leading ~ and any $HOME occurrences.
_mf_expand() {
    local v="$1"
    # Quoted case pattern "~", not shell tilde expansion.
    # shellcheck disable=SC2088
    case "$v" in
        "~")   v="$HOME" ;;
        "~/"*) v="$HOME/${v#\~/}" ;;
    esac
    printf '%s' "${v//\$HOME/$HOME}"
}

# Emit "key<TAB>value" for every top-level declared line (comments/blanks
# stripped, trimmed). Keys inside named sections are intentionally hidden from
# the flat-reader API.
_mf_pairs() {
    local file="$1" line t k v section
    section=""
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"                 # strip trailing/whole-line comment
        t="$(printf '%s' "$line" | _mf_trim)"
        case "$t" in
            \[*\])
                section="${t#\[}"
                section="${section%\]}"
                section="$(printf '%s' "$section" | _mf_trim)"
                continue
                ;;
        esac
        [ -z "$section" ] || continue
        case "$line" in *=*) ;; *) continue ;; esac
        k="$(printf '%s' "${line%%=*}" | _mf_trim)"
        v="$(printf '%s' "${line#*=}" | _mf_trim)"
        [ -n "$k" ] || continue
        printf '%s\t%s\n' "$k" "$v"
    done < "$file"
}

manifest_get() {
    local file="$1" key="$2" k v pairs
    # Buffer all pairs first, THEN search. Reading from a live `< <(_mf_pairs …)`
    # and `return`-ing on the first match closes the pipe while _mf_pairs is still
    # writing, so its printf takes SIGPIPE ("write error: Broken pipe"). A here-doc
    # over a captured string has no live writer to kill.
    pairs="$(_mf_pairs "$file")"
    while IFS=$'\t' read -r k v; do
        if [ "$k" = "$key" ]; then _mf_expand "$v"; return 0; fi
    done <<EOF
$pairs
EOF
    return 0
}

manifest_keys() {
    local k v
    while IFS=$'\t' read -r k v; do printf '%s\n' "$k"; done < <(_mf_pairs "$1")
}

manifest_hooks() {
    local file="$1" line t k v section
    section=""
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"                 # strip trailing/whole-line comment
        t="$(printf '%s' "$line" | _mf_trim)"
        case "$t" in
            \[*\])
                section="${t#\[}"
                section="${section%\]}"
                section="$(printf '%s' "$section" | _mf_trim)"
                continue
                ;;
        esac
        [ "$section" = hooks ] || continue
        case "$line" in *=*) ;; *) continue ;; esac
        k="$(printf '%s' "${line%%=*}" | _mf_trim)"
        v="$(printf '%s' "${line#*=}" | _mf_trim)"
        [ -n "$k" ] || continue
        printf '%s\t%s\n' "$k" "$v"
    done < "$file"
}
