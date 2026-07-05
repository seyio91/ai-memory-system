#!/usr/bin/env bash
# migrate-marker.sh: walk each project's reverse map, move a legacy
# .claude/memory-project to the neutral .agents/memory-project. Dry-run by
# default; --apply performs it; idempotent.
. "$(dirname "$0")/_assert.sh"

MIG="$SCRIPTS_DIR/migrate-marker.sh"

MEM="$(new_sandbox)"; CO="$(new_sandbox)"
trap 'rm -rf "$MEM" "$CO"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

# project 'alpha' pinned (via repo_path) to a checkout carrying the legacy marker
mkdir -p "$MEM/projects/alpha"
cat > "$MEM/projects/alpha/memory.md" <<EOF
---
topic: alpha
scope: project
repo_path: $CO/alpha
summary: s
---
# Project: alpha
EOF
mkdir -p "$CO/alpha/.claude"; printf 'alpha\n' > "$CO/alpha/.claude/memory-project"

# --- dry-run: reports, changes nothing ---
out="$(bash "$MIG" 2>&1)"
assert_contains "$out" "migrate" "dry-run lists the migration"
assert_contains "$out" "Re-run with --apply" "dry-run prompts for --apply"
assert_file "$CO/alpha/.claude/memory-project" "dry-run leaves the legacy marker"
if [ ! -f "$CO/alpha/.agents/memory-project" ]; then _ok "dry-run creates nothing"; else _bad "dry-run creates nothing"; fi

# --- apply: migrates ---
bash "$MIG" --apply >/dev/null 2>&1
assert_file "$CO/alpha/.agents/memory-project" "apply creates the neutral marker"
assert_eq "alpha" "$(cat "$CO/alpha/.agents/memory-project")" "neutral marker keeps the project slug"
if [ ! -f "$CO/alpha/.claude/memory-project" ]; then _ok "apply removes the legacy marker"; else _bad "apply removes the legacy marker"; fi

# --- idempotent re-run: already neutral ---
out="$(bash "$MIG" --apply 2>&1)"
assert_contains "$out" "1 already-neutral" "re-run counts the checkout as already-neutral"

# --- stale legacy alongside neutral is deduped ---
printf 'alpha\n' > "$CO/alpha/.claude/memory-project"
bash "$MIG" --apply >/dev/null 2>&1
if [ ! -f "$CO/alpha/.claude/memory-project" ]; then _ok "apply removes a stale legacy marker next to the neutral one"; else _bad "apply removes a stale legacy marker"; fi

finish
