#!/usr/bin/env bash
# link-skills.sh — linking, repair, and pruning of dangling store-shaped links.
. "$(dirname "$0")/_assert.sh"

LS="$SCRIPTS_DIR/link-skills.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"

mkdir -p "$MEM/skills/alpha" "$MEM/.skill-cache/beta"
printf '# alpha\n' > "$MEM/skills/alpha/SKILL.md"
printf '# beta\n'  > "$MEM/.skill-cache/beta/SKILL.md"

TARGET="$MEM/target"
mkdir -p "$TARGET"

out="$(bash "$LS" "$TARGET" 2>&1)"
assert_eq "$MEM/skills/alpha" "$(readlink "$TARGET/alpha")" "links a skill from skills/"
assert_eq "$MEM/.skill-cache/beta" "$(readlink "$TARGET/beta")" "links a skill from .skill-cache/"
assert_contains "$out" "0 pruned" "nothing to prune on a clean target"

# A rename or a moved memory tree leaves a link pointing at a path that no
# longer exists — the link loop never revisits it, so prune must catch it.
ln -s "/nonexistent/old/memory/skills/renamed" "$TARGET/renamed"
ln -s "/nonexistent/old/memory/.skill-cache/cached" "$TARGET/cached"

out="$(bash "$LS" "$TARGET" 2>&1)"
assert_contains "$out" "prune: renamed" "prunes a dangling link under skills/"
assert_contains "$out" "prune: cached" "prunes a dangling link under .skill-cache/"
assert_contains "$out" "2 pruned" "counts both prunes"
rc=0; [ -L "$TARGET/renamed" ] || rc=1
assert_exit 1 "$rc" "dangling skills/ link is gone"
rc=0; [ -L "$TARGET/cached" ] || rc=1
assert_exit 1 "$rc" "dangling .skill-cache/ link is gone"
assert_eq "$MEM/skills/alpha" "$(readlink "$TARGET/alpha")" "live links survive a prune pass"

# Conservative guards: shape must match, or the link is left alone.
ln -s "/nonexistent/elsewhere/notaskill" "$TARGET/notaskill"
ln -s "/nonexistent/old/memory/skills/other" "$TARGET/mismatch"

out="$(bash "$LS" "$TARGET" 2>&1)"
assert_contains "$out" "dangles outside a skill store" "warns on a dangling link outside a store"
assert_contains "$out" "dangles to a differently-named target" "warns on a name/target mismatch"
rc=0; [ -L "$TARGET/notaskill" ] || rc=1
assert_exit 0 "$rc" "foreign dangling link is left untouched"
rc=0; [ -L "$TARGET/mismatch" ] || rc=1
assert_exit 0 "$rc" "mismatched dangling link is left untouched"
assert_contains "$out" "0 pruned" "neither guarded link is pruned"

# --dry-run reports but does not remove.
rm "$TARGET/notaskill" "$TARGET/mismatch"
ln -s "/nonexistent/old/memory/skills/ghost" "$TARGET/ghost"

out="$(bash "$LS" --dry-run "$TARGET" 2>&1)"
assert_contains "$out" "prune: ghost" "dry-run reports the prune"
assert_contains "$out" "dry-run" "dry-run is tagged in the summary"
rc=0; [ -L "$TARGET/ghost" ] || rc=1
assert_exit 0 "$rc" "dry-run leaves the dangling link in place"

# A real directory is never removed, dangling-looking name or not.
mkdir -p "$TARGET/realdir"
out="$(bash "$LS" "$TARGET" 2>&1)"
rc=0; [ -d "$TARGET/realdir" ] || rc=1
assert_exit 0 "$rc" "a real directory is never pruned"

finish
