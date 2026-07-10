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

finish
