#!/usr/bin/env bash
# Shared helpers for memory scripts. Source this from other scripts:
#   . "$(dirname "$0")/_lib.sh"

MEMORY_DIR="${MEMORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Per-environment overrides (gitignored). Lives next to the memory tree; set
# AI_MEMORY_PROJECTS_ROOT, MEMORY_TASK_PROVIDER, etc. here so they reach scripts,
# hooks, and subagents that don't inherit your shell rc. See config.local.sh.example.
[ -f "$MEMORY_DIR/config.local.sh" ] && . "$MEMORY_DIR/config.local.sh"

# skills_with_partial — print the names of skills whose SKILL.md carries a
# managed partial block, one per line. Membership in a partial's loop (e.g.
# self-rating) is DERIVED from marker presence, not a static list — so a skill
# enters the loop exactly when the block is injected (new-skill --kind workflow,
# or apply-partial --force) and never drifts out of sync. With no <skills_dir>,
# scans every skill root (via list_skill_dirs); pass a dir to scan just that one.
#   skills_with_partial <partial> [skills_dir]
skills_with_partial() {
    local partial="$1" dir="${2:-}" d
    if [ -n "$dir" ]; then
        [ -d "$dir" ] || return 0
        for d in "$dir"/*/; do
            [ -f "$d/SKILL.md" ] || continue
            grep -Fq "<!-- partial:$partial START" "$d/SKILL.md" && basename "$d"
        done
        return 0
    fi
    while IFS= read -r d; do
        grep -Fq "<!-- partial:$partial START" "$d/SKILL.md" && basename "$d"
    done < <(list_skill_dirs)
}

# skill_roots — print the skill store roots, one per line, in precedence order:
# authored skills (skills/, gitignored, per-instance) > remote cache
# (.skill-cache/, gitignored, materialized from the root manifest by
# resolve-skills.sh). Override the whole list with AI_MEMORY_SKILL_ROOTS
# (colon-separated). This is the single place roots are declared — every skills
# tool picks up a new root here. Roots need not exist; callers guard.
skill_roots() {
    local roots="${AI_MEMORY_SKILL_ROOTS:-$MEMORY_DIR/skills:$MEMORY_DIR/.skill-cache}"
    local IFS=:
    set -- $roots
    printf '%s\n' "$@"
}

# skill_cache_dir — the remote-skill cache root (gitignored). Content is materialized
# by resolve-skills.sh from skills.toml and pinned by .skill-cache/skills.lock.
skill_cache_dir() {
    printf '%s\n' "${AI_MEMORY_SKILL_CACHE:-$MEMORY_DIR/.skill-cache}"
}

# skill_data_root — per-skill local data root (gitignored). Stateful skills store
# instance-local data here, decoupled from authored/remote skill content.
skill_data_root() {
    printf '%s\n' "${AI_MEMORY_SKILL_DATA:-$MEMORY_DIR/.skill-data}"
}

# skill_data_dir — print/create the data dir for a skill.
#   skill_data_dir <name>
skill_data_dir() {
    local dir
    dir="$(skill_data_root)/$1"
    mkdir -p "$dir"
    printf '%s\n' "$dir"
}

# skill_manifest — path to the per-instance remote-skill TOML manifest.
# Callers may pass an ignored legacy arg; there is one manifest now.
#   skill_manifest
skill_manifest() {
    printf '%s\n' "$MEMORY_DIR/skills.toml"
}

# skill_manifest_template — path to the tracked remote-skill catalog template.
skill_manifest_template() {
    printf '%s\n' "$MEMORY_DIR/skills.toml.example"
}

# list_skill_dirs — print every skill dir (one absolute path per line, no trailing
# slash) across all skill roots. A "skill dir" is an immediate child of a root that
# contains a SKILL.md; dirs without one are silently skipped (not skills). This is the
# single source of "what skills exist and where" — link/fan-out/ratings tools route
# through it. Tools that must also see malformed candidate dirs (e.g. validate-skills
# flagging a dir missing its SKILL.md) iterate skill_roots directly.
list_skill_dirs() {
    local root d
    while IFS= read -r root; do
        [ -d "$root" ] || continue
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            [ -f "$d/SKILL.md" ] || continue
            printf '%s\n' "${d%/}"
        done
    done < <(skill_roots)
}

# resolve_skill_dir — print the absolute dir of the skill named <name>, searching
# roots in precedence order (first match wins), and return 0; return 1 if no root
# holds a skill by that name. Lets name-addressed tools (apply-partial, ratings)
# work regardless of whether a skill is authored or remote.
#   resolve_skill_dir <name>
resolve_skill_dir() {
    local name="$1" d
    while IFS= read -r d; do
        [ "$(basename "$d")" = "$name" ] && { printf '%s\n' "$d"; return 0; }
    done < <(list_skill_dirs)
    return 1
}

_semver_num() {
    case "$1" in
        ''|*[!0-9]*) printf '0\n' ;;
        *) printf '%s\n' "$1" ;;
    esac
}

semver_gt() {
    # Stable tags sort above prereleases with the same core version, but this
    # intentionally does not order prerelease identifiers against each other.
    # Phase 2 migration versions are always stable, so that is sufficient here.
    local a="${1#v}" b="${2#v}" old_ifs
    local a_core b_core a_pre b_pre
    local a1 a2 a3 b1 b2 b3

    a="${a%%+*}"
    b="${b%%+*}"
    a_core="${a%%-*}"
    b_core="${b%%-*}"
    a_pre=""
    b_pre=""
    case "$a" in *-*) a_pre="${a#*-}" ;; esac
    case "$b" in *-*) b_pre="${b#*-}" ;; esac

    old_ifs="$IFS"
    IFS=.
    set -- $a_core
    a1="$(_semver_num "${1:-0}")"
    a2="$(_semver_num "${2:-0}")"
    a3="$(_semver_num "${3:-0}")"
    set -- $b_core
    b1="$(_semver_num "${1:-0}")"
    b2="$(_semver_num "${2:-0}")"
    b3="$(_semver_num "${3:-0}")"
    IFS="$old_ifs"

    [ "$a1" -gt "$b1" ] && return 0
    [ "$a1" -lt "$b1" ] && return 1
    [ "$a2" -gt "$b2" ] && return 0
    [ "$a2" -lt "$b2" ] && return 1
    [ "$a3" -gt "$b3" ] && return 0
    [ "$a3" -lt "$b3" ] && return 1
    [ -z "$a_pre" ] && [ -n "$b_pre" ] && return 0
    return 1
}

sort_v_supported() {
    local last
    [ "${AI_MEMORY_TEST_NO_SORT_V:-}" = "1" ] && return 1
    last="$(printf 'v1.10.0\nv1.9.0\n' | sort -V 2>/dev/null | tail -1 || true)"
    [ "$last" = "v1.10.0" ]
}

semver_sort_asc() {
    local v i j
    local versions=()

    if sort_v_supported; then
        sort -V
        return 0
    fi

    while IFS= read -r v; do
        [ -n "$v" ] || continue
        if [ "${#versions[@]}" -eq 0 ]; then
            versions[0]="$v"
            continue
        fi
        i=0
        while [ "$i" -lt "${#versions[@]}" ]; do
            if semver_gt "${versions[$i]}" "$v"; then
                j="${#versions[@]}"
                while [ "$j" -gt "$i" ]; do
                    versions[$j]="${versions[$((j - 1))]}"
                    j=$((j - 1))
                done
                versions[$i]="$v"
                break
            fi
            i=$((i + 1))
        done
        if [ "$i" -eq "${#versions[@]}" ]; then
            versions[$i]="$v"
        fi
    done

    if [ "${#versions[@]}" -gt 0 ]; then
        printf '%s\n' "${versions[@]}"
    fi
}

stable_release_tags() {
    git tag -l 'v*' | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' || true
}

latest_release_tag() {
    local tag candidate
    tag=""
    if sort_v_supported; then
        tag="$(stable_release_tags | sort -V | tail -1)"
    else
        while IFS= read -r candidate; do
            [ -n "$candidate" ] || continue
            if [ -z "$tag" ] || semver_gt "$candidate" "$tag"; then
                tag="$candidate"
            fi
        done < <(stable_release_tags)
    fi
    [ -n "$tag" ] || return 1
    printf '%s\n' "$tag"
}

# detect_active_project — print active project name to stdout, or empty.
# Walks up from $1 (defaults to cwd) looking for the harness-neutral marker
# .agents/memory-project, falling back to the legacy .claude/memory-project (pre-
# Phase-6 pins) at the same level. No marker -> empty: no global fallback, the
# project is whichever repo you are in. Nearest marker wins (per-level check).
detect_active_project() {
    local start_dir="${1:-$PWD}"
    local dir="$start_dir"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -f "$dir/.agents/memory-project" ]; then
            tr -d '[:space:]' < "$dir/.agents/memory-project"
            return 0
        fi
        if [ -f "$dir/.claude/memory-project" ]; then   # legacy fallback
            tr -d '[:space:]' < "$dir/.claude/memory-project"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    return 0
}

# projects_root — print the root under which code checkouts live. Resolved
# per-environment via AI_MEMORY_PROJECTS_ROOT (default below is this install's
# layout; e.g. /workspace in a sandbox container).
projects_root() {
    printf '%s\n' "${AI_MEMORY_PROJECTS_ROOT:-$HOME/Projects}"
}

# resolve_repo_path — print a project's local checkout dir and return 0, else
# print nothing and return 1. Path-first: a literal `$MEMORY_DIR`(/subpath)
# repo_path resolves against the memory tree itself (used by the self-
# referential ai-memory meta-project so the value is machine-independent), an
# absolute repo_path is used as-is, otherwise repo_path is taken relative to
# projects_root. The git remote (repo) is a portable fallback id.
#   resolve_repo_path <project>
resolve_repo_path() {
    local project="$1"
    local mf="$MEMORY_DIR/projects/$project/memory.md"
    [ -f "$mf" ] || return 1

    local rp cand repo root d url
    rp=$(extract_fm_field "$mf" repo_path)
    if [ -n "$rp" ]; then
        case "$rp" in
            '$MEMORY_DIR')    cand="$MEMORY_DIR" ;;
            '$MEMORY_DIR/'*)  cand="$MEMORY_DIR/${rp#\$MEMORY_DIR/}" ;;
            /*) cand="$rp" ;;
            *)  cand="$(projects_root)/$rp" ;;
        esac
        if [ -d "$cand" ]; then
            printf '%s\n' "$cand"
            return 0
        fi
    fi

    # Fallback: locate a checkout under the root whose origin remote matches `repo`.
    repo=$(extract_fm_field "$mf" repo)
    root="$(projects_root)"
    if [ -n "$repo" ] && [ -d "$root" ]; then
        for d in "$root"/*/; do
            [ -d "$d" ] || continue
            d="${d%/}"
            git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || continue
            url=$(git -C "$d" remote get-url origin 2>/dev/null) || url=""
            if [ -n "$url" ] && [ "$url" = "$repo" ]; then
                printf '%s\n' "$d"
                return 0
            fi
        done
    fi

    return 1
}

# extract_fm_field — pull a scalar field from the YAML frontmatter at the top
# of a markdown file. Prints empty string if frontmatter or field is missing.
#   extract_fm_field <file> <field-name>
extract_fm_field() {
    local file="$1" field="$2"
    awk -v f="$field" '
        BEGIN { in_fm = 0 }
        NR == 1 && /^---[[:space:]]*$/ { in_fm = 1; next }
        in_fm && /^---[[:space:]]*$/ { exit }
        in_fm {
            if (match($0, "^" f ":[[:space:]]*")) {
                val = substr($0, RLENGTH + 1)
                sub(/[[:space:]]+$/, "", val)
                print val
                exit
            }
        }
    ' "$file"
}
