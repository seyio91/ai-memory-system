#!/usr/bin/env bash
# guard.sh end to end: guarded-context writes to protected paths are denied
# before the scope early-exit; the main session is never affected.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd -P)"
GUARD="$REPO/scripts/hooks/guard.sh"
FIX="$SCRIPTS_DIR/tests/fixtures/codex/pre_tool_use_apply_patch.json"
. "$REPO/scripts/jsonutil.sh"

TMP="$(new_sandbox)"
trap 'rm -rf "$TMP"' EXIT
OUT="$TMP/out"
ERR="$TMP/err"
unset AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE AI_MEMORY_GUARD_OUTPUT

edit_in() { # <path> [agent_id]
    local extra=""
    [ -z "${2:-}" ] || extra=",\"agent_id\":\"$2\""
    printf '{"hook_event_name":"PreToolUse","tool_name":"Edit","tool_input":{"file_path":%s},"cwd":%s%s}' \
        "$(json_escape "$1")" "$(json_escape "$REPO")" "$extra"
}

run() { # <json> [env assignments...]
    local json="$1"
    shift
    set +e
    printf '%s' "$json" | env -u AI_MEMORY_ROLE -u AI_MEMORY_GUARD_SCOPE -u AI_MEMORY_GUARD_OUTPUT "$@" bash "$GUARD" >"$OUT" 2>"$ERR"
    code=$?
    set -e
}

PROT="$REPO/scripts/hooks/guard.sh"
PLAN="$REPO/projects/ai-memory/plans/executor-protected-paths.md"

run "$(edit_in "$PROT" a1)" AI_MEMORY_GUARD_SCOPE=all
assert_exit 2 "$code" "guard paths: subagent Edit on protected path exits 2"
assert_contains "$(cat "$ERR")" "only via the orchestrator" "guard paths: deny carries the route text"

run "$(edit_in "$PLAN" a1)" AI_MEMORY_GUARD_SCOPE=executor
assert_exit 2 "$code" "guard paths: subagent Edit on a plan exits 2 (scope=executor)"

run "$(edit_in "$PROT" a1)"
assert_exit 2 "$code" "guard paths: R4 subagent Edit denied with AI_MEMORY_GUARD_SCOPE unset"

run "$(edit_in "$PROT")" AI_MEMORY_GUARD_SCOPE=all
assert_exit 0 "$code" "guard paths: main session Edit on protected path exits 0"
assert_eq "" "$(cat "$OUT" "$ERR")" "guard paths: main session Edit prints nothing"

run "$(edit_in "$PROT")"
assert_exit 0 "$code" "guard paths: main session, scope unset, exits 0"

run "$(edit_in "$TMP/ok.txt" a1)" AI_MEMORY_GUARD_SCOPE=all
assert_exit 0 "$code" "guard paths: subagent Edit on unprotected path exits 0"

run "$(edit_in "$PROT")" AI_MEMORY_ROLE=task
assert_exit 2 "$code" "guard paths: role-set Edit on protected path exits 2"

patch="$(jq -r .tool_input.command "$FIX" | sed "s|^\*\*\* Update File: b.txt|*** Update File: $REPO/scripts/deny-list.txt|")"
codex_in="$(jq -c --arg p "$patch" --arg c "$REPO" '.tool_input.command = $p | .cwd = $c' "$FIX")"
run "$codex_in" AI_MEMORY_ROLE=task
assert_exit 2 "$code" "guard paths: Codex apply_patch fixture with protected target under role exits 2"
assert_contains "$(cat "$ERR")" "only via the orchestrator" "guard paths: Codex deny carries the route text"

benign="$(jq -c --arg c "$TMP" '.cwd = $c' "$FIX")"
run "$benign" AI_MEMORY_ROLE=task
assert_exit 0 "$code" "guard paths: Codex apply_patch fixture with unprotected targets exits 0"

run "$(edit_in "$PROT" a1)" AI_MEMORY_GUARD_SCOPE=all AI_MEMORY_GUARD_OUTPUT=copilot-json
assert_exit 0 "$code" "guard paths: Copilot deny exits 0"
assert_contains "$(cat "$OUT")" '"permissionDecision":"deny"' "guard paths: Copilot deny emits the JSON envelope"
assert_contains "$(cat "$OUT")" "only via the orchestrator" "guard paths: Copilot envelope carries the route text"

# The live root is usually reached through a symlink (~/.claude-memory) and the guard may run
# with a PATH lacking readlink; resolving the root must not kill guard.sh (exit 1 = fail open).
ln -s "$REPO" "$TMP/rootlink"
MINBIN="$TMP/minbin"
mkdir -p "$MINBIN"
for prog in dirname cat grep sed awk python3 jq; do
    src="$(command -v "$prog" 2>/dev/null)" && ln -sf "$src" "$MINBIN/$prog"
done
set +e
edit_in "$PROT" a1 | env -i PATH="$MINBIN" HOME="$HOME" "$(command -v bash)" "$TMP/rootlink/scripts/hooks/guard.sh" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 2 "$code" "guard paths: symlinked root, no readlink on PATH, protected Edit still denied"
assert_contains "$(cat "$ERR")" "only via the orchestrator" "guard paths: symlinked root, no readlink, reason is the path guard's"

finish
