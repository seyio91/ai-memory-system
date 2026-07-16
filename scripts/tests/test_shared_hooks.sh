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
crumb="$(content_sections proj identity project index working | md_render_breadcrumb proj "$WORK/sub")"
assert_contains "$crumb" "project: proj" "md breadcrumb: active project"
assert_contains "$crumb" "working.md"    "md breadcrumb: working write target"
assert_contains "$crumb" "$MEM/projects/proj/working.md" "md breadcrumb: advertises absent working path"

printf '# Working\n\nSHARED-HOOK-SCRATCH\n' > "$MEM/projects/proj/working.md"

# The parity oracle uses FROZEN pre-migration copies vendored under
# scripts/tests/fixtures/claude-legacy-hooks/ — NOT `git show HEAD:...`, which
# only resolves the old files while the migration is uncommitted (once P3 is
# committed/merged, HEAD no longer carries them and the oracle would silently
# read empty and the parity tests would fail on committed code / in CI).
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
    compare_xml_context "shared xml inject: breadcrumb matches Claude payload" "$(json_payload "hi" "$WORK/sub" "s1")"
    compare_xml_context "shared xml inject: @memory full matches Claude payload" "$(json_payload "reload @memory" "$WORK" "s2")"

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
    : > "$REASM_FILE"
    for i in 1 2 3 4; do
        AI_MEMORY_HOOK_CHUNK="$i/4" emit_hook_chunk "$payload" >> "$REASM_FILE"
    done
    if cmp -s "$ORIG_FILE" "$REASM_FILE"; then
        _ok "chunker: slices reassemble byte-for-byte with UTF-8 and >9000B line"
    else
        _bad "chunker: slices reassemble byte-for-byte with UTF-8 and >9000B line"
    fi

    empty="$(AI_MEMORY_HOOK_CHUNK=5/5 emit_hook_chunk "$payload")"
    assert_eq "" "$empty" "chunker: chunk beyond natural slice count is empty"

    OVER_FILE="$MEM/chunk-overflow.txt"
    AI_MEMORY_HOOK_CHUNK=2/2 emit_hook_chunk "$payload" > "$OVER_FILE"
    assert_contains "$(cat "$OVER_FILE")" "[ai-memory: memory base truncated — raise session_chunks in the harness manifest]" \
        "chunker: overflow emits loud truncation marker"
    assert_eq "[ai-memory: memory base truncated — raise session_chunks in the harness manifest]" \
        "$(tail -n 1 "$OVER_FILE")" "chunker: overflow marker is the final line"

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
assert_contains "$md_out" "# === PROJECT: proj ===" "shared md inject: full md project heading"
assert_not_contains "$md_out" "# === DOMAIN INDEX ===" "shared md inject: full md drops domain section"

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

finish
