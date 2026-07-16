#!/usr/bin/env bash
# validate-manifest.sh — static check of harness delivery manifests.
#
#   validate-manifest.sh            # validate every harnesses/*/manifest
#   validate-manifest.sh <file>     # validate one manifest
#
# Emits WARN:/ERROR: lines. Exit 0 = clean, 1 = at least one ERROR, 2 = setup error.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/manifest.sh"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ERRORS=0
err()  { printf 'ERROR: %s\n' "$1"; ERRORS=$((ERRORS + 1)); }
warn() { printf 'WARN:  %s\n' "$1"; }

KNOWN_KEYS=" name archetype format hooks_dir hooks_json settings_json hook_script guard_script session_script block_script arm_script hooks_min_version session_chunks inject_chunks statusline statusline_settings statusline_script commands commands_dir commands_doc skills_dir agents_dir context_target refresh exec exec_cmd exec_model_flag exec_readonly exec_last_message exec_probe "

in_set() { case "$2" in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

validate_one() {
    local mf="$1" label="$2" v
    [ -f "$mf" ] || { err "$label: manifest not found ($mf)"; return; }

    # name must match the harness dir name
    local dirname; dirname="$(basename "$(dirname "$mf")")"
    v="$(manifest_get "$mf" name)"
    [ -n "$v" ] || err "$label: missing required key 'name'"
    [ -z "$v" ] || [ "$v" = "$dirname" ] || err "$label: name='$v' does not match dir '$dirname'"

    # archetype + format enums
    local arch; arch="$(manifest_get "$mf" archetype)"
    in_set "$arch" " hook file " || err "$label: archetype must be hook|file (got '${arch:-<empty>}')"
    local fmt; fmt="$(manifest_get "$mf" format)"
    in_set "$fmt" " xml md " || err "$label: format must be xml|md (got '${fmt:-<empty>}')"

    # archetype-specific required keys
    case "$arch" in
        hook)
            [ -n "$(manifest_get "$mf" hooks_dir)" ] || [ -n "$(manifest_get "$mf" hooks_json)" ] \
                || err "$label: hook archetype requires 'hooks_dir' or 'hooks_json'"
            [ -z "$(manifest_get "$mf" hooks_json)" ] || [ -n "$(manifest_get "$mf" hook_script)" ] \
                || err "$label: hooks_json requires 'hook_script'"
            [ -z "$(manifest_get "$mf" statusline_settings)" ] || [ -n "$(manifest_get "$mf" statusline_script)" ] \
                || err "$label: statusline_settings requires 'statusline_script'"
            ;;
        file)
            [ -n "$(manifest_get "$mf" context_target)" ] || err "$label: file archetype requires 'context_target'"
            [ -z "$(manifest_get "$mf" hooks_json)" ] || [ -n "$(manifest_get "$mf" hook_script)" ] \
                || err "$label: hooks_json requires 'hook_script'"
            local rf; rf="$(manifest_get "$mf" refresh)"
            in_set "$rf" " launch hook " || err "$label: file archetype 'refresh' must be launch|hook (got '${rf:-<empty>}')"
            ;;
    esac

    # commands surface enum + native needs a target dir
    local cmds; cmds="$(manifest_get "$mf" commands)"
    if [ -n "$cmds" ]; then
        in_set "$cmds" " native skill doc none " || err "$label: commands must be native|skill|doc|none (got '$cmds')"
        [ "$cmds" != native ] || [ -n "$(manifest_get "$mf" commands_dir)" ] || err "$label: commands=native requires 'commands_dir'"
    fi

    # execute face: 'exec = subagent' sentinel, OR exec_cmd (+ optional model/readonly)
    local ex exc; ex="$(manifest_get "$mf" exec)"; exc="$(manifest_get "$mf" exec_cmd)"
    if [ -n "$ex" ] && [ "$ex" != subagent ]; then
        err "$label: 'exec' may only be the sentinel 'subagent' (use exec_cmd for a headless command)"
    fi
    if [ -n "$(manifest_get "$mf" exec_readonly)" ] && [ -z "$exc" ] && [ -z "$ex" ]; then
        warn "$label: exec_readonly set without exec_cmd/exec — the execute face is incomplete"
    fi

    # unknown-key typo catch
    local k
    while IFS= read -r k; do
        [ -n "$k" ] || continue
        in_set "$k" "$KNOWN_KEYS" || warn "$label: unknown key '$k'"
    done < <(manifest_keys "$mf")
}

if [ "$#" -ge 1 ]; then
    validate_one "$1" "$(basename "$(dirname "$1")")"
else
    found=0
    for mf in "$REPO_ROOT"/harnesses/*/manifest; do
        [ -f "$mf" ] || continue
        found=1
        validate_one "$mf" "$(basename "$(dirname "$mf")")"
    done
    [ "$found" = 1 ] || { echo "validate-manifest: no harnesses/*/manifest found" >&2; exit 2; }
fi

[ "$ERRORS" -eq 0 ]
