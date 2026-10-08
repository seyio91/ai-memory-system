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
case "$CONTENT" in
    *run_in_background*|*background*) _ok "background-task rule for --run present" ;;
    *) _bad "background-task rule for --run present" ;;
esac

# "Small items inline" must be gone from the always-injected base.
assert_not_contains "$CONTENT" "Small items inline" "'Small items inline' text absent"

finish
