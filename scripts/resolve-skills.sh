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

# _manifest_tsv <file> — emit one TSV row per declared skill: name\turl\tref\tpath\trecurse\tprefix\texclude.
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
us = chr(31)
for s in (data.get("skills") or []):
    if not isinstance(s, dict):
        continue
    exclude_items = s.get("exclude") or []
    if not isinstance(exclude_items, list):
        sys.stderr.write("resolve-skills: exclude must be a list for %r\n" % (s.get("name", "") or ""))
        sys.exit(3)
    if any(not isinstance(c, str) for c in exclude_items):
        sys.stderr.write("resolve-skills: exclude entries must be strings for %r\n" % (s.get("name", "") or ""))
        sys.exit(3)
    row = [str(s.get(k, "") or "") for k in ("name", "url", "ref", "path")]
    row.extend(["1" if s.get("recurse") else "", str(s.get("prefix", "") or ""), us.join(exclude_items)])
    if any("\t" in c or "\n" in c for c in row):
        sys.stderr.write("resolve-skills: tab/newline in manifest field for %r\n" % row[0])
        sys.exit(3)
    print("\t".join(row))
PY
}

# lock helpers (TSV: name\tsha\turl\tref\tpath\torigin; '#'-comment lines ignored).
lock_sha() { [ -f "$LOCK" ] || return 1; awk -F '\t' -v n="$1" '/^#/{next} $1==n{print $2; exit}' "$LOCK"; }
lock_has() { [ -f "$LOCK" ] || return 1; awk -F '\t' -v n="$1" '/^#/{next} $1==n{f=1} END{exit !f}' "$LOCK"; }
lock_names_for_origin() { [ -f "$LOCK" ] || return 0; awk -F '\t' -v o="$1" '/^#/{next} $6==o{print $1}' "$LOCK"; }
lock_set() { # name sha url ref path
    mkdir -p "$CACHE"
    local tmp="$LOCK.$$"
    local origin="$3#$5"
    { [ -f "$LOCK" ] && grep -v "^#" "$LOCK" | awk -F '\t' -v n="$1" '$1!=n'; } > "$tmp" 2>/dev/null || : > "$tmp"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "$5" "$origin" >> "$tmp"
    { printf '# skills.lock — resolved remote skills (managed by resolve-skills.sh)\n'
      printf '# name<TAB>sha<TAB>url<TAB>ref<TAB>path<TAB>origin\n'
      sort "$tmp"; } > "$LOCK"
    rm -f "$tmp"
}
lock_drop() { # name
    [ -f "$LOCK" ] || return 0
    mkdir -p "$CACHE"
    local tmp="$LOCK.$$"
    { grep -v "^#" "$LOCK" | awk -F '\t' -v n="$1" '$1!=n'; } > "$tmp" 2>/dev/null || : > "$tmp"
    { printf '# skills.lock — resolved remote skills (managed by resolve-skills.sh)\n'
      printf '# name<TAB>sha<TAB>url<TAB>ref<TAB>path<TAB>origin\n'
      sort "$tmp"; } > "$LOCK"
    rm -f "$tmp"
}

_claim_name() {
    local name="$1" origin="$2" other
    other="$(awk -F '\t' -v n="$name" '$1==n{print $2; exit}' "$SEEN_FILE" 2>/dev/null || true)"
    if [ -n "$other" ]; then
        [ "$other" = "$origin" ] && return 0
        err "skill name collision: '$name' from $origin also provided by $other; add a distinct prefix"
        return 1
    fi
    printf '%s\t%s\n' "$name" "$origin" >> "$SEEN_FILE"
}

_mark_resolved() {
    printf '%s\n' "$1" >> "$RESOLVED_FILE"
}

preseed_authored_names() {
    local root d cache_root default_cache_root
    cache_root="${CACHE%/}"
    default_cache_root="${MEMORY_DIR%/}/.skill-cache"
    while IFS= read -r root; do
        root="${root%/}"
        [ -d "$root" ] || continue
        case "$root" in
            "$cache_root"|"$default_cache_root") continue ;;
        esac
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            [ -f "$d/SKILL.md" ] || continue
            printf '%s\tauthored:%s\n' "$(basename "$d")" "$root" >> "$SEEN_FILE"
        done
    done <<EOF
$(skill_roots)
EOF
}

prune_stale_locked() {
    [ "$UPDATE" = 1 ] || return 0
    [ -f "$LOCK" ] || return 0

    local stale row name origin tab
    stale="$(mktemp 2>/dev/null)" || { err "prune: mktemp failed"; return 1; }
    awk -F '\t' '/^#/{next} {print $1 "\t" $6}' "$LOCK" > "$stale"
    tab="$(printf '\t')"
    while IFS= read -r row; do
        [ -n "$row" ] || continue
        name="${row%%"$tab"*}"
        origin="${row#*"$tab"}"
        grep -Fxq "$name" "$RESOLVED_FILE" 2>/dev/null && continue
        if [ "$DRYRUN" = 1 ]; then
            printf '  would-prune %-28s (origin %s)\n' "$name" "$origin"
        else
            rm -rf "${CACHE:?}/$name"
            lock_drop "$name"
            printf '  pruned   %-28s (origin %s)\n' "$name" "$origin"
        fi
    done < "$stale"
    rm -f "$stale"
}

split_manifest_row() {
    local line="$1" tab
    tab="$(printf '\t')"
    name="${line%%"$tab"*}"; line="${line#*"$tab"}"
    url="${line%%"$tab"*}"; line="${line#*"$tab"}"
    ref="${line%%"$tab"*}"; line="${line#*"$tab"}"
    path="${line%%"$tab"*}"; line="${line#*"$tab"}"
    recurse="${line%%"$tab"*}"; line="${line#*"$tab"}"
    prefix="${line%%"$tab"*}"; line="${line#*"$tab"}"
    exclude="$line"
}

git_supports_sparse() { git sparse-checkout -h >/dev/null 2>&1; }

_fetch_ref() {
    local name="$1" scope="$2" tmp="$3" url="$4" ref="$5" path="$6"
    local refspec sha

    git init -q "$tmp" 2>/dev/null || { err "$name: git init failed"; return 1; }
    git -C "$tmp" remote add origin "$url" 2>/dev/null

    # Shallow fetch of the ref; fall back to a full fetch if the ref can't be shallow
    # (e.g. fetching a bare sha the server won't serve by-want). HARD FAIL if neither.
    if git -C "$tmp" fetch -q --depth 1 origin "$ref" 2>/dev/null; then
        refspec="FETCH_HEAD"
    elif git -C "$tmp" fetch -q origin 2>/dev/null; then
        refspec="$ref"
    else
        err "$name ($scope): fetch failed for $url@$ref (offline or bad ref)"; return 1
    fi
    sha="$(git -C "$tmp" rev-parse "$refspec" 2>/dev/null)" || { err "$name: cannot resolve ref $ref"; return 1; }

    if [ -n "$path" ] && git_supports_sparse; then
        git -C "$tmp" sparse-checkout set --no-cone "$path" >/dev/null 2>&1 || true
    fi
    git -C "$tmp" checkout -q "$sha" 2>/dev/null || { err "$name: checkout $sha failed"; return 1; }
    printf '%s\n' "$sha"
}

_skill_frontmatter_name() {
    local file="$1"
    python3 - "$file" <<'PY'
import sys
try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        lines = fh.read().splitlines()
except Exception:
    sys.exit(0)
if not lines or lines[0].strip() != "---":
    sys.exit(0)
for line in lines[1:]:
    if line.strip() == "---":
        break
    if line.lstrip().startswith("name:"):
        val = line.split(":", 1)[1].strip()
        if len(val) >= 2 and val[0] == val[-1] and val[0] in ("'", '"'):
            val = val[1:-1].strip()
        print(val)
        break
PY
}

_excluded_by_glob() {
    local rel="$1" exclude="$2" us pat rest
    [ -n "$exclude" ] || return 1
    us="$(printf '\037')"
    rest="$exclude"
    while :; do
        case "$rest" in
            *"$us"*) pat="${rest%%"$us"*}"; rest="${rest#*"$us"}" ;;
            *) pat="$rest"; rest= ;;
        esac
        # Manifest exclude patterns are shell case-globs; '*' spans '/'.
        # shellcheck disable=SC2254
        [ -n "$pat" ] && case "$rel" in $pat) return 0 ;; esac
        [ -n "$rest" ] || break
    done
    return 1
}

_recurse_cleanup() {
    rm -f "$1" "$2" "$3" "$4"
    rm -rf "$5"
}

# resolve_one <name> <url> <ref> <path> <scope> <recurse> <prefix> <exclude>
resolve_one() {
    local name="$1" url="$2" ref="$3" path="$4" scope="$5" recurse="$6" prefix="$7" exclude="$8"
    if [ "$recurse" = 1 ]; then
        [ -n "$url" ] || { err "$scope: recurse row missing url"; return 1; }
        [ -n "$ref" ] || { err "recurse ($scope): missing ref (pin a branch/tag/sha for reproducibility)"; return 1; }
        case "$path" in /*|*..*) err "recurse ($scope): path must be repo-relative, no '..'"; return 1 ;; esac
        if [ "$DRYRUN" = 1 ] && [ "$UPDATE" != 1 ]; then
            printf '  would-expand %-25s %s@%s [%s]\n' "$url" "$url" "$ref" "$path"
            return 0
        fi

        local origin names replay_name missing
        origin="$url#$path"
        if [ "$UPDATE" != 1 ]; then
            names="$(lock_names_for_origin "$origin")"
            if [ -n "$names" ]; then
                missing=0
                while IFS= read -r replay_name; do
                    [ -f "$CACHE/$replay_name/SKILL.md" ] || { missing=1; break; }
                done <<EOF
$names
EOF
                if [ "$missing" = 0 ]; then
                    while IFS= read -r replay_name; do
                        _claim_name "$replay_name" "$origin" || return 1
                    done <<EOF
$names
EOF
                    while IFS= read -r replay_name; do
                        printf '  cached   %-28s %s@%s\n' "$replay_name" "$url" "$ref"
                    done <<EOF
$names
EOF
                    return 0
                fi
            fi
        fi

        local tmp sha src found candidates accepted candidates_sorted row depth rel dir skip acc skill_name dest count tab
        tmp="$(mktemp -d 2>/dev/null)" || { err "recurse: mktemp failed"; return 1; }
        sha="$(_fetch_ref "recurse" "$scope" "$tmp" "$url" "$ref" "$path")" || { rm -rf "$tmp"; return 1; }

        src="$tmp"; [ -n "$path" ] && src="$tmp/$path"
        if [ ! -d "$src" ]; then
            rm -rf "$tmp"; err "recurse ($scope): no directory at ${path:-<repo root>} in $url@$ref"; return 1
        fi

        found="$(mktemp 2>/dev/null)" || { rm -rf "$tmp"; err "recurse: mktemp failed"; return 1; }
        candidates="$(mktemp 2>/dev/null)" || { rm -f "$found"; rm -rf "$tmp"; err "recurse: mktemp failed"; return 1; }
        accepted="$(mktemp 2>/dev/null)" || { rm -f "$found" "$candidates"; rm -rf "$tmp"; err "recurse: mktemp failed"; return 1; }
        candidates_sorted="$(mktemp 2>/dev/null)" || { rm -f "$found" "$candidates" "$accepted"; rm -rf "$tmp"; err "recurse: mktemp failed"; return 1; }
        : > "$candidates"; : > "$accepted"
        find "$src" -type d -name .git -prune -o -name SKILL.md -type f -print > "$found"
        while IFS= read -r row; do
            dir="$(dirname "$row")"
            if [ "$dir" = "$src" ]; then
                rel=""
            else
                rel="${dir#"$src"/}"
            fi
            depth="$(awk -v r="$rel" 'BEGIN { if (r == "") print 0; else { n = gsub(/\//, "/", r); print n + 1 } }')"
            printf '%s\t%s\t%s\n' "$depth" "$rel" "$dir" >> "$candidates"
        done < "$found"
        sort -n -k1,1 -k2,2 "$candidates" > "$candidates_sorted"

        count=0
        tab="$(printf '\t')"
        exec 3< "$candidates_sorted"
        while IFS= read -r -u 3 row; do
            depth="${row%%"$tab"*}"; row="${row#*"$tab"}"
            rel="${row%%"$tab"*}"; row="${row#*"$tab"}"
            dir="$row"
            : "$depth"
            skip=0
            if [ -s "$accepted" ]; then
                while IFS= read -r acc; do
                    if [ -z "$acc" ] || [ "$rel" = "$acc" ]; then
                        skip=1; break
                    fi
                    case "$rel" in "$acc"/*) skip=1; break ;; esac
                done < "$accepted"
            fi
            [ "$skip" = 1 ] && continue
            printf '%s\n' "$rel" >> "$accepted"

            _excluded_by_glob "$rel" "$exclude" && continue

            skill_name="$(_skill_frontmatter_name "$dir/SKILL.md")"
            if [ -z "$skill_name" ]; then
                if [ -z "$rel" ] && [ -n "$path" ]; then
                    skill_name="$(basename "$path")"
                elif [ -z "$rel" ]; then
                    skill_name="$(basename "${url%/}")"
                    skill_name="${skill_name%.git}"
                else
                    skill_name="$(basename "$dir")"
                fi
            fi
            skill_name="$prefix$skill_name"
            case "$skill_name" in ""|*[!A-Za-z0-9._-]*|.|..) _recurse_cleanup "$found" "$candidates" "$accepted" "$candidates_sorted" "$tmp"; err "invalid skill name '$skill_name' in $scope manifest"; return 1 ;; esac

            dest="$CACHE/$skill_name"
            _claim_name "$skill_name" "$origin" || { _recurse_cleanup "$found" "$candidates" "$accepted" "$candidates_sorted" "$tmp"; return 1; }
            if [ "$DRYRUN" = 1 ]; then
                _mark_resolved "$skill_name"
                printf '  would-resolve %-26s %s (%s@%s)\n' "$skill_name" "$(printf '%.12s' "$sha")" "$url" "$ref"
                count=$((count + 1))
                continue
            fi
            rm -rf "$dest"; mkdir -p "$CACHE"
            cp -R "$dir" "$dest" || { _recurse_cleanup "$found" "$candidates" "$accepted" "$candidates_sorted" "$tmp"; err "$skill_name: copy into cache failed"; return 1; }
            rm -rf "$dest/.git"
            lock_set "$skill_name" "$sha" "$url" "$ref" "$path"
            _mark_resolved "$skill_name"
            printf '  resolved %-28s %s (%s@%s)\n' "$skill_name" "$(printf '%.12s' "$sha")" "$url" "$ref"
            count=$((count + 1))
        done
        exec 3<&-

        _recurse_cleanup "$found" "$candidates" "$accepted" "$candidates_sorted" "$tmp"
        if [ "$count" = 0 ]; then
            err "recurse ($scope): no skills matched under ${path:-<repo root>} in $url@$ref"
            return 1
        fi
        return 0
    fi
    : "$prefix" "$exclude"
    case "$name" in ""|*[!A-Za-z0-9._-]*|.|..) err "invalid skill name '$name' in $scope manifest"; return 1 ;; esac
    [ -n "$url" ] || { err "$name ($scope): missing url"; return 1; }
    [ -n "$ref" ] || { err "$name ($scope): missing ref (pin a branch/tag/sha for reproducibility)"; return 1; }
    case "$path" in /*|*..*) err "$name ($scope): path must be repo-relative, no '..'"; return 1 ;; esac

    local dest="$CACHE/$name"

    # Cache hit: already resolved and present -> no network (offline-safe re-link).
    if [ "$UPDATE" != 1 ] && [ -f "$dest/SKILL.md" ] && lock_has "$name"; then
        _claim_name "$name" "$url#$path" || return 1
        printf '  cached   %-28s %s@%s\n' "$name" "$url" "$ref"
        return 0
    fi
    if [ "$DRYRUN" = 1 ]; then
        _claim_name "$name" "$url#$path" || return 1
        [ "$UPDATE" = 1 ] && _mark_resolved "$name"
        printf '  would-fetch %-25s %s@%s%s\n' "$name" "$url" "$ref" "${path:+ [$path]}"
        return 0
    fi

    local tmp sha src
    tmp="$(mktemp -d 2>/dev/null)" || { err "$name: mktemp failed"; return 1; }
    sha="$(_fetch_ref "$name" "$scope" "$tmp" "$url" "$ref" "$path")" || { rm -rf "$tmp"; return 1; }

    src="$tmp"; [ -n "$path" ] && src="$tmp/$path"
    if [ ! -f "$src/SKILL.md" ]; then
        rm -rf "$tmp"; err "$name ($scope): no SKILL.md at ${path:-<repo root>} in $url@$ref"; return 1
    fi

    _claim_name "$name" "$url#$path" || { rm -rf "$tmp"; return 1; }
    rm -rf "$dest"; mkdir -p "$CACHE"
    cp -R "$src" "$dest" || { rm -rf "$tmp"; err "$name: copy into cache failed"; return 1; }
    rm -rf "$dest/.git"   # never keep a nested repo in the cache
    rm -rf "$tmp"
    lock_set "$name" "$sha" "$url" "$ref" "$path"
    _mark_resolved "$name"
    printf '  resolved %-28s %s (%s@%s)\n' "$name" "$(printf '%.12s' "$sha")" "$url" "$ref"
    return 0
}

# --- gather declared remotes from the root manifest ---------------------------
rows="$(_manifest_tsv "$MANIFEST")" || exit 3

if [ "$LIST" = 1 ]; then
    printf '%-30s %-10s %s\n' "SKILL" "RESOLVED" "SOURCE"
    print_rows() {
        local row name url ref path recurse prefix exclude sha origin names child
        while IFS= read -r row; do
            split_manifest_row "$row"
            [ -n "$name" ] || [ "$recurse" = 1 ] || continue
            if [ "$recurse" = 1 ]; then
                origin="$url#$path"
                names="$(lock_names_for_origin "$origin")"
                if [ -z "$names" ]; then
                    printf '%-30s %-10s %s@%s%s %s\n' "${name:-[recurse]}" \
                        "" "$url" "$ref" "${path:+ [$path]}" "(unresolved - run resolve-skills)"
                    continue
                fi
                while IFS= read -r child; do
                    [ -n "$child" ] || continue
                    sha="$(lock_sha "$child" 2>/dev/null || true)"
                    printf '%-30s %-10s %s@%s%s\n' "$child" \
                        "${sha:+$(printf '%.10s' "$sha")}" "$url" "$ref" "${path:+ [$path]}"
                done <<EOF
$names
EOF
                continue
            fi
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
SEEN_FILE="$(mktemp 2>/dev/null)" || { err "mktemp failed"; exit 2; }
RESOLVED_FILE="$(mktemp 2>/dev/null)" || { rm -f "$SEEN_FILE"; err "mktemp failed"; exit 2; }
trap 'rm -f "$SEEN_FILE" "$RESOLVED_FILE"' EXIT
preseed_authored_names
resolve_rows() {
    local row name url ref path recurse prefix exclude
    while IFS= read -r row; do
        split_manifest_row "$row"
        [ -n "$name" ] || [ "$recurse" = 1 ] || continue
        n=$((n + 1))
        resolve_one "$name" "$url" "$ref" "$path" "root" "$recurse" "$prefix" "$exclude" || rc=1
    done
}
# Feed via here-strings so the counters/rc survive (no subshell pipe).
resolve_rows <<EOF
$rows
EOF

if [ "$rc" = 0 ]; then
    prune_stale_locked || rc=1
fi

if [ "$rc" != 0 ]; then
    err "one or more remotes failed to resolve"
    exit 1
fi
if [ "$n" = 0 ]; then
    printf 'resolve-skills: no remote skills declared (skills.toml)\n'
    exit 0
fi
printf 'resolve-skills: %d remote skill(s) resolved into %s\n' "$n" "$CACHE"
exit 0
