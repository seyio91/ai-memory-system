#!/usr/bin/env bash
#
# release.sh — finalize CHANGELOG.md and cut a stable git-tag release.
#
# Manual equivalent:
#   edit CHANGELOG.md so ## [Unreleased] contains the release notes
#   move those notes under ## [<version>] - YYYY-MM-DD
#   add a fresh empty ## [Unreleased] section above it
#   git add CHANGELOG.md
#   git commit -m "chore(release): v<version>"
#   git tag -a "v<version>" -m "<version plus changelog section body>"
#   git push origin main
#   git push origin "v<version>"
#
# Usage:
#   release.sh <version> [--dry-run] [--no-push]
#
#   <version>  bare stable semver, e.g. 1.0.0 (tag becomes v1.0.0)
#   --dry-run  run guards and print the changelog section; mutate nothing
#   --no-push  create the local release commit and tag, but skip both pushes

set -euo pipefail

if [ -n "${AI_MEMORY_ROLE:-}" ]; then
    echo "release.sh is orchestrator-only; tag-push is the publish act." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/_lib.sh"

VERSION=""
TAG=""
DRY_RUN=0
NO_PUSH=0
SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'

usage() {
    sed -n '9,20p' "$0" >&2
}

abort() {
    echo "  ABORT: $1" >&2
    [ $# -gt 1 ] && echo "  $2" >&2
    exit 1
}

while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run) DRY_RUN=1 ;;
        --no-push) NO_PUSH=1 ;;
        -*) echo "unknown flag: $1" >&2; usage; exit 2 ;;
        *)
            if [ -n "$VERSION" ]; then
                echo "unexpected argument: $1" >&2
                usage
                exit 2
            fi
            VERSION="$1"
            ;;
    esac
    shift
done

if [ -z "$VERSION" ]; then
    echo "missing release version" >&2
    usage
    exit 2
fi

if ! printf '%s\n' "$VERSION" | grep -Eq "$SEMVER_RE"; then
    echo "  ABORT: release version must be a bare stable semver: <major>.<minor>.<patch>." >&2
    echo "  Example: scripts/release.sh 1.0.0" >&2
    echo "  Prerelease/build metadata and a leading v are not accepted." >&2
    exit 2
fi

TAG="v$VERSION"

cd "$REPO_ROOT"

dirty_tracked_guard() {
    if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
        echo "  ABORT: tracked files have local modifications or staged changes." >&2
        echo "  Commit/stash/revert tracked changes, then re-run release.sh." >&2
        echo "  Untracked files do not block release." >&2
        git status --short --untracked-files=no >&2
        exit 1
    fi
}

branch_guard() {
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"
    if [ "$branch" != "main" ]; then
        abort "release.sh must run from branch main." "Current branch: $branch"
    fi
}

fetch_origin() {
    if ! git fetch --quiet --tags origin; then
        abort "could not fetch tags from origin." "Check network/remote access, then re-run release.sh."
    fi
}

origin_main_guard() {
    local local_sha remote_sha
    if ! git rev-parse --verify --quiet refs/remotes/origin/main >/dev/null; then
        abort "origin/main is missing after fetch." "Set the origin remote and fetch main before releasing."
    fi

    local_sha="$(git rev-parse main)"
    remote_sha="$(git rev-parse origin/main)"
    [ "$local_sha" = "$remote_sha" ] && return 0

    if git merge-base --is-ancestor main origin/main; then
        abort "local main is behind origin/main." "Fast-forward main before releasing."
    fi
    if git merge-base --is-ancestor origin/main main; then
        abort "local main is ahead of origin/main." "Push or drop local commits before releasing."
    fi
    abort "local main has diverged from origin/main." "Reconcile main with origin/main before releasing."
}

tag_guard() {
    if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
        abort "tag $TAG already exists locally or on origin." "Choose a new version or delete the incorrect tag by hand."
    fi
}

previous_tag() {
    local tag
    if tag="$(latest_release_tag)"; then
        printf '%s\n' "$tag"
    else
        printf '\n'
    fi
}

version_guard() {
    local prev="$1"
    [ -n "$prev" ] || return 0
    if ! semver_gt "$VERSION" "${prev#v}"; then
        abort "release version $VERSION must be greater than latest stable tag $prev." "Choose a strictly newer semver."
    fi
}

run_suite_guard() {
    if ! bash "$REPO_ROOT/scripts/run-tests.sh"; then
        abort "test suite failed." "Fix the failing tests before releasing."
    fi
}

changelog_path() {
    printf '%s\n' "$REPO_ROOT/CHANGELOG.md"
}

seed_changelog() {
    local file
    file="$(changelog_path)"
    [ -f "$file" ] && return 0
    cat > "$file" <<'EOF'
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
EOF
}

has_unreleased_section() {
    local file
    file="$(changelog_path)"
    [ -f "$file" ] || return 0
    grep -Eq '^## \[Unreleased\]$' "$file"
}

unreleased_body() {
    local file
    file="$(changelog_path)"
    [ -f "$file" ] || return 0
    awk '
        /^## \[Unreleased\]$/ { in_section=1; next }
        in_section && /^## / { exit }
        in_section { print }
    ' "$file"
}

changelog_prefix() {
    awk '/^## \[Unreleased\]$/ { exit } { print }' "$(changelog_path)"
}

changelog_suffix() {
    awk '
        /^## \[Unreleased\]$/ { in_section=1; next }
        in_section && /^## / { in_suffix=1 }
        in_suffix { print }
    ' "$(changelog_path)"
}

body_has_entries() {
    printf '%s\n' "$1" | grep -Eq '[^[:space:]]'
}

draft_entries() {
    local prev="$1" commits commit
    if [ -n "$prev" ]; then
        commits="$(git --no-pager log "$prev..HEAD" --oneline)"
    else
        commits="$(git --no-pager log --oneline)"
    fi
    if [ -z "$commits" ]; then
        abort "nothing to release." "No commits exist since ${prev:-repository start}."
    fi
    while IFS= read -r commit; do
        [ -n "$commit" ] || continue
        printf -- '- %s\n' "$commit"
    done <<EOF
$commits
EOF
}

release_body() {
    local prev="$1" body
    if ! has_unreleased_section; then
        abort "CHANGELOG.md is missing an ## [Unreleased] section." "Add the section or remove CHANGELOG.md so release.sh can seed it."
    fi
    body="$(unreleased_body)"
    if body_has_entries "$body"; then
        printf '%s\n' "$body"
    else
        draft_entries "$prev"
    fi
}

write_final_changelog() {
    local version="$1" body="$2" date="$3" file tmp prefix suffix
    file="$(changelog_path)"
    tmp="$file.tmp.$$"
    prefix="$(changelog_prefix)"
    suffix="$(changelog_suffix)"
    {
        [ -n "$prefix" ] && printf '%s\n' "$prefix"
        printf '## [Unreleased]\n\n'
        printf '## [%s] - %s\n' "$version" "$date"
        printf '%s\n\n' "$body"
        [ -n "$suffix" ] && printf '%s\n' "$suffix"
    } > "$tmp"
    mv "$tmp" "$file"
}

tag_message() {
    local body="$1"
    printf '%s\n\n%s\n' "$TAG" "$body"
}

dry_run_report() {
    local prev="$1" body="$2" date="$3"
    printf 'previous tag: %s\n' "${prev:-<none>}"
    printf 'new tag: %s\n' "$TAG"
    printf 'changelog section that would be written:\n'
    printf '## [%s] - %s\n' "$VERSION" "$date"
    printf '%s\n' "$body"
}

PREV_TAG=""
RELEASE_BODY=""
TODAY="$(date +%Y-%m-%d)"

dirty_tracked_guard
branch_guard
fetch_origin
origin_main_guard
tag_guard
PREV_TAG="$(previous_tag)"
version_guard "$PREV_TAG"
run_suite_guard

if [ "$DRY_RUN" = 1 ]; then
    RELEASE_BODY="$(release_body "$PREV_TAG")"
    dry_run_report "$PREV_TAG" "$RELEASE_BODY" "$TODAY"
    exit 0
fi

seed_changelog
RELEASE_BODY="$(release_body "$PREV_TAG")"
write_final_changelog "$VERSION" "$RELEASE_BODY" "$TODAY"

git add CHANGELOG.md
git commit -q -m "chore(release): $TAG"
git tag -a "$TAG" -m "$(tag_message "$RELEASE_BODY")"

if [ "$NO_PUSH" = 1 ]; then
    printf 'Created local release commit and tag %s (--no-push).\n' "$TAG"
else
    git push origin main
    git push origin "$TAG"
    printf 'Released %s.\n' "$TAG"
fi
