#!/usr/bin/env bash
# Shared hook scripts: format-param rendering, Claude XML payload equivalence,
# and exit-2 infra guard behavior.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
SHARED_INJECT="$REPO/scripts/hooks/inject.sh"
SHARED_GUARD="$REPO/scripts/hooks/guard.sh"

MEM="$(new_sandbox)"
WORK="$(new_sandbox)"
OLD_REPO="$(new_sandbox)"
trap 'rm -rf "$MEM" "$WORK" "$OLD_REPO"' EXIT
export MEMORY_DIR="$MEM"

seed_min_tree "$MEM"
mkdir -p "$MEM/doctrine"
printf '# Orchestrator\n\nORCH-MARKER\n' > "$MEM/doctrine/orchestrator.md"
mkdir -p "$MEM/projects/proj" "$WORK/.agents" "$WORK/sub"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOF
printf 'proj\n' > "$WORK/.agents/memory-project"

. "$REPO/scripts/hooks/lib.sh"
. "$REPO/scripts/_lib.sh"
. "$REPO/scripts/formatters/md.sh"

export AI_MEMORY_CWD="$WORK/sub"
crumb="$(content_sections proj identity orchestrator project index working | md_render_breadcrumb proj "$WORK/sub")"
assert_contains "$crumb" "project: proj" "md breadcrumb: active project"
assert_contains "$crumb" "orchestrator: $MEM/doctrine/orchestrator.md" "md breadcrumb: orchestrator path"
assert_contains "$crumb" "working.md"    "md breadcrumb: working write target"
assert_contains "$crumb" "$MEM/projects/proj/working.md" "md breadcrumb: advertises absent working path"

printf '# Working\n\nSHARED-HOOK-SCRATCH\n' > "$MEM/projects/proj/working.md"

xml_full="$(AI_MEMORY_HOOK_FORMAT=xml render_full proj)"
assert_contains "$xml_full" "<memory:orchestrator>" "xml full: orchestrator section rendered"
case "$xml_full" in
    *"<memory:identity>"*"<memory:orchestrator>"*"<memory:project name=\"proj\">"*) _ok "xml full: orchestrator is after identity before project" ;;
    *) _bad "xml full: orchestrator is after identity before project" ;;
esac
md_full="$(AI_MEMORY_HOOK_FORMAT=md render_full proj)"
assert_contains "$md_full" "# === ORCHESTRATOR ===" "md full: orchestrator heading rendered"
case "$md_full" in
    *"# === IDENTITY ==="*"# === ORCHESTRATOR ==="*"# === PROJECT: proj ==="*) _ok "md full: orchestrator is after identity before project" ;;
    *) _bad "md full: orchestrator is after identity before project" ;;
esac

# The parity oracle uses FROZEN pre-migration copies vendored under
# scripts/tests/fixtures/claude-legacy-hooks/ — NOT `git show HEAD:...`, which
# only resolves the old files while the migration is uncommitted (once P3 is
# committed/merged, HEAD no longer carries them and the oracle would silently
# read empty and the parity tests would fail on committed code / in CI).
# Pre-migration hooks never emitted the (post-freeze) orchestrator section, so
# the parity block runs against a tree without doctrine/orchestrator.md — which
# doubles as the backward-compat proof for the pre-core-overlay code path.
# The section's own rendering is asserted independently above and below.
mv "$MEM/doctrine/orchestrator.md" "$MEM/doctrine/orchestrator.md.aside"
LEGACY="$REPO/scripts/tests/fixtures/claude-legacy-hooks"
stage_old_claude_hooks() {
    mkdir -p "$OLD_REPO/harnesses/claude/hooks" "$OLD_REPO/scripts/formatters"
    cp "$LEGACY/inject_memory.sh"        "$OLD_REPO/harnesses/claude/hooks/inject_memory.sh"
    cp "$LEGACY/session_start_memory.sh" "$OLD_REPO/harnesses/claude/hooks/session_start_memory.sh"
    cp "$LEGACY/memory_common.sh"        "$OLD_REPO/harnesses/claude/hooks/memory_common.sh"
    cp "$REPO/scripts/content-core.sh" "$OLD_REPO/scripts/content-core.sh"
    cp "$REPO/scripts/formatters/xml.sh" "$OLD_REPO/scripts/formatters/xml.sh"
    chmod +x "$OLD_REPO/harnesses/claude/hooks/"*.sh
}

stage_old_claude_hooks
CLAUDE_INJECT="$OLD_REPO/harnesses/claude/hooks/inject_memory.sh"
OLD_SESSION="$OLD_REPO/harnesses/claude/hooks/session_start_memory.sh"
NEW_SESSION="$REPO/scripts/hooks/session_start_memory.sh"

json_payload() {
    local prompt="$1" cwd="$2" session="${3:-}"
    printf '{"prompt":"%s","cwd":"%s","session_id":"%s"}' "$prompt" "$cwd" "$session"
}

additional_context() {
    python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"], end="")'
}

compare_xml_context() {
    local label="$1" payload="$2" shared claude
    shared="$(printf '%s' "$payload" | AI_MEMORY_HOOK_FORMAT=xml bash "$SHARED_INJECT")"
    claude="$(printf '%s' "$payload" | bash "$CLAUDE_INJECT")"
    shared="$(printf '%s' "$shared" | additional_context)"
    claude="$(printf '%s' "$claude" | additional_context)"
    assert_eq "$claude" "$shared" "$label"
}

if command -v python3 >/dev/null 2>&1; then
    # Parity with the frozen pre-migration Claude hook is asserted on the payload
    # WITHOUT a session_id: that is the pre-session-pin feature set, and it must
    # stay byte-identical forever. The legacy fixture is a reference snapshot and
    # is never edited to match new behaviour — that would defeat its purpose.
    compare_xml_context "shared xml inject: breadcrumb matches Claude payload" "$(json_payload "hi" "$WORK/sub" "")"
    compare_xml_context "shared xml inject: @memory full matches Claude payload" "$(json_payload "reload @memory" "$WORK" "")"

    # With a session_id the shared hook adds exactly one line — the session
    # pointer /pin needs — immediately after the opening tag, and changes nothing
    # else. Asserted as legacy-plus-one-line rather than by eyeballing a literal,
    # so any OTHER drift from the legacy bytes still fails here.
    sess_payload="$(json_payload "hi" "$WORK/sub" "s1")"
    sess_shared="$(printf '%s' "$sess_payload" | AI_MEMORY_HOOK_FORMAT=xml bash "$SHARED_INJECT" | additional_context)"
    sess_legacy="$(printf '%s' "$(json_payload "hi" "$WORK/sub" "")" | bash "$CLAUDE_INJECT" | additional_context)"
    sess_expected="$(printf '%s' "$sess_legacy" | awk 'NR==1 {print; print "session: s1"; next} {print}')"
    assert_eq "$sess_expected" "$sess_shared" "shared xml inject: session_id adds exactly the session line"

    old_session="$(printf '{"cwd":"%s","session_id":"ss-normal"}' "$WORK" | bash "$OLD_SESSION")"
    new_session="$(printf '{"cwd":"%s","session_id":"ss-normal"}' "$WORK" | bash "$NEW_SESSION")"
    assert_eq "$old_session" "$new_session" "session_start: normal full payload matches pre-migration bytes"
    assert_contains "$(printf '%s' "$new_session" | additional_context)" "SHARED-HOOK-SCRATCH" \
        "session_start: normal payload contains working memory"

    OLD_STATE="$MEM/old-state"; NEW_STATE="$MEM/new-state"
    old_compact="$(printf '{"source":"compact","cwd":"%s","session_id":"ss-compact"}' "$WORK" \
        | MEMORY_STATE_DIR="$OLD_STATE" bash "$OLD_SESSION")"
    new_compact="$(printf '{"source":"compact","cwd":"%s","session_id":"ss-compact"}' "$WORK" \
        | MEMORY_STATE_DIR="$NEW_STATE" bash "$NEW_SESSION")"
    assert_eq "$old_compact" "$new_compact" "session_start: compact emits same bytes as pre-migration"
    assert_eq "" "$new_compact" "session_start: compact emits no inline injection"
    assert_file "$OLD_STATE/ss-compact.recompact" "session_start: old compact writes sentinel"
    assert_file "$NEW_STATE/ss-compact.recompact" "session_start: migrated compact writes sentinel"

    CHUNK_STATE="$MEM/chunk-state"
    printf '{"source":"compact","cwd":"%s","session_id":"ss-chunk2"}' "$WORK" \
        | AI_MEMORY_HOOK_CHUNK=2/8 MEMORY_STATE_DIR="$CHUNK_STATE" bash "$NEW_SESSION" >/dev/null
    [ ! -e "$CHUNK_STATE/ss-chunk2.recompact" ] \
        && _ok "session_start: compact chunk 2 writes no sentinel" \
        || _bad "session_start: compact chunk 2 writes no sentinel"
    printf '{"source":"compact","cwd":"%s","session_id":"ss-chunk1"}' "$WORK" \
        | AI_MEMORY_HOOK_CHUNK=1/8 MEMORY_STATE_DIR="$CHUNK_STATE" bash "$NEW_SESSION" >/dev/null
    assert_file "$CHUNK_STATE/ss-chunk1.recompact" "session_start: compact chunk 1 writes sentinel"
else
    printf '  SKIP python3 absent; shared/Claude JSON payload comparison not run\n'
fi

# Parity oracle done — restore the orchestrator file for the remaining tests.
mv "$MEM/doctrine/orchestrator.md.aside" "$MEM/doctrine/orchestrator.md"

# --- AI_MEMORY_SKIP_INJECT gate (bare/isolated executor opt-out) — no python3 needed ---
skip_inject="$(json_payload "hello" "$WORK/sub" "sk1" | AI_MEMORY_SKIP_INJECT=1 bash "$SHARED_INJECT")"
assert_eq "" "$skip_inject" "skip-inject: inject.sh emits nothing when AI_MEMORY_SKIP_INJECT=1"

skip_start="$(printf '{"cwd":"%s","session_id":"sk-start"}' "$WORK" | AI_MEMORY_SKIP_INJECT=1 bash "$NEW_SESSION")"
assert_eq "" "$skip_start" "skip-inject: session_start emits nothing when AI_MEMORY_SKIP_INJECT=1"

SKIP_STATE="$MEM/skip-state"
printf '{"source":"compact","cwd":"%s","session_id":"sk-compact"}' "$WORK" \
    | AI_MEMORY_SKIP_INJECT=1 MEMORY_STATE_DIR="$SKIP_STATE" bash "$NEW_SESSION" >/dev/null
[ ! -e "$SKIP_STATE/sk-compact.recompact" ] \
    && _ok "skip-inject: session_start compact writes NO sentinel when skipping" \
    || _bad "skip-inject: session_start compact writes NO sentinel when skipping"

if command -v python3 >/dev/null 2>&1; then
    PAYLOAD_FILE="$MEM/chunk-payload.txt"
    ORIG_FILE="$MEM/chunk-orig.txt"
    REASM_FILE="$MEM/chunk-reassembled.txt"
    python3 - <<'PY' >"$PAYLOAD_FILE"
import sys
sys.stdout.write("alpha café\n")
sys.stdout.write("x" * 9500)
sys.stdout.write("\n")
sys.stdout.write("omega ☕")
PY
    payload="$(cat "$PAYLOAD_FILE")"
    printf '%s' "$payload" > "$ORIG_FILE"

    # Hook entries are NOT delivered in registration order (Claude, 2026-07-18:
    # 2,3,4,1,5), so chunks carry an ordering envelope. Strip it by header index
    # and reassemble sorted — the SHUFFLED order below is the point of the test.
    CHUNK_DIR="$MEM/chunk-parts"
    mkdir -p "$CHUNK_DIR"
    for i in 1 2 3 4; do
        AI_MEMORY_HOOK_CHUNK="$i/4" emit_hook_chunk "$payload" > "$CHUNK_DIR/part.$i"
    done
    # deliberately shuffled — reassembly must depend on index, not arrival
    strip_chunks "$CHUNK_DIR/part.3" "$CHUNK_DIR/part.1" "$CHUNK_DIR/part.4" \
        "$CHUNK_DIR/part.2" > "$REASM_FILE"
    if cmp -s "$ORIG_FILE" "$REASM_FILE"; then
        _ok "chunker: out-of-order slices reassemble byte-for-byte by index (UTF-8, >9000B line)"
    else
        _bad "chunker: out-of-order slices reassemble byte-for-byte by index (UTF-8, >9000B line)"
    fi

    assert_contains "$(head -n 1 "$CHUNK_DIR/part.2")" '<memory:chunk index="2" of="3">' \
        "chunker: envelope header carries index and ACTUAL slice count"
    assert_eq "</memory:chunk>" "$(tail -n 1 "$CHUNK_DIR/part.2")" \
        "chunker: envelope footer closes the chunk"
    assert_contains "$(head -n 1 "$CHUNK_DIR/part.1")" 'note="ordered fragments' \
        "chunker: chunk 1 carries the reassembly note"
    if head -n 1 "$CHUNK_DIR/part.2" | grep -q 'note='; then
        _bad "chunker: note appears only on chunk 1"
    else
        _ok "chunker: note appears only on chunk 1"
    fi
    assert_eq "" "$(cat "$CHUNK_DIR/part.4")" \
        "chunker: chunk past the natural slice count emits no envelope at all"

    # The envelope must not push a chunk over the harness per-entry cap (10,000).
    worst=0
    for i in 1 2 3 4; do
        n="$(wc -c < "$CHUNK_DIR/part.$i" | tr -d ' ')"
        [ "$n" -gt "$worst" ] && worst="$n"
    done
    if [ "$worst" -lt 10000 ]; then
        _ok "chunker: worst-case enveloped chunk ($worst B) stays under the 10,000 cap"
    else
        _bad "chunker: worst-case enveloped chunk ($worst B) stays under the 10,000 cap"
    fi

    empty="$(AI_MEMORY_HOOK_CHUNK=5/5 emit_hook_chunk "$payload")"
    assert_eq "" "$empty" "chunker: chunk beyond natural slice count is empty"

    OVER_FILE="$MEM/chunk-overflow.txt"
    AI_MEMORY_HOOK_CHUNK=2/2 emit_hook_chunk "$payload" > "$OVER_FILE"
    assert_contains "$(cat "$OVER_FILE")" "[ai-memory: memory base truncated — raise session_chunks in the harness manifest]" \
        "chunker: overflow emits loud truncation marker"
    assert_eq "[ai-memory: memory base truncated — raise session_chunks in the harness manifest]" \
        "$(tail -n 2 "$OVER_FILE" | head -n 1)" "chunker: overflow marker is the final line inside the envelope"
    assert_eq "</memory:chunk>" "$(tail -n 1 "$OVER_FILE")" \
        "chunker: overflow chunk is enveloped too"

    UNSET_FILE="$MEM/chunk-unset.txt"
    ONE_FILE="$MEM/chunk-one.txt"
    unset AI_MEMORY_HOOK_CHUNK
    emit_hook_chunk "$payload" > "$UNSET_FILE"
    AI_MEMORY_HOOK_CHUNK=1/1 emit_hook_chunk "$payload" > "$ONE_FILE"
    if cmp -s "$ORIG_FILE" "$UNSET_FILE" && cmp -s "$ORIG_FILE" "$ONE_FILE"; then
        _ok "chunker: unset and 1/1 passthrough are byte-identical"
    else
        _bad "chunker: unset and 1/1 passthrough are byte-identical"
    fi

    # Malformed specs fail CLOSED across ALL helpers: is_first/is_last must not
    # default garbage to 1/1 (would consume the recompact sentinel / emit a
    # breadcrumb from an invocation whose emit_hook_chunk then rejects the spec).
    for bad in garbage 0/8 /8 2/ 9/8 1/x; do
        if AI_MEMORY_HOOK_CHUNK="$bad" hook_chunk_is_first 2>/dev/null; then
            _bad "chunker: malformed spec '$bad' is not first"
        else
            _ok "chunker: malformed spec '$bad' is not first"
        fi
        if AI_MEMORY_HOOK_CHUNK="$bad" hook_chunk_is_last 2>/dev/null; then
            _bad "chunker: malformed spec '$bad' is not last"
        else
            _ok "chunker: malformed spec '$bad' is not last"
        fi
    done
    if hook_chunk_is_first && hook_chunk_is_last; then
        _ok "chunker: unset spec is first AND last (1/1)"
    else
        _bad "chunker: unset spec is first AND last (1/1)"
    fi
else
    printf '  SKIP python3 absent; chunker unit coverage not run\n'
fi

md_out="$(json_payload "reload @memory" "$WORK" "s3" | AI_MEMORY_HOOK_FORMAT=md bash "$SHARED_INJECT")"
assert_contains "$md_out" "# === IDENTITY ===" "shared md inject: full md identity heading"
assert_contains "$md_out" "# === ORCHESTRATOR ===" "shared md inject: full md orchestrator heading"
assert_contains "$md_out" "# === PROJECT: proj ===" "shared md inject: full md project heading"
assert_contains "$md_out" "# === DOMAIN INDEX ===" "shared md inject: full md keeps domain lazy-load table"

# Codex's REAL PreToolUse stdin shape (verified against codex 0.144.1): the shell
# command lives at tool_input.command. Using the actual schema is the point — an
# earlier version of this test used Antigravity's {"toolCall":{"args":{"CommandLine"}}}
# shape and passed while the guard read empty and failed OPEN for Codex.
guard_payload() {
    printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"%s"},"tool_use_id":"call_x"}' "$1"
}
# Antigravity's shape — exercises the guard's fallback path.
guard_payload_agy() {
    printf '{"toolCall":{"name":"run_command","args":{"CommandLine":"%s"}}}' "$1"
}

ERR="$MEM/guard.err"
# A developer's exported guard env must not change these results.
unset AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE AI_MEMORY_GUARD_OUTPUT

set +e
guard_payload "terraform apply -auto-approve" | AI_MEMORY_ROLE=task bash "$SHARED_GUARD" >/dev/null 2>"$ERR"
code=$?
set -e
assert_exit 2 "$code" "shared guard: Codex-shape denied command exits 2"
assert_contains "$(cat "$ERR")" "terraform apply" "shared guard: denied command explains reason"

set +e
guard_payload_agy "terraform apply -auto-approve" | AI_MEMORY_ROLE=task bash "$SHARED_GUARD" >/dev/null 2>"$ERR"
code=$?
set -e
assert_exit 2 "$code" "shared guard: Antigravity-shape denied command exits 2 (fallback path)"

set +e
guard_payload "terraform apply -auto-approve" | env -u AI_MEMORY_ROLE bash "$SHARED_GUARD" >/dev/null 2>"$ERR"
code=$?
set -e
assert_exit 0 "$code" "shared guard: interactive role unset exits 0"

set +e
guard_payload "ls -la && git log --oneline" | AI_MEMORY_ROLE=task bash "$SHARED_GUARD" >/dev/null 2>"$ERR"
code=$?
set -e
assert_exit 0 "$code" "shared guard: executor allowed command exits 0"

# AI_MEMORY_GUARD_SCOPE=all (Claude opt-in): agent_id present -> subagent -> deny;
# absent -> main session -> ask JSON on stdout. Default scope stays role-gated.
guard_payload_sub() {
    printf '{"hook_event_name":"PreToolUse","agent_id":"a1","agent_type":"general-purpose","tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"
}
OUT="$MEM/guard.out"

set +e
guard_payload "terraform apply" | env -u AI_MEMORY_ROLE -u AI_MEMORY_GUARD_SCOPE bash "$SHARED_GUARD" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 0 "$code" "shared guard: default scope, no role exits 0"
assert_eq "" "$(cat "$OUT" "$ERR")" "shared guard: default scope, no role prints nothing"

set +e
guard_payload_sub "terraform apply" | env -u AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE=all bash "$SHARED_GUARD" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 2 "$code" "shared guard: scope=all subagent denied command exits 2"
assert_contains "$(cat "$ERR")" "terraform apply" "shared guard: scope=all subagent deny reason on stderr"
assert_eq "" "$(cat "$OUT")" "shared guard: scope=all subagent deny prints no stdout"

set +e
guard_payload "terraform apply" | env -u AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE=all bash "$SHARED_GUARD" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 0 "$code" "shared guard: scope=all main session denied command exits 0"
assert_contains "$(cat "$OUT")" '"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"' "shared guard: scope=all main session emits ask JSON"
assert_contains "$(cat "$OUT")" "terraform apply" "shared guard: scope=all main session ask carries reason"
if command -v python3 >/dev/null 2>&1; then
    if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["hookSpecificOutput"]["permissionDecision"]=="ask" else 1)' "$OUT" 2>/dev/null; then
        _ok "shared guard: scope=all main session ask output is valid JSON"
    else
        _bad "shared guard: scope=all main session ask output is valid JSON"
    fi
fi

for ctx in main sub; do
    if [ "$ctx" = sub ]; then pl="$(guard_payload_sub "ls -la")"; else pl="$(guard_payload "ls -la")"; fi
    set +e
    printf '%s' "$pl" | env -u AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE=all bash "$SHARED_GUARD" >"$OUT" 2>"$ERR"
    code=$?
    set -e
    assert_exit 0 "$code" "shared guard: scope=all $ctx allowed command exits 0"
    assert_eq "" "$(cat "$OUT" "$ERR")" "shared guard: scope=all $ctx allowed command prints nothing"
done

# Failure modes: guard.sh resolves REPO from its own path, so a copy without
# scripts/deny-list.txt exercises the missing-list path.
NODENY_REPO="$(new_sandbox)"
EMPTYDENY_REPO="$(new_sandbox)"
trap 'rm -rf "$MEM" "$WORK" "$OLD_REPO" "$NODENY_REPO" "$EMPTYDENY_REPO"' EXIT
mkdir -p "$NODENY_REPO/scripts/hooks"
cp "$REPO/scripts/hooks/guard.sh" "$NODENY_REPO/scripts/hooks/guard.sh"
cp "$REPO/scripts/jsonutil.sh" "$REPO/scripts/deny-match.sh" "$NODENY_REPO/scripts/"
NODENY_GUARD="$NODENY_REPO/scripts/hooks/guard.sh"

set +e
guard_payload_sub "ls -la" | env -u AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE=all bash "$NODENY_GUARD" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 2 "$code" "shared guard: missing deny-list, subagent exits 2"
assert_contains "$(cat "$ERR")" "deny-list missing" "shared guard: missing deny-list, subagent reason on stderr"

set +e
guard_payload "ls -la" | env -u AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE=all bash "$NODENY_GUARD" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 0 "$code" "shared guard: missing deny-list, main session exits 0"
assert_contains "$(cat "$OUT")" '{"systemMessage":"ai-memory guard: deny-list missing' "shared guard: missing deny-list, main session emits systemMessage"
assert_contains "$(cat "$OUT")" "deny-list NOT enforced" "shared guard: missing deny-list, main session warns not enforced"

# No JSON parser: a PATH with only the coreutils guard.sh needs (no jq/python3).
NOPARSER_BIN="$NODENY_REPO/bin"
mkdir -p "$NOPARSER_BIN"
for prog in dirname cat grep sed awk; do
    src="$(command -v "$prog" 2>/dev/null)"
    [ -n "$src" ] && ln -sf "$src" "$NOPARSER_BIN/$prog"
done
BASH_BIN="$(command -v bash)"
if env -i PATH="$NOPARSER_BIN" "$BASH_BIN" -c 'command -v jq || command -v python3' >/dev/null 2>&1; then
    _bad "test setup: stub PATH still exposes a JSON parser"
fi

set +e
guard_payload_sub "terraform apply" | env -i PATH="$NOPARSER_BIN" AI_MEMORY_GUARD_SCOPE=all "$BASH_BIN" "$SHARED_GUARD" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 2 "$code" "shared guard: no parser, subagent detected by grep and denied"
assert_contains "$(cat "$ERR")" "no jq/python3" "shared guard: no parser, subagent reason on stderr"

set +e
guard_payload "terraform apply" | env -i PATH="$NOPARSER_BIN" AI_MEMORY_GUARD_SCOPE=all "$BASH_BIN" "$SHARED_GUARD" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 0 "$code" "shared guard: no parser, main session exits 0"
assert_contains "$(cat "$OUT")" '{"systemMessage":"ai-memory guard: no jq/python3' "shared guard: no parser, main session emits systemMessage"
assert_contains "$(cat "$OUT")" "deny-list NOT enforced" "shared guard: no parser, main session warns not enforced"

# run_guard <guard> <scope> <payload> — role unset, scope set verbatim.
run_guard() {
    set +e
    printf '%s' "$3" | env -u AI_MEMORY_ROLE AI_MEMORY_GUARD_SCOPE="$2" bash "$1" >"$OUT" 2>"$ERR"
    code=$?
    set -e
}

for scope in ALL " all " alll; do
    run_guard "$SHARED_GUARD" "$scope" "$(guard_payload_sub "terraform apply")"
    assert_exit 2 "$code" "shared guard: scope='$scope' subagent denied command exits 2"
    run_guard "$SHARED_GUARD" "$scope" "$(guard_payload "terraform apply")"
    assert_exit 0 "$code" "shared guard: scope='$scope' main session denied command exits 0"
    assert_contains "$(cat "$OUT")" '"permissionDecision":"ask"' "shared guard: scope='$scope' main session emits ask JSON"
done
assert_contains "$(cat "$OUT")" "unknown AI_MEMORY_GUARD_SCOPE 'alll', treating as all" "shared guard: typo scope noted in ask reason"
run_guard "$SHARED_GUARD" " all " "$(guard_payload "terraform apply")"
assert_not_contains "$(cat "$OUT")" "unknown AI_MEMORY_GUARD_SCOPE" "shared guard: padded 'all' is not reported unknown"

run_guard "$SHARED_GUARD" alll "$(guard_payload "ls -la")"
assert_exit 0 "$code" "shared guard: typo scope, main session allowed command exits 0"
assert_eq '{"systemMessage":"ai-memory guard: unknown AI_MEMORY_GUARD_SCOPE '"'alll'"', treating as all"}' "$(cat "$OUT")" "shared guard: typo scope, main session allowed command emits systemMessage"
run_guard "$SHARED_GUARD" alll "$(guard_payload_sub "ls -la")"
assert_exit 0 "$code" "shared guard: typo scope, subagent allowed command exits 0"
assert_eq "" "$(cat "$OUT")" "shared guard: typo scope, subagent allowed command prints no stdout"

for scope in "" executor; do
    run_guard "$SHARED_GUARD" "$scope" "$(guard_payload_sub "terraform apply")"
    assert_exit 0 "$code" "shared guard: scope='$scope' subagent payload is a no-op"
    assert_eq "" "$(cat "$OUT" "$ERR")" "shared guard: scope='$scope' subagent payload prints nothing"
done

set +e
guard_payload "terraform apply" | env AI_MEMORY_ROLE=task AI_MEMORY_GUARD_SCOPE=all bash "$SHARED_GUARD" >"$OUT" 2>"$ERR"
code=$?
set -e
assert_exit 2 "$code" "shared guard: role set + scope=all behaves as executor (exit 2)"
assert_eq "" "$(cat "$OUT")" "shared guard: role set + scope=all prints no ask JSON"

mkdir -p "$EMPTYDENY_REPO/scripts/hooks"
cp "$REPO/scripts/hooks/guard.sh" "$EMPTYDENY_REPO/scripts/hooks/guard.sh"
cp "$REPO/scripts/jsonutil.sh" "$REPO/scripts/deny-match.sh" "$EMPTYDENY_REPO/scripts/"
printf '# comments only\n\n' > "$EMPTYDENY_REPO/scripts/deny-list.txt"
run_guard "$EMPTYDENY_REPO/scripts/hooks/guard.sh" all "$(guard_payload_sub "ls -la")"
assert_exit 2 "$code" "shared guard: no usable rules, subagent exits 2"
assert_contains "$(cat "$ERR")" "no usable rules" "shared guard: no usable rules, subagent reason on stderr"
run_guard "$EMPTYDENY_REPO/scripts/hooks/guard.sh" all "$(guard_payload "ls -la")"
assert_exit 0 "$code" "shared guard: no usable rules, main session exits 0"
assert_contains "$(cat "$OUT")" '{"systemMessage":"ai-memory guard: deny-list at scripts/deny-list.txt has no usable rules' "shared guard: no usable rules, main session emits systemMessage"

finish
