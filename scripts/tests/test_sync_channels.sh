#!/usr/bin/env bash
# sync-system.sh channel selection and one-shot --to refs.
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
    cp "$SCRIPTS_DIR/sync-system.sh" "$repo/scripts/sync-system.sh"
    cp "$SCRIPTS_DIR/_lib.sh" "$repo/scripts/_lib.sh"
    cat > "$repo/install.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
git describe --tags --always > install-ran.txt
EOF
    cat > "$repo/scripts/resolve-skills.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'updated\n' > resolve-ran.txt
EOF
    chmod +x "$repo/install.sh" "$repo/scripts/sync-system.sh" "$repo/scripts/resolve-skills.sh"
}

make_fixture() {
    local name="$1" with_tags="${2:-yes}"
    local repo="$ROOT/$name/repo"
    local origin="$ROOT/$name/origin.git"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b main
    git_identity "$repo"
    write_fixture_scripts "$repo"
    printf 'base\n' > "$repo/VERSION"
    commit_all "$repo" "base"
    if [ "$with_tags" = "yes" ]; then
        git -C "$repo" tag v0.1.0
        printf 'nine\n' > "$repo/VERSION"
        commit_all "$repo" "v0.9.0"
        git -C "$repo" tag v0.9.0
        printf 'ten\n' > "$repo/VERSION"
        commit_all "$repo" "v0.10.0"
        git -C "$repo" tag v0.10.0
    else
        printf 'untagged\n' > "$repo/VERSION"
        commit_all "$repo" "untagged"
    fi
    git -C "$repo" checkout -q -b trial
    printf 'trial\n' > "$repo/VERSION"
    commit_all "$repo" "trial branch"
    git -C "$repo" checkout -q main
    git clone -q --bare "$repo" "$origin"
    git -C "$repo" remote add origin "$origin"
    git -C "$repo" fetch -q origin
    git -C "$repo" branch --set-upstream-to=origin/main main >/dev/null
    printf '%s\n' "$repo"
}

make_branch_fixture() {
    local name="$1" branch="$2"
    local repo="$ROOT/$name/repo"
    local origin="$ROOT/$name/origin.git"
    mkdir -p "$repo"
    git -C "$repo" init -q
    git -C "$repo" checkout -q -b "$branch"
    git_identity "$repo"
    write_fixture_scripts "$repo"
    printf 'base\n' > "$repo/VERSION"
    commit_all "$repo" "base"
    git clone -q --bare "$repo" "$origin"
    git -C "$origin" symbolic-ref HEAD "refs/heads/$branch"
    git -C "$repo" remote add origin "$origin"
    git -C "$repo" fetch -q origin
    git -C "$repo" branch --set-upstream-to="origin/$branch" "$branch" >/dev/null
    printf '%s\n' "$repo"
}

make_prerelease_fixture() {
    local name="$1" with_stable_next="${2:-no}"
    local repo
    repo="$(make_fixture "$name" no)"
    git -C "$repo" tag v1.0.0
    printf 'rc\n' > "$repo/VERSION"
    commit_all "$repo" "v1.1.0 rc"
    git -C "$repo" tag v1.1.0-rc.1
    if [ "$with_stable_next" = "yes" ]; then
        printf 'stable\n' > "$repo/VERSION"
        commit_all "$repo" "v1.1.0 stable"
        git -C "$repo" tag v1.1.0
    fi
    printf '%s\n' "$repo"
}

run_sync_unset() {
    local repo="$1"
    shift
    ( cd "$repo" && env -u AI_MEMORY_CHANNEL MEMORY_DIR="$repo" bash scripts/sync-system.sh "$@" )
}

capture_sync_unset() {
    local repo="$1"
    shift
    ( cd "$repo" && env -u AI_MEMORY_CHANNEL MEMORY_DIR="$repo" bash scripts/sync-system.sh "$@" ) 2>&1
}

run_sync_channel() {
    local repo="$1" channel="$2"
    shift 2
    ( cd "$repo" && MEMORY_DIR="$repo" AI_MEMORY_CHANNEL="$channel" bash scripts/sync-system.sh "$@" )
}

capture_sync_channel() {
    local repo="$1" channel="$2"
    shift 2
    ( cd "$repo" && MEMORY_DIR="$repo" AI_MEMORY_CHANNEL="$channel" bash scripts/sync-system.sh "$@" ) 2>&1
}

run_sync_channel_no_sort_v() {
    local repo="$1" channel="$2"
    shift 2
    ( cd "$repo" && MEMORY_DIR="$repo" AI_MEMORY_CHANNEL="$channel" AI_MEMORY_TEST_NO_SORT_V=1 bash scripts/sync-system.sh "$@" )
}

capture_sync_channel_no_sort_v() {
    local repo="$1" channel="$2"
    shift 2
    ( cd "$repo" && MEMORY_DIR="$repo" AI_MEMORY_CHANNEL="$channel" AI_MEMORY_TEST_NO_SORT_V=1 bash scripts/sync-system.sh "$@" ) 2>&1
}

# --- release/default resolves to latest semver tag ---
R1="$(make_fixture release-default yes)"
out="$(capture_sync_unset "$R1")"
assert_eq "v0.10.0" "$(git -C "$R1" describe --tags --exact-match 2>/dev/null)" "unset channel checks out latest semver tag"
assert_eq "HEAD" "$(git -C "$R1" rev-parse --abbrev-ref HEAD)" "release checkout is detached HEAD"
assert_eq "v0.10.0" "$(cat "$R1/install-ran.txt")" "release path runs install after checkout"
assert_contains "$out" "Checking out release v0.10.0" "release output reports latest tag"

R2="$(make_fixture release-explicit yes)"
run_sync_channel "$R2" release >/dev/null 2>&1
assert_eq "v0.10.0" "$(git -C "$R2" describe --tags --exact-match 2>/dev/null)" "release channel checks out latest semver tag"

R3="$(make_fixture release-fallback-sort yes)"
fallback_out="$(capture_sync_channel_no_sort_v "$R3" release)"
assert_eq "v0.10.0" "$(git -C "$R3" describe --tags --exact-match 2>/dev/null)" "release latest-tag fallback orders semver tags without sort -V"
assert_contains "$fallback_out" "Checking out release v0.10.0" "release fallback reports latest semver tag"

R4="$(make_prerelease_fixture release-ignore-prerelease-sort no)"
prerelease_out="$(capture_sync_channel "$R4" release)"
assert_eq "v1.0.0" "$(git -C "$R4" describe --tags --exact-match 2>/dev/null)" "release discovery ignores prerelease tags with sort -V"
assert_contains "$prerelease_out" "Checking out release v1.0.0" "release prerelease-ignore reports stable target with sort -V"

R5="$(make_prerelease_fixture release-ignore-prerelease-fallback no)"
prerelease_fallback_out="$(capture_sync_channel_no_sort_v "$R5" release)"
assert_eq "v1.0.0" "$(git -C "$R5" describe --tags --exact-match 2>/dev/null)" "release discovery ignores prerelease tags without sort -V"
assert_contains "$prerelease_fallback_out" "Checking out release v1.0.0" "release prerelease-ignore reports stable target without sort -V"

R6="$(make_prerelease_fixture release-stable-next-sort yes)"
stable_next_out="$(capture_sync_channel "$R6" release)"
assert_eq "v1.1.0" "$(git -C "$R6" describe --tags --exact-match 2>/dev/null)" "release discovery chooses newer stable tag with sort -V"
assert_contains "$stable_next_out" "Checking out release v1.1.0" "release newer-stable reports target with sort -V"

R7="$(make_prerelease_fixture release-stable-next-fallback yes)"
stable_next_fallback_out="$(capture_sync_channel_no_sort_v "$R7" release)"
assert_eq "v1.1.0" "$(git -C "$R7" describe --tags --exact-match 2>/dev/null)" "release discovery chooses newer stable tag without sort -V"
assert_contains "$stable_next_fallback_out" "Checking out release v1.1.0" "release newer-stable reports target without sort -V"

# --- dev keeps ff-only branch behavior ---
D1="$(make_fixture dev yes)"
PEER="$ROOT/dev/peer"
git clone -q "$ROOT/dev/origin.git" "$PEER"
git_identity "$PEER"
printf 'remote-dev\n' > "$PEER/VERSION"
git -C "$PEER" add VERSION
git -C "$PEER" commit -q -m "remote dev"
git -C "$PEER" push -q origin main
printf 'export AI_MEMORY_CHANNEL="dev"\n' > "$D1/config.local.sh"
run_sync_unset "$D1" >/dev/null 2>&1
assert_eq "main" "$(git -C "$D1" rev-parse --abbrev-ref HEAD)" "dev channel stays on branch"
assert_eq "$(git -C "$D1" rev-parse origin/main)" "$(git -C "$D1" rev-parse HEAD)" "dev channel fast-forwards to upstream"
if git -C "$D1" describe --tags --exact-match >/dev/null 2>&1; then _bad "dev channel does not checkout a tag"; else _ok "dev channel does not checkout a tag"; fi

# --- invalid channel aborts clearly ---
BAD="$(make_fixture invalid yes)"
set +e
bad_out="$(capture_sync_channel "$BAD" banana)"
bad_rc=$?
set -u
assert_exit 2 "$bad_rc" "invalid channel exits nonzero"
assert_contains "$bad_out" "invalid AI_MEMORY_CHANNEL='banana' (valid: release, dev)" "invalid channel message lists valid values"

# --- --to branch and sha checkout arbitrary refs ---
T1="$(make_fixture to-branch yes)"
run_sync_channel "$T1" release --to trial >/dev/null 2>&1
assert_eq "trial" "$(git -C "$T1" rev-parse --abbrev-ref HEAD)" "--to branch checks out the branch"
assert_eq "trial" "$(cat "$T1/VERSION")" "--to branch reaches branch content"

T2="$(make_fixture to-sha yes)"
sha="$(git -C "$T2" rev-parse trial)"
run_sync_channel "$T2" release --to "$sha" >/dev/null 2>&1
assert_eq "HEAD" "$(git -C "$T2" rev-parse --abbrev-ref HEAD)" "--to sha leaves detached HEAD"
assert_eq "$sha" "$(git -C "$T2" rev-parse HEAD)" "--to sha checks out the requested commit"

T3="$(make_fixture to-tag yes)"
run_sync_channel "$T3" release --to v0.9.0 >/dev/null 2>&1
assert_eq "v0.9.0" "$(git -C "$T3" describe --tags --exact-match 2>/dev/null)" "--to tag checks out the tag"
assert_eq "nine" "$(cat "$T3/VERSION")" "--to tag reaches tag content"

# --- --to is ephemeral; next plain run snaps back to channel default ---
E1="$(make_fixture ephemeral yes)"
run_sync_channel "$E1" release --to trial >/dev/null 2>&1
assert_eq "trial" "$(git -C "$E1" rev-parse --abbrev-ref HEAD)" "--to starts on branch"
run_sync_channel "$E1" release >/dev/null 2>&1
assert_eq "v0.10.0" "$(git -C "$E1" describe --tags --exact-match 2>/dev/null)" "plain sync after --to returns to release tag"
assert_eq "HEAD" "$(git -C "$E1" rev-parse --abbrev-ref HEAD)" "snap-back release checkout is detached"

E2="$(make_fixture ephemeral-dev yes)"
sha="$(git -C "$E2" rev-parse trial)"
run_sync_channel "$E2" dev --to "$sha" >/dev/null 2>&1
assert_eq "HEAD" "$(git -C "$E2" rev-parse --abbrev-ref HEAD)" "--to sha starts detached for dev snap-back"
PEER="$ROOT/ephemeral-dev/peer"
git clone -q "$ROOT/ephemeral-dev/origin.git" "$PEER"
git_identity "$PEER"
printf 'remote-dev-after-detach\n' > "$PEER/VERSION"
git -C "$PEER" add VERSION
git -C "$PEER" commit -q -m "remote dev after detach"
git -C "$PEER" push -q origin main
run_sync_channel "$E2" dev >/dev/null 2>&1
assert_eq "main" "$(git -C "$E2" rev-parse --abbrev-ref HEAD)" "plain dev sync after --to returns to tracking branch"
assert_eq "$(git -C "$E2" rev-parse origin/main)" "$(git -C "$E2" rev-parse HEAD)" "plain dev sync after --to fast-forwards tracking branch"

E3="$(make_branch_fixture ephemeral-dev-trunk trunk)"
git -C "$E3" update-ref -d refs/remotes/origin/HEAD 2>/dev/null || true
sha="$(git -C "$E3" rev-parse HEAD)"
run_sync_channel "$E3" dev --to "$sha" >/dev/null 2>&1
run_sync_channel "$E3" dev >/dev/null 2>&1
assert_eq "trunk" "$(git -C "$E3" rev-parse --abbrev-ref HEAD)" "plain dev sync after detached HEAD recovers non-main default branch without origin HEAD"
assert_eq "$(git -C "$E3" rev-parse origin/trunk)" "$(git -C "$E3" rev-parse HEAD)" "non-main detached recovery lands on origin default branch"

E4="$(make_branch_fixture ephemeral-dev-remote-only trunk)"
git -C "$E4" update-ref -d refs/remotes/origin/HEAD 2>/dev/null || true
sha="$(git -C "$E4" rev-parse HEAD)"
git -C "$E4" checkout -q "$sha"
git -C "$E4" branch -D trunk >/dev/null
run_sync_channel "$E4" dev >/dev/null 2>&1
assert_eq "trunk" "$(git -C "$E4" rev-parse --abbrev-ref HEAD)" "dev detached recovery creates missing local branch from origin default"
assert_eq "origin/trunk" "$(git -C "$E4" rev-parse --abbrev-ref --symbolic-full-name '@{u}')" "recovered local branch tracks origin default"

# --- dirty tracked files abort; untracked files do not ---
DIRTY="$(make_fixture dirty yes)"
printf 'dirty\n' > "$DIRTY/VERSION"
set +e
dirty_out="$(capture_sync_channel "$DIRTY" release)"
dirty_rc=$?
set -u
assert_exit 1 "$dirty_rc" "dirty tracked file aborts"
assert_contains "$dirty_out" "tracked files have local modifications" "dirty abort explains tracked-file guard"
assert_eq "main" "$(git -C "$DIRTY" rev-parse --abbrev-ref HEAD)" "dirty abort happens before checkout"

DIRTY_TO="$(make_fixture dirty-to yes)"
printf 'dirty-to\n' > "$DIRTY_TO/VERSION"
set +e
dirty_to_out="$(capture_sync_channel "$DIRTY_TO" release --to trial)"
dirty_to_rc=$?
set -u
assert_exit 1 "$dirty_to_rc" "dirty tracked file aborts before --to checkout"
assert_contains "$dirty_to_out" "tracked files have local modifications" "dirty --to abort explains tracked-file guard"
assert_eq "main" "$(git -C "$DIRTY_TO" rev-parse --abbrev-ref HEAD)" "dirty --to abort happens before checkout"

UNTRACKED="$(make_fixture untracked yes)"
printf 'scratch\n' > "$UNTRACKED/scratch.txt"
run_sync_channel "$UNTRACKED" release >/dev/null 2>&1
assert_eq "v0.10.0" "$(git -C "$UNTRACKED" describe --tags --exact-match 2>/dev/null)" "untracked files do not block release checkout"

NO_PULL_TO="$(make_fixture no-pull-to yes)"
set +e
no_pull_to_out="$(capture_sync_channel "$NO_PULL_TO" release --to trial --no-pull)"
no_pull_to_rc=$?
set -u
assert_exit 2 "$no_pull_to_rc" "--to with --no-pull is a usage error"
assert_contains "$no_pull_to_out" "--to cannot be combined with --no-pull" "--to --no-pull explains invalid combination"
assert_eq "main" "$(git -C "$NO_PULL_TO" rev-parse --abbrev-ref HEAD)" "--to --no-pull leaves branch unchanged"

# --- no release tags fails actionably ---
NOTAGS="$(make_fixture no-tags no)"
set +e
notags_out="$(capture_sync_channel "$NOTAGS" release)"
notags_rc=$?
set -u
assert_exit 1 "$notags_rc" "release channel without v tags exits nonzero"
assert_contains "$notags_out" "no release tag yet" "no-tag failure explains next action"
assert_contains "$notags_out" "set AI_MEMORY_CHANNEL=dev" "no-tag failure suggests dev channel"

ONLY_RC="$(make_fixture only-rc no)"
git -C "$ONLY_RC" tag v1.1.0-rc.1
set +e
only_rc_out="$(capture_sync_channel "$ONLY_RC" release)"
only_rc_rc=$?
set -u
assert_exit 1 "$only_rc_rc" "release channel with only prerelease v tags exits nonzero"
assert_contains "$only_rc_out" "none are stable release tags matching v<num>.<num>.<num>" "only-prerelease failure uses distinct stable-tag message"
assert_not_contains "$only_rc_out" "no release tag yet" "only-prerelease failure is distinct from no-tag failure"

TO_RC="$(make_prerelease_fixture to-prerelease-tag no)"
run_sync_channel "$TO_RC" release --to v1.1.0-rc.1 >/dev/null 2>&1
assert_eq "v1.1.0-rc.1" "$(git -C "$TO_RC" describe --tags --exact-match 2>/dev/null)" "--to prerelease tag checks out requested prerelease ref"
assert_eq "rc" "$(cat "$TO_RC/VERSION")" "--to prerelease tag reaches prerelease content"

# --- dry-run changes nothing and reports resolved target ---
DRY="$(make_fixture dry yes)"
before_head="$(git -C "$DRY" rev-parse HEAD)"
before_branch="$(git -C "$DRY" rev-parse --abbrev-ref HEAD)"
dry_out="$(capture_sync_channel "$DRY" release --dry-run)"
assert_eq "$before_head" "$(git -C "$DRY" rev-parse HEAD)" "dry-run leaves HEAD unchanged"
assert_eq "$before_branch" "$(git -C "$DRY" rev-parse --abbrev-ref HEAD)" "dry-run leaves branch unchanged"
assert_contains "$dry_out" "channel: release" "dry-run reports channel"
assert_contains "$dry_out" "target: v0.10.0" "dry-run reports resolved target"
if [ ! -f "$DRY/install-ran.txt" ]; then _ok "dry-run does not run install"; else _bad "dry-run does not run install"; fi

DRY_FETCH="$(make_fixture dry-fetch yes)"
PEER="$ROOT/dry-fetch/peer"
git clone -q "$ROOT/dry-fetch/origin.git" "$PEER"
git_identity "$PEER"
printf 'eleven\n' > "$PEER/VERSION"
git -C "$PEER" add VERSION
git -C "$PEER" commit -q -m "v0.11.0"
git -C "$PEER" tag v0.11.0
git -C "$PEER" push -q origin main --tags
dry_fetch_out="$(capture_sync_channel "$DRY_FETCH" release --dry-run)"
assert_contains "$dry_fetch_out" "target: v0.11.0" "release dry-run fetches tags before resolving latest target"
assert_eq "main" "$(git -C "$DRY_FETCH" rev-parse --abbrev-ref HEAD)" "release dry-run fetch leaves branch unchanged"
if [ ! -f "$DRY_FETCH/install-ran.txt" ]; then _ok "release dry-run fetch does not run install"; else _bad "release dry-run fetch does not run install"; fi

DRY_NO_ORIGIN="$(make_fixture dry-no-origin yes)"
git -C "$DRY_NO_ORIGIN" remote remove origin
dry_no_origin_out="$(capture_sync_channel "$DRY_NO_ORIGIN" release --dry-run)"
assert_contains "$dry_no_origin_out" "refs may be stale (offline or no origin)" "dry-run without origin reports stale refs"
assert_contains "$dry_no_origin_out" "[dry-run] using local refs, not checking out, not installing" "dry-run without origin continues with local refs"
assert_eq "main" "$(git -C "$DRY_NO_ORIGIN" rev-parse --abbrev-ref HEAD)" "dry-run without origin leaves branch unchanged"

DRY_DEV="$(make_fixture dry-dev yes)"
PEER="$ROOT/dry-dev/peer"
git clone -q "$ROOT/dry-dev/origin.git" "$PEER"
git_identity "$PEER"
printf 'remote-dry-dev\n' > "$PEER/VERSION"
git -C "$PEER" add VERSION
git -C "$PEER" commit -q -m "remote dry dev"
git -C "$PEER" push -q origin main
before_head="$(git -C "$DRY_DEV" rev-parse HEAD)"
before_branch="$(git -C "$DRY_DEV" rev-parse --abbrev-ref HEAD)"
dry_dev_out="$(capture_sync_channel "$DRY_DEV" dev --dry-run)"
assert_eq "$before_head" "$(git -C "$DRY_DEV" rev-parse HEAD)" "dev dry-run leaves HEAD unchanged"
assert_eq "$before_branch" "$(git -C "$DRY_DEV" rev-parse --abbrev-ref HEAD)" "dev dry-run leaves branch unchanged"
assert_contains "$dry_dev_out" "incoming changes on main:" "dev dry-run prints incoming commit preview"
assert_contains "$dry_dev_out" "remote dry dev" "dev dry-run prints incoming commit subject"
assert_contains "$dry_dev_out" "VERSION |" "dev dry-run prints incoming diffstat"
if [ ! -f "$DRY_DEV/install-ran.txt" ]; then _ok "dev dry-run does not run install"; else _bad "dev dry-run does not run install"; fi

finish
