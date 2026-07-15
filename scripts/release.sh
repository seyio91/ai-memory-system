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
#   printf '%s\n\n%s\n' "v<version>" "<changelog section body>" | git tag -a "v<version>" --cleanup=verbatim -F -
#   git push origin main
#   git push origin "v<version>"
#
# Usage:
#   release.sh [<version>] [--ci] [--dry-run] [--no-push]   (local one-shot cut)
#   release.sh [<version>] --prepare                        (CI: assemble on a release branch)
#   release.sh  <version>  --publish                        (CI: tag the merged release commit)
#
#   <version>  bare stable semver, e.g. 1.0.0 (tag becomes v1.0.0). OPTIONAL for the
#              default and --prepare paths: omit it and the version is computed from
#              changelog.d/ fragment kinds (breaking->major, feature->minor, fix/upgrade->patch).
#   --ci       non-interactive publish: also create the GitHub Release (gh).
#   --dry-run  run guards and print the changelog section; mutate nothing
#   --no-push  create the local release commit and tag, but skip both pushes
#   --prepare  assemble CHANGELOG + delete fragments + commit on the CURRENT (release/*)
#              branch; NO tag, NO push. Drives the auto-opened Release PR. Refuses on main.
#   --publish  tag the prepared release commit that is already on main + push tag + GitHub
#              Release (implies --ci). Expects resume-at-tag state (the Release PR merged).

set -euo pipefail

if [ -n "${AI_MEMORY_ROLE:-}" ]; then
    echo "release.sh is orchestrator-only; tag-push is the publish act." >&2
    exit 1
fi

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
. "$REPO_ROOT/scripts/_lib.sh"

VERSION=""
TAG=""
RELEASE_COMMIT_SUBJECT=""
DRY_RUN=0
NO_PUSH=0
CI=0
PREPARE=0
PUBLISH=0
SEMVER_RE='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
CHANGELOG_D="$REPO_ROOT/changelog.d"
ASSEMBLE="$REPO_ROOT/scripts/assemble-changelog.sh"

usage() {
    sed -n '15,28p' "$0" >&2
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
        --ci) CI=1 ;;
        --prepare) PREPARE=1 ;;
        --publish) PUBLISH=1; CI=1 ;;
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

if [ "$PREPARE" = 1 ] && [ "$PUBLISH" = 1 ]; then
    echo "  ABORT: --prepare and --publish are mutually exclusive." >&2
    usage
    exit 2
fi
if { [ "$PREPARE" = 1 ] || [ "$PUBLISH" = 1 ]; } && [ "$DRY_RUN" = 1 ]; then
    echo "  ABORT: --dry-run does not apply to --prepare/--publish." >&2
    exit 2
fi

# A version may be given explicitly OR computed from changelog.d/ fragments after
# fetch (resolve_version, below). Validation + tag naming happen in finalize_version,
# called once the version is known.
validate_semver() {
    if ! printf '%s\n' "$1" | grep -Eq "$SEMVER_RE"; then
        echo "  ABORT: release version must be a bare stable semver: <major>.<minor>.<patch>." >&2
        echo "  Example: scripts/release.sh 1.0.0" >&2
        echo "  Prerelease/build metadata and a leading v are not accepted." >&2
        exit 2
    fi
}

finalize_version() {
    validate_semver "$VERSION"
    TAG="v$VERSION"
    RELEASE_COMMIT_SUBJECT="chore(release): $TAG"
}

# fragment_status: 0 = changelog.d/ has valid fragments; 1 = present but invalid;
# 2 = none (or the assembler is unavailable — fall back to legacy drafting).
fragment_status() {
    [ -x "$ASSEMBLE" ] || [ -f "$ASSEMBLE" ] || return 2
    bash "$ASSEMBLE" --dir "$CHANGELOG_D" --check >/dev/null 2>&1
    case $? in
        0) return 0 ;;
        1) return 1 ;;
        *) return 2 ;;
    esac
}

# resolve_version — called AFTER fetch so the latest tag is current. Aborts on
# invalid fragments (whether or not a version was passed); computes the version
# from fragment kinds when none was given.
resolve_version() {
    local st=0
    fragment_status || st=$?
    [ "$st" = 1 ] && abort "changelog.d/ has invalid fragments." "Run scripts/assemble-changelog.sh --check and fix them."
    if [ -z "$VERSION" ]; then
        if [ "$st" = 0 ]; then
            VERSION="$(bash "$ASSEMBLE" --dir "$CHANGELOG_D" --bump)" \
                || abort "could not compute a version from changelog.d/ fragments."
        else
            echo "missing release version" >&2
            echo "  Pass a version (scripts/release.sh 1.4.0) or add changelog.d/ fragments." >&2
            usage
            exit 2
        fi
    fi
    finalize_version
}

RELEASE_MODE="normal"

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
    local allow_ahead="${1:-0}"
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
        [ "$allow_ahead" = 1 ] && return 0
        abort "local main is ahead of origin/main." "Push or drop local commits before releasing."
    fi
    abort "local main has diverged from origin/main." "Reconcile main with origin/main before releasing."
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
    local file tmp
    file="$(changelog_path)"
    [ -f "$file" ] && return 0
    tmp="$file.tmp.$$"
    cat > "$tmp" <<'EOF'
# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]
EOF
    mv "$tmp" "$file"
}

unreleased_heading_count() {
    local file
    file="$(changelog_path)"
    [ -f "$file" ] || { printf '1\n'; return 0; }
    awk '
        { sub(/\r$/, "", $0) }
        /^## \[Unreleased\]$/ { count++ }
        END { printf "%d\n", count + 0 }
    ' "$file"
}

require_one_unreleased_section() {
    local count
    count="$(unreleased_heading_count)"
    [ "$count" = 1 ] && return 0
    abort "CHANGELOG.md must contain exactly one ## [Unreleased] heading; found $count." "Fix the changelog headings before releasing."
}

version_heading_count() {
    local file version="$1"
    file="$(changelog_path)"
    [ -f "$file" ] || { printf '0\n'; return 0; }
    awk -v version="$version" '
        { sub(/\r$/, "", $0) }
        $0 == "## [" version "]" || index($0, "## [" version "] - ") == 1 { count++ }
        END { printf "%d\n", count + 0 }
    ' "$file"
}

ensure_no_version_section() {
    local count
    count="$(version_heading_count "$VERSION")"
    [ "$count" = 0 ] && return 0
    abort "CHANGELOG.md already contains a ## [$VERSION] section." "Reconcile the existing section before running the normal release path."
}

unreleased_body() {
    local file
    file="$(changelog_path)"
    [ -f "$file" ] || return 0
    awk '
        { line=$0; sub(/\r$/, "", line) }
        line == "## [Unreleased]" { in_section=1; next }
        in_section && line ~ /^## / { exit }
        in_section { print }
    ' "$file"
}

changelog_prefix() {
    awk '{ line=$0; sub(/\r$/, "", line); if (line == "## [Unreleased]") exit; print }' "$(changelog_path)"
}

changelog_suffix() {
    awk '
        { line=$0; sub(/\r$/, "", line) }
        line == "## [Unreleased]" { in_section=1; next }
        in_section && line ~ /^## / { in_suffix=1 }
        in_suffix { print }
    ' "$(changelog_path)"
}

newest_release_version() {
    local file
    file="$(changelog_path)"
    [ -f "$file" ] || return 0
    awk '
        { line=$0; sub(/\r$/, "", line) }
        line ~ /^## \[[0-9]+\.[0-9]+\.[0-9]+\]( - .*)?$/ {
            sub(/^## \[/, "", line)
            sub(/\].*$/, "", line)
            print line
            exit
        }
    ' "$file"
}

version_body() {
    local file version="$1"
    file="$(changelog_path)"
    [ -f "$file" ] || return 0
    awk -v version="$version" '
        { line=$0; sub(/\r$/, "", line) }
        line == "## [" version "]" || index(line, "## [" version "] - ") == 1 { in_section=1; next }
        in_section && line ~ /^## / { exit }
        in_section { print }
    ' "$file"
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
    # Fragments, when present, are the source of truth — assemble deterministically
    # and skip the git-log draft entirely.
    if fragment_status; then
        bash "$ASSEMBLE" --dir "$CHANGELOG_D" assemble
        return 0
    fi
    require_one_unreleased_section
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
        if [ -n "$prefix" ]; then
            printf '%s\n\n' "$prefix"
        fi
        printf '## [Unreleased]\n\n'
        printf '## [%s] - %s\n' "$version" "$date"
        if [ -n "$suffix" ]; then
            printf '%s\n\n' "$body"
            printf '%s\n' "$suffix"
        else
            printf '%s\n' "$body"
        fi
    } > "$tmp"
    mv "$tmp" "$file"
}

tag_message() {
    local body="$1"
    printf '%s\n\n%s\n' "$TAG" "$body"
}

dry_run_report() {
    local prev="$1" body="$2" date="$3" mode="$4"
    printf 'release mode: %s\n' "$mode"
    printf 'previous tag: %s\n' "${prev:-<none>}"
    printf 'new tag: %s\n' "$TAG"
    printf 'changelog section that would be written:\n'
    printf '## [%s] - %s\n' "$VERSION" "$date"
    printf '%s\n' "$body"
}

remote_tag_commit() {
    local tag="$1" out
    out="$(git ls-remote --tags origin "refs/tags/$tag^{}" "refs/tags/$tag" | awk '
        $2 ~ /\^\{\}$/ { peeled=$1 }
        $2 !~ /\^\{\}$/ && first == "" { first=$1 }
        END {
            if (peeled != "") print peeled
            else if (first != "") print first
        }
    ')" || return 1
    [ -n "$out" ] || return 1
    printf '%s\n' "$out"
}

local_tag_commit() {
    git rev-list -n 1 "$1"
}

detect_release_state() {
    local local_exists=0 remote_exists=0 local_commit="" remote_commit="" head subject newest

    if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
        local_exists=1
        local_commit="$(local_tag_commit "$TAG")"
    fi
    if remote_commit="$(remote_tag_commit "$TAG")"; then
        remote_exists=1
    fi

    if [ "$remote_exists" = 1 ] && [ "$local_exists" = 1 ]; then
        if [ "$remote_commit" != "$local_commit" ]; then
            abort "$TAG exists locally and on origin but points at different commits." "Local: $local_commit; origin: $remote_commit"
        fi
        if git merge-base --is-ancestor "$local_commit" origin/main; then
            RELEASE_MODE="already-released"
            return 0
        fi
        abort "$TAG exists on origin but its commit is not reachable from origin/main." "Commit: $local_commit"
    fi

    if [ "$remote_exists" = 1 ]; then
        abort "$TAG exists on origin but not locally — \`git fetch --tags\` and reconcile."
    fi

    head="$(git rev-parse HEAD)"
    if [ "$local_exists" = 1 ]; then
        if [ "$local_commit" = "$head" ]; then
            RELEASE_MODE="resume-at-push"
            return 0
        fi
        abort "$TAG already exists locally on another commit: $local_commit." "Reconcile or delete the local tag before releasing."
    fi

    subject="$(git log -1 --format=%s)"
    newest="$(newest_release_version)"
    if [ "$subject" = "$RELEASE_COMMIT_SUBJECT" ] && [ "$newest" = "$VERSION" ]; then
        RELEASE_MODE="resume-at-tag"
        return 0
    fi

    RELEASE_MODE="normal"
}

push_failure_resume_message() {
    printf 're-run `release.sh %s` to resume — it will detect the existing commit/tag and only push what'\''s missing.\n' "$VERSION" >&2
}

push_main_if_needed() {
    if git merge-base --is-ancestor HEAD origin/main; then
        return 0
    fi
    if ! git push origin main; then
        push_failure_resume_message
        exit 1
    fi
}

push_tag_if_needed() {
    if remote_tag_commit "$TAG" >/dev/null 2>&1; then
        return 0
    fi
    if ! git push origin "$TAG"; then
        push_failure_resume_message
        exit 1
    fi
}

create_gh_release() {
    # Idempotent: an existing release (resume) is left alone. Notes come from the
    # assembled body when we have it, else from the annotated tag message.
    if gh release view "$TAG" >/dev/null 2>&1; then
        return 0
    fi
    if [ -n "$RELEASE_BODY" ]; then
        gh release create "$TAG" --title "$TAG" --notes "$RELEASE_BODY" || \
            abort "gh release create failed for $TAG." "The tag is pushed; create the Release manually or re-run --ci."
    else
        gh release create "$TAG" --title "$TAG" --notes-from-tag || \
            abort "gh release create failed for $TAG." "The tag is pushed; create the Release manually or re-run --ci."
    fi
}

publish_release() {
    if [ "$NO_PUSH" = 1 ]; then
        printf 'Created local release commit and tag %s (--no-push).\n' "$TAG"
        return 0
    fi
    push_main_if_needed
    push_tag_if_needed
    [ "$CI" = 1 ] && create_gh_release
    printf 'Released %s.\n' "$TAG"
}

# prepare_release (--prepare) — assemble the CHANGELOG section from fragments and
# commit it on the CURRENT (release/*) branch, deleting the consumed fragments. NO
# tag, NO push: the auto-opened Release PR carries this commit for review, and the
# tag is cut by --publish once it merges. Refuses on main (main is written only via
# the PR merge). The suite is not re-run here — CI runs it as the PR check.
prepare_release() {
    local branch
    branch="$(git rev-parse --abbrev-ref HEAD)"
    [ "$branch" = "main" ] && abort "--prepare must run on a release branch, not main." "main is written only when the Release PR merges."
    fetch_origin
    resolve_version
    fragment_status || abort "no changelog.d/ fragments to prepare — nothing to release."
    PREV_TAG="$(previous_tag)"
    version_guard "$PREV_TAG"
    ensure_no_version_section
    seed_changelog
    RELEASE_BODY="$(release_body "$PREV_TAG")"
    write_final_changelog "$VERSION" "$RELEASE_BODY" "$TODAY"
    git add CHANGELOG.md
    if fragment_status; then git rm -q "$CHANGELOG_D"/*.*.md; fi
    git commit -q -m "$RELEASE_COMMIT_SUBJECT"
    printf 'Prepared %s on %s — no tag, no push.\n' "$TAG" "$branch"
}

# publish_prepared_release (--publish) — the prepared release is already on main (the
# Release PR merged, by ANY strategy — merge commit, squash, or rebase). The invariant
# is content, not a commit subject: CHANGELOG.md carries the ## [VERSION] section and no
# vVERSION tag exists yet. Tag main's HEAD, push the tag, create the GH Release. Reruns
# are idempotent. Implies --ci.
publish_prepared_release() {
    local count
    count="$(version_heading_count "$VERSION")"
    [ "$count" = 1 ] || abort "no prepared '## [$VERSION]' section in CHANGELOG.md on main." "Did the Release PR (release/$TAG) merge?"

    # Already fully released → nothing to do (idempotent).
    if git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null && remote_tag_commit "$TAG" >/dev/null 2>&1; then
        printf '%s is already released.\n' "$TAG"
        return 0
    fi
    if remote_tag_commit "$TAG" >/dev/null 2>&1; then
        abort "$TAG exists on origin but not locally." "Run \`git fetch --tags\` and reconcile before publishing."
    fi

    origin_main_guard 1
    if ! git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null; then
        RELEASE_BODY="$(version_body "$VERSION")"
        tag_message "$RELEASE_BODY" | git tag -a "$TAG" --cleanup=verbatim -F -
    fi
    publish_release
}

PREV_TAG=""
RELEASE_BODY=""
TODAY="$(date +%Y-%m-%d)"

dirty_tracked_guard

if [ "$PREPARE" = 1 ]; then
    prepare_release
    exit 0
fi

branch_guard
fetch_origin
resolve_version

if [ "$PUBLISH" = 1 ]; then
    publish_prepared_release
    exit 0
fi

detect_release_state

case "$RELEASE_MODE" in
    already-released)
        printf '%s is already released; local and origin tags match and are reachable from origin/main.\n' "$TAG"
        exit 0
        ;;
    resume-at-push)
        origin_main_guard 1
        ;;
    resume-at-tag)
        origin_main_guard 1
        ;;
    normal)
        origin_main_guard 0
        PREV_TAG="$(previous_tag)"
        version_guard "$PREV_TAG"
        ensure_no_version_section
        ;;
    *)
        abort "internal error: unknown release mode $RELEASE_MODE."
        ;;
esac

# Resume-at-push already has the release commit and local annotated tag. The suite
# passed before those existed; re-running it would block recovery without testing new code.
[ "$RELEASE_MODE" = "resume-at-push" ] || run_suite_guard

if [ "$DRY_RUN" = 1 ]; then
    if [ "$RELEASE_MODE" = "resume-at-push" ]; then
        RELEASE_BODY="$(version_body "$VERSION")"
    elif [ "$RELEASE_MODE" = "resume-at-tag" ]; then
        RELEASE_BODY="$(version_body "$VERSION")"
    else
        RELEASE_BODY="$(release_body "$PREV_TAG")"
    fi
    dry_run_report "$PREV_TAG" "$RELEASE_BODY" "$TODAY" "$RELEASE_MODE"
    exit 0
fi

case "$RELEASE_MODE" in
    resume-at-push)
        publish_release
        exit 0
        ;;
    resume-at-tag)
        RELEASE_BODY="$(version_body "$VERSION")"
        tag_message "$RELEASE_BODY" | git tag -a "$TAG" --cleanup=verbatim -F -
        publish_release
        exit 0
        ;;
esac

seed_changelog
RELEASE_BODY="$(release_body "$PREV_TAG")"
write_final_changelog "$VERSION" "$RELEASE_BODY" "$TODAY"
git add CHANGELOG.md
# release_body ran in a subshell, so re-check here: if fragments fed this release,
# they've been assembled into CHANGELOG.md and must be removed in the same commit.
if fragment_status; then
    git rm -q "$CHANGELOG_D"/*.*.md
fi
git commit -q -m "$RELEASE_COMMIT_SUBJECT"
tag_message "$RELEASE_BODY" | git tag -a "$TAG" --cleanup=verbatim -F -
publish_release
