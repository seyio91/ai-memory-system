#!/usr/bin/env bash
# Pins the dedupe of the always-injected orchestrator doctrine: the tracked core
# (doctrine/orchestrator.md) must stay under a byte ceiling and must state each
# deduped rule exactly once. See projects/ai-memory/plans/dedupe-always-injected-base.md.
. "$(dirname "$0")/_assert.sh"
set -euo pipefail

REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"

# ORCH_CORE_FILE lets the mutation check point this test at a scratch copy
# instead of the real file.
CORE_FILE="${ORCH_CORE_FILE:-$REPO_ROOT/doctrine/orchestrator.md}"

# Byte ceiling pins the dedupe (plan: Phase 1 size gate). Raise only deliberately,
# after re-measuring that the core still needs the extra room.
MAX_BYTES=14336

assert_file "$CORE_FILE" "doctrine/orchestrator.md exists"

SIZE="$(wc -c < "$CORE_FILE" | tr -d ' ')"
if [ "$SIZE" -le "$MAX_BYTES" ]; then
    _ok "doctrine/orchestrator.md is <= $MAX_BYTES bytes (got $SIZE)"
else
    _bad "doctrine/orchestrator.md is <= $MAX_BYTES bytes (got $SIZE)"
fi

grep_once() {
    # grep_once <pattern> <label>
    local pattern="$1" label="$2" count
    count="$(grep -c -- "$pattern" "$CORE_FILE" || true)"
    assert_eq "1" "$count" "$label"
}

# Deny-list stated exactly once: anchor on a line carrying both a destructive
# terraform verb and a destructive helm verb (deliberately distinctive — unlikely
# to appear in any other prose in this file).
grep_once "terraform destroy" "deny-list statement present exactly once (terraform destroy anchor)"
grep_once "helm upgrade" "deny-list statement present exactly once (helm upgrade anchor)"

# Three task tiers stated exactly once.
grep_once "Three task tiers" "three task tiers header present exactly once"

# TaskCreate ban stated exactly once.
grep_once "Never use the harness" "TaskCreate/TaskUpdate ban present exactly once"

# Archive rule stated exactly once.
grep_once "Archive is never read unless the user explicitly asks" "archive rule present exactly once"

# Headings cited by commands/docs must keep their exact names.
assert_contains "$(cat "$CORE_FILE")" "## Orchestration" "## Orchestration heading present"
assert_contains "$(cat "$CORE_FILE")" "Brainstorm gate" "Brainstorm gate label present"
assert_contains "$(cat "$CORE_FILE")" "### Task Contract" "### Task Contract heading present"
assert_contains "$(cat "$CORE_FILE")" "## Cross-project relationships" "## Cross-project relationships heading present"
assert_contains "$(cat "$CORE_FILE")" "## Memory maintenance" "## Memory maintenance heading present"

# Validator brief fields and the executor decision-tree / background rule must
# survive the dedupe pass (load-bearing per the plan).
assert_contains "$(cat "$CORE_FILE")" "scope:" "validator brief field scope: present"
assert_contains "$(cat "$CORE_FILE")" "risk:" "validator brief field risk: present"
assert_contains "$(cat "$CORE_FILE")" "hypotheses:" "validator brief field hypotheses: present"
assert_contains "$(cat "$CORE_FILE")" "--which" "executor.sh --which decision tree present"

CONTENT="$(cat "$CORE_FILE")"
# Assert the SPECIFIC rule, not any mention of "background": a line that
# names both `--run` and background execution (`run_in_background` or the
# bare word) — the generic dispatch instruction, not an unrelated mention.
if grep -E -- '--run' "$CORE_FILE" | grep -q -- 'background'; then
    _ok "background-task rule for --run present"
else
    _bad "background-task rule for --run present"
fi

# "Small items inline" must be gone from the always-injected base.
assert_not_contains "$CONTENT" "Small items inline" "'Small items inline' text absent"

# --- Migration: migrations/1.6.0-orchestrator-core-overlay.sh -------------
# Named here (not a sibling file) so run-tests.sh --changed maps a change to
# the migration back to this test via its reference-grep fallback: the literal
# basename below satisfies that lookup.
MIGRATION="$REPO_ROOT/migrations/1.6.0-orchestrator-core-overlay.sh"
assert_file "$MIGRATION" "migrations/1.6.0-orchestrator-core-overlay.sh exists"

run_migration() {
    # run_migration <memory_dir> -- runs with a fresh MEMORY_DIR/REPO_ROOT env.
    MEMORY_DIR="$1" REPO_ROOT="$REPO_ROOT" bash "$MIGRATION"
}

tree_cksums() {
    # tree_cksums <dir> -- sorted cksum listing of every file, relative paths.
    # Plain sort + cksum (no GNU-only -z/-print0) to stay bash-3.2/macOS safe.
    ( cd "$1" && find . -type f | sort | xargs cksum )
}

# (a) full-copy root orchestrator.md, no overlay.
MDA="$(new_sandbox)"
printf '# My Orchestrator\n\nFull copy of the old template, hand-edited.\n' > "$MDA/orchestrator.md"
cp "$MDA/orchestrator.md" "$MDA/orchestrator.md.orig-for-test"
out_a="$(run_migration "$MDA")"
assert_file "$MDA/orchestrator.md.pre-1.6.0" "(a) backup created"
if cmp -s "$MDA/orchestrator.md.pre-1.6.0" "$MDA/orchestrator.md.orig-for-test"; then
    _ok "(a) backup bytes match the original root file"
else
    _bad "(a) backup bytes match the original root file"
fi
assert_not_file "$MDA/orchestrator.md" "(a) root orchestrator.md gone after migration"
assert_file "$MDA/orchestrator.local.md" "(a) orchestrator.local.md created"
assert_eq "" "$(cat "$MDA/orchestrator.local.md")" "(a) orchestrator.local.md seeded empty (zero bytes)"
assert_contains "$out_a" "port any personal rules" "(a) migration prints a porting notice"
assert_contains "$out_a" "$MDA/orchestrator.md.pre-1.6.0" "(a) notice names the backup path"

before_a="$(tree_cksums "$MDA")"
run_migration "$MDA" >/dev/null
after_a="$(tree_cksums "$MDA")"
assert_eq "$before_a" "$after_a" "(a) running the migration again yields an identical tree"
rm -rf "$MDA"

# (b) existing overlay with content + root file -> overlay is never overwritten.
MDB="$(new_sandbox)"
printf '# legacy\n' > "$MDB/orchestrator.md"
printf '# my personal overlay\ngit-cli rule here\n' > "$MDB/orchestrator.local.md"
cp "$MDB/orchestrator.local.md" "$MDB/orchestrator.local.md.orig-for-test"
run_migration "$MDB" >/dev/null
if cmp -s "$MDB/orchestrator.local.md" "$MDB/orchestrator.local.md.orig-for-test"; then
    _ok "(b) existing overlay with content is byte-identical after the migration"
else
    _bad "(b) existing overlay with content is byte-identical after the migration"
fi
rm -rf "$MDB"

# (c) existing backup + root file (rollback-then-resync) -> backup never clobbered.
MDC="$(new_sandbox)"
printf '# legacy current\n' > "$MDC/orchestrator.md"
printf '# pre-existing backup from an earlier migration run\n' > "$MDC/orchestrator.md.pre-1.6.0"
cp "$MDC/orchestrator.md.pre-1.6.0" "$MDC/orchestrator.md.pre-1.6.0.orig-for-test"
cp "$MDC/orchestrator.md"           "$MDC/orchestrator.md.orig-for-test"
set +e
out_c="$(run_migration "$MDC")"; rc_c=$?
set -e
assert_exit 0 "$rc_c" "(c) existing backup + root file: migration exits 0"
if cmp -s "$MDC/orchestrator.md.pre-1.6.0" "$MDC/orchestrator.md.pre-1.6.0.orig-for-test"; then
    _ok "(c) existing backup is byte-identical (never clobbered)"
else
    _bad "(c) existing backup is byte-identical (never clobbered)"
fi
if cmp -s "$MDC/orchestrator.md" "$MDC/orchestrator.md.orig-for-test"; then
    _ok "(c) root orchestrator.md is still present and untouched"
else
    _bad "(c) root orchestrator.md is still present and untouched"
fi
assert_contains "$out_c" "already exists" "(c) migration prints a notice about the pre-existing backup"
rm -rf "$MDC"

# (d) nothing present -> only an empty overlay is created.
MDD="$(new_sandbox)"
set +e
out_d="$(run_migration "$MDD")"; rc_d=$?
set -e
assert_exit 0 "$rc_d" "(d) empty tree: migration exits 0"
assert_file "$MDD/orchestrator.local.md" "(d) orchestrator.local.md created"
assert_eq "" "$(cat "$MDD/orchestrator.local.md")" "(d) orchestrator.local.md seeded empty"
assert_not_file "$MDD/orchestrator.md" "(d) no root orchestrator.md created"
assert_not_file "$MDD/orchestrator.md.pre-1.6.0" "(d) no backup created (nothing to back up)"
rm -rf "$MDD"

finish
