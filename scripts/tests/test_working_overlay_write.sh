#!/usr/bin/env bash
# Write path of the per-worktree working.md overlay: the Codex checkpoint writer
# (codex-mem-checkpoint.sh) must target working.<key>.md in a linked worktree,
# seed a fresh overlay, refuse a missing BASE working.md, and keep two worktrees
# fully isolated. --for-codex mode is used (deterministic, no TTY/editor needed);
# it drives the same WORKING target as interactive mode and runs the seeding.
. "$(dirname "$0")/_assert.sh"

if ! command -v git >/dev/null 2>&1; then
    printf '  SKIP git not available\n'; finish
fi

CK="$SCRIPTS_DIR/../harnesses/codex/scripts/codex-mem-checkpoint.sh"
if [ ! -f "$CK" ]; then
    printf '  SKIP %s not found\n' "$CK"; finish
fi

MEM="$(new_sandbox)"; ROOT="$(new_sandbox)"
trap 'rm -rf "$MEM" "$ROOT"' EXIT
export MEMORY_DIR="$MEM"
mkdir -p "$MEM/projects/proj"
printf '# Working\n\nBASE-SCRATCH\n' > "$MEM/projects/proj/working.md"

# A repo with two linked worktrees, each marked to project "proj".
git -C "$ROOT" init -q
git -C "$ROOT" -c user.name=T -c user.email=t@e commit --allow-empty -qm init
git -C "$ROOT" worktree add -q -b fa "$ROOT/wt-a" 2>/dev/null
git -C "$ROOT" worktree add -q -b fb "$ROOT/wt-b" 2>/dev/null
for w in "$ROOT/wt-a" "$ROOT/wt-b" "$ROOT"; do
    mkdir -p "$w/.agents"; printf 'proj\n' > "$w/.agents/memory-project"
done

run_ck() { ( cd "$1" && bash "$CK" --for-codex ); }

# --- worktree with no overlay yet: resolves to working.<wt>.md, seeds it ---
out="$(run_ck "$ROOT/wt-a")"
assert_contains "$out" "WORKING_MD: $MEM/projects/proj/working.wt-a.md" \
    "codex checkpoint targets the worktree overlay"
assert_file "$MEM/projects/proj/working.wt-a.md" "fresh overlay seeded on first checkpoint"
assert_contains "$(cat "$MEM/projects/proj/working.md")" "BASE-SCRATCH" \
    "base working.md untouched by a worktree checkpoint"

# --- main checkout: targets the base working.md (which exists) ---
out="$(run_ck "$ROOT")"
assert_contains "$out" "WORKING_MD: $MEM/projects/proj/working.md" \
    "main checkout checkpoint targets base working.md"

# --- base working.md missing in a MAIN checkout -> hard error (real signal) ---
MEM2="$(new_sandbox)"; mkdir -p "$MEM2/projects/proj"
mkdir -p "$ROOT/.agents"
set +e
out="$( cd "$ROOT" && MEMORY_DIR="$MEM2" bash "$CK" --for-codex 2>&1 )"; code=$?
set -e
assert_exit 1 "$code" "missing base working.md in main checkout exits non-zero"
assert_contains "$out" "working.md not found" "…with an explanatory message"
rm -rf "$MEM2"

# --- isolation: two worktrees, two overlays, no cross-write ---
run_ck "$ROOT/wt-b" >/dev/null
printf 'A-ONLY\n' >> "$MEM/projects/proj/working.wt-a.md"
printf 'B-ONLY\n' >> "$MEM/projects/proj/working.wt-b.md"
assert_contains     "$(cat "$MEM/projects/proj/working.wt-a.md")" "A-ONLY" "wt-a overlay holds its own note"
assert_not_contains "$(cat "$MEM/projects/proj/working.wt-a.md")" "B-ONLY" "wt-a overlay free of wt-b's note"
assert_not_contains "$(cat "$MEM/projects/proj/working.wt-b.md")" "A-ONLY" "wt-b overlay free of wt-a's note"

finish
