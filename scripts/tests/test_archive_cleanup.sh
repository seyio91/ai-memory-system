#!/usr/bin/env bash
# archive-cleanup.sh: dry-run lists old files, .gitkeep preserved, real delete
# removes them, --days validation, no active project errors without --all-projects.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

# Build a project with old + new archive files.
A="$MEM/projects/proj/archive"
mkdir -p "$A/plans" "$A/todos" "$A/working"
: > "$A/plans/.gitkeep"
old="$A/plans/old-plan.md"; new="$A/todos/recent.md"
printf 'old\n' > "$old"
printf 'new\n' > "$new"
# Age the old file ~40 days (touch -t); keep new file fresh.
touch -t "$(date -v-40d +%Y%m%d%H%M 2>/dev/null || date -d '40 days ago' +%Y%m%d%H%M)" "$old"

# Project resolves only from a cwd marker now (no .active_project fallback).
WORK="$MEM/work"; mkdir -p "$WORK/.agents"; printf 'proj\n' > "$WORK/.agents/memory-project"

# --- dry-run lists old, not new, not gitkeep ---
set +e
OUT=$(cd "$WORK" && bash "$SCRIPTS_DIR/archive-cleanup.sh" --dry-run --days 30 2>&1); CODE=$?
set -e
assert_exit 0 "$CODE" "dry-run exits 0"
assert_contains "$OUT" "old-plan.md" "dry-run lists the old file"
assert_contains "$OUT" "DRY RUN" "dry-run announces itself"
assert_not_contains "$OUT" "recent.md" "dry-run skips fresh file"
assert_file "$old" "dry-run did not delete"

# --- real run deletes old, preserves gitkeep + new ---
set +e
OUT=$(cd "$WORK" && bash "$SCRIPTS_DIR/archive-cleanup.sh" --days 30 2>&1); CODE=$?
set -e
assert_exit 0 "$CODE" "real run exits 0"
[ ! -e "$old" ] && _ok "old file deleted" || _bad "old file deleted"
assert_file "$A/plans/.gitkeep" ".gitkeep preserved"
assert_file "$new" "fresh file preserved"

# --- bad --days -> exit 1 ---
set +e
OUT=$(cd "$WORK" && bash "$SCRIPTS_DIR/archive-cleanup.sh" --days abc 2>&1); CODE=$?
set -e
assert_exit 1 "$CODE" "non-integer --days exits 1"

# --- no marker, no --all-projects -> exit 1 ---
EMPTY="$(new_sandbox)"; export MEMORY_DIR="$EMPTY"
set +e
OUT=$(cd "$EMPTY" && bash "$SCRIPTS_DIR/archive-cleanup.sh" 2>&1); CODE=$?
set -e
assert_exit 1 "$CODE" "no active project exits 1"
rm -rf "$EMPTY"

finish
