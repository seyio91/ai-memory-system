#!/usr/bin/env bash
# manifest.sh — read declarative per-harness manifests. A manifest is a flat
# `key = value` file (│ `#` comments, blank lines ignored). Values may use `~`
# and `$HOME`, expanded at read time. Manifests are DATA, not code — never
# sourced/executed — so a manifest can declare a harness without granting it
# shell in the installer. Sourced by install.sh, validate-manifest.sh, the
# archetype drivers, and (later) executor.sh.
#
#   manifest_get <file> <key>   -> value (trimmed, ~/$HOME expanded), empty if absent
#   manifest_keys <file>        -> all declared keys, one per line

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

# Emit "key<TAB>value" for every declared line (comments/blanks stripped, trimmed).
_mf_pairs() {
    local file="$1" line k v
    [ -f "$file" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        line="${line%%#*}"                 # strip trailing/whole-line comment
        case "$line" in *=*) ;; *) continue ;; esac
        k="$(printf '%s' "${line%%=*}" | _mf_trim)"
        v="$(printf '%s' "${line#*=}" | _mf_trim)"
        [ -n "$k" ] || continue
        printf '%s\t%s\n' "$k" "$v"
    done < "$file"
}

manifest_get() {
    local file="$1" key="$2" k v
    while IFS=$'\t' read -r k v; do
        if [ "$k" = "$key" ]; then _mf_expand "$v"; return 0; fi
    done < <(_mf_pairs "$file")
    return 0
}

manifest_keys() {
    local k v
    while IFS=$'\t' read -r k v; do printf '%s\n' "$k"; done < <(_mf_pairs "$1")
}
