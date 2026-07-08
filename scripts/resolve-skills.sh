#!/usr/bin/env bash
#
# resolve-skills.sh — materialize REMOTE skills declared in the root manifest into the
# gitignored cache, pinned by a lockfile. Remote skills are *referenced, not forked*:
# the declaration (name + git url + ref [+ path]) lives in per-instance skills.toml;
# the content is fetched per-instance into .skill-cache/ and never committed.
# Bumping `ref` and re-resolving (--update) is how a remote skill updates.
#
# Manifest, TOML — you maintain the list, one [[skills]] entry per skill:
#   skills.toml                — per-instance remotes (gitignored)
# Each entry: name, url, ref (required) + path (optional subdir holding SKILL.md).
# Parsing uses python3's stdlib tomllib (3.11+) — no pip dependency.
#
# Fetch is sparse + shallow; the resolved commit is pinned in .skill-cache/skills.lock.
# A plain resolve is a CACHE HIT for anything already in the lockfile (no network) —
# so re-linking works offline. Only a first-time resolve or --update hits the network,
# and a fetch failure is a HARD ERROR (strict reproducibility).
#
# Usage:
#   resolve-skills.sh [--update] [--dry-run]   # resolve all declared remotes
#   resolve-skills.sh --list                   # show declared remotes + resolved sha
#
# Exit: 0 all resolved (or cache-hit), 1 a fetch/validation failed, 2 usage/setup.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

UPDATE=0 DRYRUN=0 LIST=0
for arg in "$@"; do
    case "$arg" in
        --update)  UPDATE=1 ;;
        --dry-run) DRYRUN=1 ;;
        --list)    LIST=1 ;;
        -h|--help) sed -n '2,26p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) printf 'resolve-skills: unknown arg: %s\n' "$arg" >&2; exit 2 ;;
    esac
done

CACHE="$(skill_cache_dir)"
LOCK="$CACHE/skills.lock"
MANIFEST="$(skill_manifest)"

err()  { printf 'resolve-skills: %s\n' "$*" >&2; }

# _manifest_tsv <file> — emit one TSV row per declared skill: name\turl\tref\tpath.
# Parses TOML via python3's stdlib tomllib (3.11+); no pip dependency. Missing file
# -> nothing. Unparseable file or missing tomllib -> exit 3 (surfaced by the caller).
_manifest_tsv() {
    local f="$1"
    [ -f "$f" ] || return 0
    command -v python3 >/dev/null 2>&1 || { err "need python3 to parse $f"; return 3; }
    python3 - "$f" <<'PY'
import sys
try:
    import tomllib
except ModuleNotFoundError:
    sys.stderr.write("resolve-skills: TOML manifest needs python3.11+ (stdlib tomllib)\n")
    sys.exit(3)
try:
    with open(sys.argv[1], "rb") as fh:
        data = tomllib.load(fh)
except Exception as e:
    sys.stderr.write("resolve-skills: cannot parse %s: %s\n" % (sys.argv[1], e))
    sys.exit(3)
for s in (data.get("skills") or []):
    if not isinstance(s, dict):
        continue
    row = [str(s.get(k, "") or "") for k in ("name", "url", "ref", "path")]
    if any("\t" in c or "\n" in c for c in row):
        sys.stderr.write("resolve-skills: tab/newline in manifest field for %r\n" % row[0])
        sys.exit(3)
    print("\t".join(row))
PY
}

# lock helpers (TSV: name\tsha\turl\tref\tpath; '#'-comment lines ignored).
lock_sha() { [ -f "$LOCK" ] || return 1; awk -F '\t' -v n="$1" '/^#/{next} $1==n{print $2; exit}' "$LOCK"; }
lock_has() { [ -f "$LOCK" ] || return 1; awk -F '\t' -v n="$1" '/^#/{next} $1==n{f=1} END{exit !f}' "$LOCK"; }
lock_set() { # name sha url ref path
    mkdir -p "$CACHE"
    local tmp="$LOCK.$$"
    { [ -f "$LOCK" ] && grep -v "^#" "$LOCK" | awk -F '\t' -v n="$1" '$1!=n'; } > "$tmp" 2>/dev/null || : > "$tmp"
    printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" >> "$tmp"
    { printf '# skills.lock — resolved remote skills (managed by resolve-skills.sh)\n'
      printf '# name<TAB>sha<TAB>url<TAB>ref<TAB>path\n'
      sort "$tmp"; } > "$LOCK"
    rm -f "$tmp"
}

git_supports_sparse() { git sparse-checkout -h >/dev/null 2>&1; }

# resolve_one <name> <url> <ref> <path> <scope>
resolve_one() {
    local name="$1" url="$2" ref="$3" path="$4" scope="$5"
    case "$name" in ""|*[!A-Za-z0-9._-]*|.|..) err "invalid skill name '$name' in $scope manifest"; return 1 ;; esac
    [ -n "$url" ] || { err "$name ($scope): missing url"; return 1; }
    [ -n "$ref" ] || { err "$name ($scope): missing ref (pin a branch/tag/sha for reproducibility)"; return 1; }
    case "$path" in /*|*..*) err "$name ($scope): path must be repo-relative, no '..'"; return 1 ;; esac

    local dest="$CACHE/$name"

    # Cache hit: already resolved and present -> no network (offline-safe re-link).
    if [ "$UPDATE" != 1 ] && [ -f "$dest/SKILL.md" ] && lock_has "$name"; then
        printf '  cached   %-28s %s@%s\n' "$name" "$url" "$ref"
        return 0
    fi
    if [ "$DRYRUN" = 1 ]; then
        printf '  would-fetch %-25s %s@%s%s\n' "$name" "$url" "$ref" "${path:+ [$path]}"
        return 0
    fi

    local tmp refspec sha src
    tmp="$(mktemp -d 2>/dev/null)" || { err "$name: mktemp failed"; return 1; }
    git init -q "$tmp" 2>/dev/null || { rm -rf "$tmp"; err "$name: git init failed"; return 1; }
    git -C "$tmp" remote add origin "$url" 2>/dev/null

    # Shallow fetch of the ref; fall back to a full fetch if the ref can't be shallow
    # (e.g. fetching a bare sha the server won't serve by-want). HARD FAIL if neither.
    if git -C "$tmp" fetch -q --depth 1 origin "$ref" 2>/dev/null; then
        refspec="FETCH_HEAD"
    elif git -C "$tmp" fetch -q origin 2>/dev/null; then
        refspec="$ref"
    else
        rm -rf "$tmp"; err "$name ($scope): fetch failed for $url@$ref (offline or bad ref)"; return 1
    fi
    sha="$(git -C "$tmp" rev-parse "$refspec" 2>/dev/null)" || { rm -rf "$tmp"; err "$name: cannot resolve ref $ref"; return 1; }

    if [ -n "$path" ] && git_supports_sparse; then
        git -C "$tmp" sparse-checkout set --no-cone "$path" >/dev/null 2>&1 || true
    fi
    git -C "$tmp" checkout -q "$sha" 2>/dev/null || { rm -rf "$tmp"; err "$name: checkout $sha failed"; return 1; }

    src="$tmp"; [ -n "$path" ] && src="$tmp/$path"
    if [ ! -f "$src/SKILL.md" ]; then
        rm -rf "$tmp"; err "$name ($scope): no SKILL.md at ${path:-<repo root>} in $url@$ref"; return 1
    fi

    rm -rf "$dest"; mkdir -p "$CACHE"
    cp -R "$src" "$dest" || { rm -rf "$tmp"; err "$name: copy into cache failed"; return 1; }
    rm -rf "$dest/.git"   # never keep a nested repo in the cache
    rm -rf "$tmp"
    lock_set "$name" "$sha" "$url" "$ref" "$path"
    printf '  resolved %-28s %s (%s@%s)\n' "$name" "$(printf '%.12s' "$sha")" "$url" "$ref"
    return 0
}

# --- gather declared remotes from the root manifest ---------------------------
rows="$(_manifest_tsv "$MANIFEST")" || exit 3

if [ "$LIST" = 1 ]; then
    printf '%-30s %-10s %s\n' "SKILL" "RESOLVED" "SOURCE"
    print_rows() {
        local line name url ref path sha
        while IFS="$(printf '\t')" read -r name url ref path; do
            [ -n "$name" ] || continue
            sha="$(lock_sha "$name" 2>/dev/null || true)"
            printf '%-30s %-10s %s@%s%s\n' "$name" \
                "${sha:+$(printf '%.10s' "$sha")}" "$url" "$ref" "${path:+ [$path]}"
        done
    }
    printf '%s\n' "$rows" | print_rows
    exit 0
fi

# --- resolve --------------------------------------------------------------------
rc=0 n=0
resolve_rows() {
    local name url ref path
    while IFS="$(printf '\t')" read -r name url ref path; do
        [ -n "$name" ] || continue
        n=$((n + 1))
        resolve_one "$name" "$url" "$ref" "$path" "root" || rc=1
    done
}
# Feed via here-strings so the counters/rc survive (no subshell pipe).
resolve_rows <<EOF
$rows
EOF

if [ "$n" = 0 ]; then
    printf 'resolve-skills: no remote skills declared (skills.toml)\n'
    exit 0
fi
if [ "$rc" != 0 ]; then
    err "one or more remotes failed to resolve"
    exit 1
fi
printf 'resolve-skills: %d remote skill(s) resolved into %s\n' "$n" "$CACHE"
exit 0
