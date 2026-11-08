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

# Large multiline payload with agent_id early: grep -q in a pipe would SIGPIPE the writer
# under pipefail and skip the path check (exit 0).
BIG="$(python3 -c 'import sys,json;print(json.dumps({"agent_id":"a1","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":sys.argv[1],"content":"x"*100000},"cwd":sys.argv[2]},indent=2))' "$PROT" "$REPO")"
run "$BIG"
assert_exit 2 "$code" "guard paths: large multiline subagent Write on protected path denied"

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

# --- opencode mode (AI_MEMORY_GUARD_OUTPUT=opencode): execute.before event {tool, input:{command}},
# verdict is one JSON line on stdout, exit 0; the plugin fails closed on anything else.
OCFIX="$SCRIPTS_DIR/tests/fixtures/opencode"
oc_event() { # <tool> [command]
    jq -nc --arg t "$1" --arg c "${2:-}" '{tool:$t, sessionID:"ses_x", agent:"build", input:(if $c=="" then {} else {command:$c} end)}'
}
OC="AI_MEMORY_GUARD_OUTPUT=opencode"

run "$(oc_event shell 'kubectl delete ns foo')" $OC AI_MEMORY_ROLE=task
assert_exit 0 "$code" "guard opencode: deny verdict exits 0"
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: deny-listed shell command is denied"
assert_contains "$(jq -r .reason "$OUT")" "kubectl delete" "guard opencode: deny reason names the rule"

run "$(cat "$OCFIX/execute-before-shell.json")" $OC AI_MEMORY_ROLE=task
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: captured benign shell fixture is allowed (explicit allow)"

run "$(oc_event write)" $OC AI_MEMORY_ROLE=explore
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: explore + write tool is denied"
run "$(oc_event edit)" $OC AI_MEMORY_ROLE=validate
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: validate + edit tool is denied"
run "$(oc_event shell 'echo ok')" $OC AI_MEMORY_ROLE=explore
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: explore + benign shell is denied"
run "$(oc_event read)" $OC AI_MEMORY_ROLE=explore
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: explore + read tool is allowed"
oc_ptool() { # <tool> <input-json> [directory]: tool call with a given input object
    jq -nc --arg t "$1" --argjson i "$2" --arg d "${3:-$REPO}" \
        '{tool:$t, sessionID:"ses_x", agent:"build", directory:$d, input:$i}'
}
run "$(oc_ptool write '{"path":"notes/ordinary.txt","content":"x"}')" $OC AI_MEMORY_ROLE=task
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: task role + write to an ordinary path is allowed"

# protected-path writes through opencode's own tools (v2.2.6: write/edit use input.path, may be relative)
run "$(oc_ptool write '{"path":"projects/x/plans/p.md","content":"x"}')" $OC AI_MEMORY_ROLE=task
assert_exit 0 "$code" "guard opencode: protected-path deny still exits 0"
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: task write to a protected plan path is denied"
assert_contains "$(jq -r .reason "$OUT")" "only via the orchestrator" "guard opencode: protected write reason is the path guard's"
run "$(oc_ptool edit '{"path":"scripts/protected-paths.txt","oldString":"a","newString":"b"}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: task edit of a protected path is denied"
# JSON built outside "$(...)": bash 3.2 mangles \" nested in a quoted command substitution
in_json="$(jq -nc --arg p "$REPO/projects/x/plans/p.md" '{path:$p, content:"x"}')"
run "$(oc_ptool write "$in_json" /elsewhere)" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: absolute protected path is denied regardless of directory"
run "$(oc_ptool shell '{"command":"echo hi > projects/x/plans/p.md"}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: shell redirect into a protected path is denied"
run "$(oc_ptool shell '{"command":"echo hi > notes/ok.txt"}')" $OC AI_MEMORY_ROLE=task
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: shell redirect into an ordinary path is allowed"
run "$(oc_ptool write '{"content":"x"}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: write with no path field is denied (fail closed)"
run "$(oc_ptool edit '{}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: edit with no path field is denied (fail closed)"
run "$(oc_ptool apply_patch '{"patchText":"*** Begin Patch\n*** Add File: projects/x/plans/p.md\n+x\n*** End Patch"}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: patch tool adding a protected path is denied"
run "$(oc_ptool apply_patch '{"patchText":"*** Begin Patch\n*** Add File: notes/a.md\n+x\n*** End Patch"}')" $OC AI_MEMORY_ROLE=task
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: patch tool on an ordinary path is allowed"
run "$(oc_ptool apply_patch '{}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: patch tool with no patch text is denied"
run "$(oc_ptool write '{"path":"projects/x/plans/p.md"}')" $OC
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: no role, no scope: protected write is not guarded (main session)"
run "$(oc_event write)" $OC
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: no role, no scope: unguarded allow"

run 'not json at all' $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: malformed input is denied (role set)"
run 'not json at all' $OC
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: malformed input is denied (no role)"
run '{"sessionID":"ses_x","input":{"command":"kubectl delete ns foo"}}' $OC
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: event without a tool name is denied"

# --- fix round 1 ---
# B1: shell input.workdir is the cwd for relative targets (event directory is elsewhere)
oc_wd() { # <workdir> <command> [directory]
    jq -nc --arg w "$1" --arg c "$2" --arg d "${3:-/tmp}" \
        '{tool:"shell", sessionID:"ses_x", agent:"build", directory:$d, input:{command:$c, workdir:$w}}'
}
run "$(oc_wd "$REPO/scripts" 'printf x > deny-list.txt')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: shell workdir=<repo>/scripts, relative redirect into deny-list.txt is denied"
run "$(oc_wd scripts 'printf x > deny-list.txt' "$REPO")" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: relative workdir resolves against the event directory"
run "$(oc_wd /tmp 'printf x > deny-list.txt')" $OC AI_MEMORY_ROLE=task
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: same command with an unrelated workdir is allowed"

# B2: enforcement/injection files are protected from task writes
for rel in harnesses/opencode/hooks/context.sh harnesses/opencode/plugin/ai-memory.ts harnesses/opencode/scripts/opencode-mem.sh; do
    in_json="$(jq -nc --arg p "$rel" '{path:$p, content:"exit 0"}')"
    run "$(oc_ptool write "$in_json")" $OC AI_MEMORY_ROLE=task
    assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: task write to $rel is denied"
done
OCHOME="$TMP/home"; mkdir -p "$OCHOME"
in_json="$(jq -nc --arg p "$OCHOME/.config/opencode/plugins/x.ts" '{path:$p, content:"x"}')"
run "$(oc_ptool write "$in_json" /elsewhere)" $OC AI_MEMORY_ROLE=task HOME="$OCHOME"
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: task write to ~/.config/opencode/plugins/x.ts is denied"
in_json="$(jq -nc --arg p "$OCHOME/.config/opencode/agents/x.md" '{path:$p, content:"x"}')"
run "$(oc_ptool write "$in_json" /elsewhere)" $OC AI_MEMORY_ROLE=task HOME="$OCHOME"
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: task write to ~/.config/opencode/agents/x.md is denied"

# B4c: Code Mode / state-mutating / child-session tools are denied under any guarded role
for role in task explore validate; do
    for t in execute opencode_worktree_create worktree_remove opencode_artifact_publish artifact_write opencode_schedule_create schedule_run subagent opencode_subagent my_subagent_run; do
        run "$(oc_ptool "$t" '{}')" $OC AI_MEMORY_ROLE=$role
        assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: $role + $t is denied"
    done
done
run "$(oc_ptool execute '{"code":"1"}')" $OC AI_MEMORY_ROLE=task
assert_contains "$(jq -r .reason "$OUT")" "Code Mode" "guard opencode: execute denial reason names Code Mode"
run "$(oc_ptool execute '{"code":"1"}')" $OC
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: no role: execute is not guarded (main session)"
run "$(oc_ptool some_mcp_server_lookup '{"q":"x"}')" $OC AI_MEMORY_ROLE=task
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: task role + unknown MCP-style tool stays allowed"
run "$(oc_ptool some_mcp_server_lookup '{"q":"x"}')" $OC AI_MEMORY_ROLE=explore
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: explore role + MCP-style tool stays denied (allowlist)"

# fix round 4: session move/rename would leave the directory holding a project-local plugin
for role in task explore validate; do
    for t in opencode_session_move session_rename opencode_session_fork OPENCODE_SESSION_MOVE Session_Delete; do
        run "$(oc_ptool "$t" '{"directory":"/elsewhere"}')" $OC AI_MEMORY_ROLE=$role
        assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: $role + $t is denied"
    done
done
run "$(oc_ptool opencode_session_move '{"directory":"/elsewhere"}')" $OC AI_MEMORY_ROLE=task
assert_contains "$(jq -r .reason "$OUT")" "session" "guard opencode: session denial reason names the session tool"
run "$(oc_ptool opencode_session_move '{"directory":"/elsewhere"}')" $OC
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: no role: session move is not guarded (main session)"

# fix round 4: experimental_image_generate writes input.path (protected-path check applies)
run "$(oc_ptool experimental_image_generate '{"prompt":"x","path":"projects/x/plans/p.png"}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: image_generate to a protected plan path is denied"
run "$(oc_ptool experimental_image_generate '{"prompt":"x","filePath":"projects/x/plans/p.png"}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: image_generate filePath to a protected plan path is denied"
run "$(oc_ptool experimental_image_generate '{"prompt":"x","path":"notes/p.png"}')" $OC AI_MEMORY_ROLE=task
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: image_generate to an ordinary path is allowed"
run "$(oc_ptool experimental_image_generate '{"prompt":"x"}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: image_generate with no path is denied (fail closed)"

# fix round 4: tool-name matching is case-insensitive everywhere
run "$(oc_event Shell 'terraform destroy')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: Shell + terraform destroy is denied"
run "$(oc_event BASH 'terraform destroy')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: BASH + terraform destroy is denied"

# B4d: patch tool (spike: `patch` with `patchText`) is guarded under both names
run "$(oc_ptool patch '{"patchText":"*** Begin Patch\n*** Add File: projects/x/plans/p.md\n+x\n*** End Patch"}')" $OC AI_MEMORY_ROLE=task
assert_eq deny "$(jq -r .decision "$OUT")" "guard opencode: patch tool (patchText) adding a protected path is denied"
run "$(oc_ptool patch '{"patchText":"*** Begin Patch\n*** Add File: notes/a.md\n+x\n*** End Patch"}')" $OC AI_MEMORY_ROLE=task
assert_eq allow "$(jq -r .decision "$OUT")" "guard opencode: patch tool (patchText) on an ordinary path is allowed"

finish
