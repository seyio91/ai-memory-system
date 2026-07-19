#!/usr/bin/env bash
# _lib.sh: resolve_session_key + resolve_working_file.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
ROOT="$(new_sandbox)"
trap 'rm -rf "$MEM" "$ROOT"' EXIT
export MEMORY_DIR="$MEM"

. "$SCRIPTS_DIR/_lib.sh"

project="proj"
mkdir -p "$MEM/projects/$project"

main="$ROOT/main"
worktree="$ROOT/wt-featureB"
nongit="$ROOT/not-a-repo/deep"
mkdir -p "$main" "$nongit"
git -C "$main" init -q
git -C "$main" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm init
git -C "$main" worktree add -q -b featureB "$worktree"

assert_eq "$MEM/projects/$project/working.md" \
    "$(resolve_working_file "$project" "$main")" \
    "main checkout -> base working.md"

assert_eq "$MEM/projects/$project/working.wt-featureB.md" \
    "$(resolve_working_file "$project" "$worktree")" \
    "linked git worktree -> working.<wtname>.md"

# --- marker-free SUBDIRECTORIES: the case that shipped broken ----------------
# Every subdir assertion below this block is shadowed by a .agents/memory-session
# marker written further down, so precedence rule 1 short-circuits and the git
# branch never runs — which is exactly why `working..git.md` shipped. These run
# BEFORE any marker exists, so they exercise the git derivation itself.
#
# git returns --git-dir absolute from a subdir but --git-common-dir relative
# ("../.git", "../../.git"), so comparing them raw flagged every non-root cwd of
# a MAIN checkout as a linked worktree, keyed it on basename(".git") == ".git",
# and produced the literal doubled-dot filename asserted against below.
mkdir -p "$main/sub/deeper" "$worktree/nested/deeper"

for d in "$main/sub" "$main/sub/deeper"; do
    assert_eq "$MEM/projects/$project/working.md" \
        "$(resolve_working_file "$project" "$d")" \
        "main-checkout subdir (${d#"$main"/}) -> base working.md"
done

# Gate the NORMALIZATION directly, not only through its symptom. The key guard
# further down independently rejects ".git", so the subdir assertions above still
# pass with the raw comparison restored — the two controls overlap, and without
# this the normalization would be untested. The predicate itself must hold: in a
# main checkout, the two rev-parse forms name the SAME directory from every cwd.
assert_eq "$(_resolve_git_path "$main" --git-dir)" \
    "$(_resolve_git_path "$main" --git-common-dir)" \
    "main checkout: git-dir == git-common-dir at the root"
assert_eq "$(_resolve_git_path "$main/sub/deeper" --git-dir)" \
    "$(_resolve_git_path "$main/sub/deeper" --git-common-dir)" \
    "main checkout: git-dir == git-common-dir from a subdir (the raw forms differ)"
# ...and must NOT hold in a linked worktree, or the predicate would never key.
assert_not_contains "$(_resolve_git_path "$worktree" --git-dir)$(printf '\037')" \
    "$(_resolve_git_path "$worktree" --git-common-dir)$(printf '\037')" \
    "linked worktree: git-dir differs from git-common-dir"

# Name the exact string that shipped, so a regression is unmistakable.
assert_not_contains "$(resolve_working_file "$project" "$main/sub")" "working..git.md" \
    "main-checkout subdir never yields the doubled-dot working..git.md"
assert_not_contains "$(resolve_working_file "$project" "$main/sub/deeper")" "working.." \
    "no doubled dot at depth 2, where --git-common-dir becomes ../../.git"

# The worktree key must survive depth too — the fix must not overshoot into
# "subdirectories never key".
for d in "$worktree/nested" "$worktree/nested/deeper"; do
    assert_eq "$MEM/projects/$project/working.wt-featureB.md" \
        "$(resolve_working_file "$project" "$d")" \
        "linked-worktree subdir (${d#"$worktree"/}) keeps the worktree key"
done

mkdir -p "$main/.agents"
printf 'Manual Marker\n' > "$main/.agents/memory-session"
assert_eq "$MEM/projects/$project/working.manual-marker.md" \
    "$(resolve_working_file "$project" "$main/subdir")" \
    "memory-session marker -> working.<marker>.md"

mkdir -p "$worktree/.agents" "$worktree/nested"
printf 'Override Key\n' > "$worktree/.agents/memory-session"
assert_eq "$MEM/projects/$project/working.override-key.md" \
    "$(resolve_working_file "$project" "$worktree/nested")" \
    "memory-session marker overrides worktree key"

assert_eq "$MEM/projects/$project/working.md" \
    "$(resolve_working_file "$project" "$nongit")" \
    "no git repo -> base working.md"

printf 'Feature X!/../y\n' > "$main/.agents/memory-session"
assert_eq "$MEM/projects/$project/working.feature-x-y.md" \
    "$(resolve_working_file "$project" "$main")" \
    "marker content is sanitized"

# --- derived-key guard, exercised with a stubbed git ------------------------
# The guard rejects a worktree key that is empty, dot-leading, or holds a path
# separator. `git worktree add` cannot produce those — git rewrites the name
# itself (.hidden-wt lands in .git/worktrees/-hidden-wt) — so the branch is
# unreachable through the real CLI and would ship untested. Stub git to hand the
# resolver the shape it refuses, and confirm it fails SAFE (shared working.md)
# rather than emitting a malformed working..evil.md.
# NOT wrapped in a subshell: assert_* increments counters in the shell it runs
# in, so `( ... )` would print ok/FAIL lines that the summary never counts — a
# failure here would not fail the suite. The stub is torn down with `unset -f`.
fake="$ROOT/fakerepo"
mkdir -p "$fake/.git/worktrees/.evil" "$fake/.git/worktrees/ok-name"
fake_gitdir="$fake/.git/worktrees/.evil"
git() {
    case "$*" in
        *--git-dir*)        printf '%s\n' "$fake_gitdir" ;;
        *--git-common-dir*) printf '%s\n' "$fake/.git" ;;
        *) return 1 ;;
    esac
}

assert_eq "$MEM/projects/$project/working.md" \
    "$(resolve_working_file "$project" "$fake")" \
    "dot-leading derived key is rejected -> shared working.md"

fake_gitdir="$fake/.git/worktrees/ok-name"
assert_eq "$MEM/projects/$project/working.ok-name.md" \
    "$(resolve_working_file "$project" "$fake")" \
    "well-formed derived key still passes the guard"

unset -f git

finish
