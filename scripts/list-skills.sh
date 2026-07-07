#!/usr/bin/env bash
#
# list-skills.sh — unified, provenance-tagged view of every installed skill.
#
# Nothing new to maintain: provenance is DERIVED from where each skill sits —
#   skills/<name>/        -> generic authored (tracked, synced)
#   skills-local/<name>/  -> local   authored (gitignored, per-instance)
#   .skill-cache/<name>/  -> remote referenced (scope from the manifest that declared
#                            it; commit pin from skills.lock)
# so this is the single answer to "how do I list my skills." One row per skill.
#
# Columns: SKILL  SCOPE(generic|local)  SOURCE(authored|remote)  SYNCED(yes|no)  PIN
#
# Usage: list-skills.sh [--remote] [--local]
#   --remote  only remote (referenced) skills
#   --local   only local-scope skills
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

ONLY_REMOTE=0 ONLY_LOCAL=0
for arg in "$@"; do
    case "$arg" in
        --remote) ONLY_REMOTE=1 ;;
        --local)  ONLY_LOCAL=1 ;;
        -h|--help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'list-skills: unknown arg: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

CACHE="$(skill_cache_dir)"
LOCK="$CACHE/skills.lock"
GEN_ROOT="$MEMORY_DIR/skills"
LOC_ROOT="$MEMORY_DIR/skills-local"

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

GEN_NAMES="$(_declared_names "$(skill_manifest generic)")"
LOC_NAMES="$(_declared_names "$(skill_manifest local)")"

has_name() { printf '%s\n' "$1" | grep -qxF "$2"; }
lock_pin() { [ -f "$LOCK" ] || return 0; awk -F '\t' -v n="$1" '/^#/{next} $1==n{print substr($2,1,10); exit}' "$LOCK"; }

emit_rows() {
    local d name scope source synced pin
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        name="$(basename "$d")"
        case "$d" in
            "$CACHE"/*)
                source=remote; pin="$(lock_pin "$name")"; [ -n "$pin" ] || pin='-'
                if has_name "$GEN_NAMES" "$name"; then scope=generic; synced=yes
                elif has_name "$LOC_NAMES" "$name"; then scope=local; synced=no
                else scope='?'; synced='?'; fi ;;   # in the cache but no manifest declares it
            "$LOC_ROOT"/*) source=authored; scope=local;   synced=no;  pin='-' ;;
            "$GEN_ROOT"/*) source=authored; scope=generic; synced=yes; pin='-' ;;
            *)             source='?'; scope='?'; synced='?'; pin='-' ;;
        esac
        [ "$ONLY_REMOTE" = 1 ] && [ "$source" != remote ] && continue
        [ "$ONLY_LOCAL" = 1 ]  && [ "$scope" != local ]   && continue
        printf '%-30s %-8s %-9s %-7s %s\n' "$name" "$scope" "$source" "$synced" "$pin"
    done < <(list_skill_dirs)
}

printf '%-30s %-8s %-9s %-7s %s\n' SKILL SCOPE SOURCE SYNCED PIN
emit_rows | sort
