#!/usr/bin/env bash
#
# list-skills.sh — unified, provenance-tagged view of every installed skill.
#
# Nothing new to maintain: provenance is DERIVED from where each skill sits —
#   skills/<name>/        -> authored (gitignored, per-instance)
#   .skill-cache/<name>/  -> remote referenced (declared in root skills.toml;
#                            commit pin from skills.lock)
# so this is the single answer to "how do I list my skills." One row per skill.
#
# Columns: SKILL  SOURCE(authored|remote)  SYNCED(yes|no)  PIN
#
# Usage: list-skills.sh [--remote]
#   --remote  only remote (referenced) skills
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

ONLY_REMOTE=0
for arg in "$@"; do
    case "$arg" in
        --remote) ONLY_REMOTE=1 ;;
        -h|--help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'list-skills: unknown arg: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

CACHE="$(skill_cache_dir)"
LOCK="$CACHE/skills.lock"
AUTH_ROOT="$MEMORY_DIR/skills"

# _declared_names <manifest> — names declared in a TOML manifest (empty if none).
_declared_names() {
    [ -f "$1" ] || return 0
    command -v python3 >/dev/null 2>&1 || return 0
    python3 - "$1" <<'PY'
import sys, os
try:
    import tomllib
except ModuleNotFoundError:
    sys.exit(0)
try:
    with open(sys.argv[1], "rb") as f:
        data = tomllib.load(f)
except Exception:
    sys.exit(0)
for s in (data.get("skills") or []):
    n = s.get("name")
    if n:
        print(n)
PY
}

REMOTE_NAMES="$(_declared_names "$(skill_manifest)")"

has_name() { printf '%s\n' "$1" | grep -qxF "$2"; }
lock_pin() { [ -f "$LOCK" ] || return 0; awk -F '\t' -v n="$1" '/^#/{next} $1==n{print substr($2,1,10); exit}' "$LOCK"; }

emit_rows() {
    local d name source synced pin
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        name="$(basename "$d")"
        case "$d" in
            "$CACHE"/*)
                source=remote; pin="$(lock_pin "$name")"; [ -n "$pin" ] || pin='-'
                if has_name "$REMOTE_NAMES" "$name" || [ "$pin" != "-" ]; then synced=yes
                else synced='?'; fi ;;   # in the cache but no manifest declares it
            "$AUTH_ROOT"/*) source=authored; synced=no; pin='-' ;;
            *)              source='?'; synced='?'; pin='-' ;;
        esac
        [ "$ONLY_REMOTE" = 1 ] && [ "$source" != remote ] && continue
        printf '%-30s %-9s %-7s %s\n' "$name" "$source" "$synced" "$pin"
    done < <(list_skill_dirs)
}

printf '%-30s %-9s %-7s %s\n' SKILL SOURCE SYNCED PIN
emit_rows | sort
