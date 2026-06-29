#!/usr/bin/env bash
# Shared helpers for memory scripts. Source this from other scripts:
#   . "$(dirname "$0")/_lib.sh"

MEMORY_DIR="${MEMORY_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Per-environment overrides (gitignored). Lives next to the memory tree; set
# AI_MEMORY_PROJECTS_ROOT, MEMORY_TASK_PROVIDER, etc. here so they reach scripts,
# hooks, and subagents that don't inherit your shell rc. See config.local.sh.example.
[ -f "$MEMORY_DIR/config.local.sh" ] && . "$MEMORY_DIR/config.local.sh"

# detect_active_project — print active project name to stdout, or empty.
# Walks up from $1 (defaults to cwd) looking for .claude/memory-project. No
# marker -> empty: no global fallback, the project is whichever repo you are in.
detect_active_project() {
    local start_dir="${1:-$PWD}"
    local dir="$start_dir"
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        if [ -f "$dir/.claude/memory-project" ]; then
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
# print nothing and return 1. Path-first (repo_path under projects_root, or an
# absolute repo_path), with the git remote (repo) as a portable fallback id.
#   resolve_repo_path <project>
resolve_repo_path() {
    local project="$1"
    local mf="$MEMORY_DIR/projects/$project/memory.md"
    [ -f "$mf" ] || return 1

    local rp cand repo root d url
    rp=$(extract_fm_field "$mf" repo_path)
    if [ -n "$rp" ]; then
        case "$rp" in
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
