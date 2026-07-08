#!/usr/bin/env bash
# release.sh guards, changelog finalization, and local tag creation.
. "$(dirname "$0")/_assert.sh"

ROOT="$(new_sandbox)"
trap 'rm -rf "$ROOT"' EXIT

git_identity() {
    git -C "$1" config user.email "tests@example.invalid"
    git -C "$1" config user.name "Memory Tests"
}

commit_all() {
    local repo="$1" msg="$2"
    git -C "$repo" add .
    git -C "$repo" commit -q -m "$msg"
}

write_fixture_scripts() {
    local repo="$1"
    mkdir -p "$repo/scripts"
    cp "$SCRIPTS_DIR/release.sh" "$repo/scripts/release.sh"
    cp "$SCRIPTS_DIR/_lib.sh" "$repo/scripts/_lib.sh"
    cat > "$repo/scripts/run-tests.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ "${FAIL_TESTS:-}" = "1" ]; then
    echo "stub tests failed"
    exit 1
fi
echo "stub tests passed"
EOF
    chmod +x "$repo/scripts/release.sh" "$repo/scripts/run-tests.sh"
}

make_fixture() {
    local name="$1"
    local repo="$ROOT/$name/repo"
    local origin="$ROOT/$name/origin.git"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b main
    git_identity "$repo"
    write_fixture_scripts "$repo"
    printf 'base\n' > "$repo/README.md"
    commit_all "$repo" "base"
    git clone -q --bare "$repo" "$origin"
    git -C "$repo" remote add origin "$origin"
    git -C "$repo" fetch -q --tags origin
    git -C "$repo" branch --set-upstream-to=origin/main main >/dev/null
    printf '%s\n' "$repo"
}

push_main() {
    git -C "$1" push -q origin main
}

push_tags() {
    git -C "$1" push -q origin --tags
}

add_commit() {
    local repo="$1" msg="$2" file="$3" content="$4"
    printf '%s\n' "$content" > "$repo/$file"
    commit_all "$repo" "$msg"
}

capture_release() {
    local repo="$1"
    shift
    ( cd "$repo" && env -u AI_MEMORY_ROLE bash scripts/release.sh "$@" ) 2>&1
}

run_release() {
    local repo="$1"
    shift
    ( cd "$repo" && env -u AI_MEMORY_ROLE bash scripts/release.sh "$@" )
}

capture_release_env() {
    local repo="$1" env_name="$2" env_value="$3"
    shift 3
    ( cd "$repo" && env -u AI_MEMORY_ROLE "$env_name=$env_value" bash scripts/release.sh "$@" ) 2>&1
}

assert_tag_absent() {
    local repo="$1" tag="$2" label="$3"
    if git -C "$repo" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null; then
        _bad "$label"
    else
        _ok "$label"
    fi
}

assert_origin_tag_absent() {
    local origin="$1" tag="$2" label="$3"
    if git -C "$origin" show-ref --verify --quiet "refs/tags/$tag"; then
        _bad "$label"
    else
        _ok "$label"
    fi
}

assert_guard_no_mutation() {
    local repo="$1" before_head="$2" tag="$3" label="$4"
    assert_eq "$before_head" "$(git -C "$repo" rev-parse HEAD)" "$label leaves HEAD unchanged"
    assert_tag_absent "$repo" "$tag" "$label creates no requested tag"
}

# --- happy path: first release ---
R1="$(make_fixture first-release)"
before_head="$(git -C "$R1" rev-parse HEAD)"
first_out="$(capture_release "$R1" 1.0.0 --no-push)"
assert_contains "$first_out" "Created local release commit and tag v1.0.0" "first release reports local tag"
assert_contains "$(cat "$R1/CHANGELOG.md")" "## [1.0.0] -" "first release finalizes version section"
assert_contains "$(cat "$R1/CHANGELOG.md")" "- $(git -C "$R1" rev-parse --short "$before_head") base" "first release drafts changelog from history"
assert_eq "tag" "$(git -C "$R1" cat-file -t v1.0.0)" "first release creates annotated tag"
assert_contains "$(git -C "$R1" cat-file -p v1.0.0)" "- $(git -C "$R1" rev-parse --short "$before_head") base" "tag message contains changelog body"
assert_eq "$before_head" "$(git -C "$R1" rev-parse origin/main)" "--no-push leaves origin/main unchanged"
assert_origin_tag_absent "$ROOT/first-release/origin.git" "v1.0.0" "--no-push leaves origin tag absent"

# --- second release drafts only commits since previous stable tag ---
R2="$(make_fixture second-release)"
git -C "$R2" tag v1.0.0
push_tags "$R2"
add_commit "$R2" "feature after 1.0" "feature.txt" "feature"
new_commit="$(git -C "$R2" rev-parse HEAD)"
push_main "$R2"
second_out="$(capture_release "$R2" 1.1.0 --no-push)"
assert_contains "$second_out" "v1.1.0" "second release reports v1.1.0"
assert_contains "$(cat "$R2/CHANGELOG.md")" "- $(git -C "$R2" rev-parse --short "$new_commit") feature after 1.0" "second release drafts from v1.0.0..HEAD"
assert_not_contains "$(cat "$R2/CHANGELOG.md")" "- $(git -C "$R2" rev-parse --short v1.0.0) base" "second release excludes commits before previous tag"

# --- hand-written Unreleased entries are preserved, with a fresh section above ---
R3="$(make_fixture handwritten)"
cat > "$R3/CHANGELOG.md" <<'EOF'
# Changelog

## [Unreleased]
- hand-written entry
  with continuation

## [0.9.0] - 2026-01-01
- old entry
EOF
git -C "$R3" add CHANGELOG.md
git -C "$R3" commit -q -m "seed changelog"
push_main "$R3"
run_release "$R3" 1.0.0 --no-push >/dev/null 2>&1
handwritten_changelog="$(cat "$R3/CHANGELOG.md")"
assert_contains "$handwritten_changelog" "## [Unreleased]" "fresh Unreleased section remains"
assert_contains "$handwritten_changelog" "## [1.0.0] -" "handwritten release finalizes version section"
assert_contains "$handwritten_changelog" "- hand-written entry
  with continuation" "hand-written entries are preserved verbatim"
assert_contains "$handwritten_changelog" "## [0.9.0] - 2026-01-01" "older changelog sections remain"
first_heading="$(grep -n '^## ' "$R3/CHANGELOG.md" | head -1 | cut -d: -f2-)"
assert_eq "## [Unreleased]" "$first_heading" "fresh empty Unreleased is above finalized section"

# --- untracked files do not block ---
UNTRACKED="$(make_fixture untracked)"
printf 'scratch\n' > "$UNTRACKED/scratch.txt"
run_release "$UNTRACKED" 1.0.0 --no-push >/dev/null 2>&1
assert_eq "tag" "$(git -C "$UNTRACKED" cat-file -t v1.0.0)" "untracked files do not block release"

# --- guards refuse and mutate nothing ---
BAD_VERSION="$(make_fixture bad-version)"
before="$(git -C "$BAD_VERSION" rev-parse HEAD)"
set +e
bad_version_out="$(capture_release "$BAD_VERSION" v1.0.0 --no-push)"
bad_version_rc=$?
set -u
assert_exit 2 "$bad_version_rc" "bad version exits usage error"
assert_contains "$bad_version_out" "bare stable semver" "bad version explains semver format"
assert_guard_no_mutation "$BAD_VERSION" "$before" "vv1.0.0" "bad version guard"

DIRTY="$(make_fixture dirty)"
printf 'dirty\n' > "$DIRTY/README.md"
before="$(git -C "$DIRTY" rev-parse HEAD)"
set +e
dirty_out="$(capture_release "$DIRTY" 1.0.0 --no-push)"
dirty_rc=$?
set -u
assert_exit 1 "$dirty_rc" "dirty tracked exits nonzero"
assert_contains "$dirty_out" "tracked files have local modifications" "dirty tracked explains guard"
assert_guard_no_mutation "$DIRTY" "$before" "v1.0.0" "dirty tracked guard"

NOT_MAIN="$(make_fixture not-main)"
git -C "$NOT_MAIN" checkout -q -b feature
before="$(git -C "$NOT_MAIN" rev-parse HEAD)"
set +e
not_main_out="$(capture_release "$NOT_MAIN" 1.0.0 --no-push)"
not_main_rc=$?
set -u
assert_exit 1 "$not_main_rc" "not-main exits nonzero"
assert_contains "$not_main_out" "must run from branch main" "not-main explains guard"
assert_guard_no_mutation "$NOT_MAIN" "$before" "v1.0.0" "not-main guard"

AHEAD="$(make_fixture ahead)"
add_commit "$AHEAD" "local ahead" "ahead.txt" "ahead"
before="$(git -C "$AHEAD" rev-parse HEAD)"
set +e
ahead_out="$(capture_release "$AHEAD" 1.0.0 --no-push)"
ahead_rc=$?
set -u
assert_exit 1 "$ahead_rc" "local ahead exits nonzero"
assert_contains "$ahead_out" "local main is ahead of origin/main" "local ahead reports direction"
assert_guard_no_mutation "$AHEAD" "$before" "v1.0.0" "local ahead guard"

BEHIND="$(make_fixture behind)"
PEER="$ROOT/behind/peer"
git clone -q "$ROOT/behind/origin.git" "$PEER"
git_identity "$PEER"
add_commit "$PEER" "remote ahead" "remote.txt" "remote"
git -C "$PEER" push -q origin main
before="$(git -C "$BEHIND" rev-parse HEAD)"
set +e
behind_out="$(capture_release "$BEHIND" 1.0.0 --no-push)"
behind_rc=$?
set -u
assert_exit 1 "$behind_rc" "local behind exits nonzero"
assert_contains "$behind_out" "local main is behind origin/main" "local behind reports direction"
assert_guard_no_mutation "$BEHIND" "$before" "v1.0.0" "local behind guard"

TAG_EXISTS="$(make_fixture tag-exists)"
git -C "$TAG_EXISTS" tag v1.2.0
push_tags "$TAG_EXISTS"
before="$(git -C "$TAG_EXISTS" rev-parse HEAD)"
set +e
tag_exists_out="$(capture_release "$TAG_EXISTS" 1.2.0 --no-push)"
tag_exists_rc=$?
set -u
assert_exit 1 "$tag_exists_rc" "existing tag exits nonzero"
assert_contains "$tag_exists_out" "tag v1.2.0 already exists" "existing tag explains guard"
assert_eq "$before" "$(git -C "$TAG_EXISTS" rev-parse HEAD)" "existing tag leaves HEAD unchanged"

EQUAL="$(make_fixture equal)"
git -C "$EQUAL" tag v1.0.0
push_tags "$EQUAL"
before="$(git -C "$EQUAL" rev-parse HEAD)"
set +e
equal_out="$(capture_release "$EQUAL" 1.0.0 --no-push)"
equal_rc=$?
set -u
assert_exit 1 "$equal_rc" "equal version exits nonzero"
assert_contains "$equal_out" "tag v1.0.0 already exists" "equal version is refused before mutation"
assert_eq "$before" "$(git -C "$EQUAL" rev-parse HEAD)" "equal version leaves HEAD unchanged"

LOWER="$(make_fixture lower)"
git -C "$LOWER" tag v1.0.0
push_tags "$LOWER"
add_commit "$LOWER" "after previous" "after.txt" "after"
push_main "$LOWER"
before="$(git -C "$LOWER" rev-parse HEAD)"
set +e
lower_out="$(capture_release "$LOWER" 0.9.0 --no-push)"
lower_rc=$?
set -u
assert_exit 1 "$lower_rc" "lower version exits nonzero"
assert_contains "$lower_out" "must be greater than latest stable tag v1.0.0" "lower version explains monotonic guard"
assert_guard_no_mutation "$LOWER" "$before" "v0.9.0" "lower version guard"

FAIL_SUITE="$(make_fixture failing-suite)"
before="$(git -C "$FAIL_SUITE" rev-parse HEAD)"
set +e
fail_suite_out="$(capture_release_env "$FAIL_SUITE" FAIL_TESTS 1 1.0.0 --no-push)"
fail_suite_rc=$?
set -u
assert_exit 1 "$fail_suite_rc" "failing suite exits nonzero"
assert_contains "$fail_suite_out" "test suite failed" "failing suite explains guard"
assert_guard_no_mutation "$FAIL_SUITE" "$before" "v1.0.0" "failing suite guard"

ROLE="$(make_fixture role)"
before="$(git -C "$ROLE" rev-parse HEAD)"
set +e
role_out="$(cd "$ROLE" && AI_MEMORY_ROLE=task bash scripts/release.sh 1.0.0 --no-push 2>&1)"
role_rc=$?
set -u
assert_exit 1 "$role_rc" "AI_MEMORY_ROLE exits nonzero"
assert_contains "$role_out" "release.sh is orchestrator-only" "AI_MEMORY_ROLE refuses before guards"
assert_guard_no_mutation "$ROLE" "$before" "v1.0.0" "AI_MEMORY_ROLE guard"

# --- dry-run prints the would-be section and mutates nothing ---
DRY="$(make_fixture dry-run)"
before="$(git -C "$DRY" rev-parse HEAD)"
dry_out="$(capture_release "$DRY" 1.0.0 --dry-run --no-push)"
assert_eq "$before" "$(git -C "$DRY" rev-parse HEAD)" "dry-run leaves HEAD unchanged"
assert_tag_absent "$DRY" "v1.0.0" "dry-run creates no tag"
if [ ! -f "$DRY/CHANGELOG.md" ]; then _ok "dry-run writes no changelog"; else _bad "dry-run writes no changelog"; fi
assert_contains "$dry_out" "previous tag: <none>" "dry-run reports previous tag"
assert_contains "$dry_out" "new tag: v1.0.0" "dry-run reports new tag"
assert_contains "$dry_out" "## [1.0.0] -" "dry-run prints would-be changelog section"
assert_contains "$dry_out" "- $(git -C "$DRY" rev-parse --short "$before") base" "dry-run prints drafted body"

# --- semver ordering: 1.10.0 > 1.9.0 with sort -V and fallback ---
SEMVER_SORT="$(make_fixture semver-sort)"
git -C "$SEMVER_SORT" tag v1.9.0
push_tags "$SEMVER_SORT"
add_commit "$SEMVER_SORT" "after 1.9" "after.txt" "after"
push_main "$SEMVER_SORT"
run_release "$SEMVER_SORT" 1.10.0 --no-push >/dev/null 2>&1
assert_eq "tag" "$(git -C "$SEMVER_SORT" cat-file -t v1.10.0)" "1.10.0 is greater than 1.9.0 with sort -V"

SEMVER_FALLBACK="$(make_fixture semver-fallback)"
git -C "$SEMVER_FALLBACK" tag v1.9.0
push_tags "$SEMVER_FALLBACK"
add_commit "$SEMVER_FALLBACK" "after 1.9 fallback" "after.txt" "after"
push_main "$SEMVER_FALLBACK"
fallback_out="$(capture_release_env "$SEMVER_FALLBACK" AI_MEMORY_TEST_NO_SORT_V 1 1.10.0 --no-push)"
assert_contains "$fallback_out" "Created local release commit and tag v1.10.0" "1.10.0 is greater than 1.9.0 without sort -V"
assert_eq "tag" "$(git -C "$SEMVER_FALLBACK" cat-file -t v1.10.0)" "fallback path creates v1.10.0 tag"

finish
