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

. "$REPO/scripts/_lib.sh"
. "$REPO/scripts/formatters/md.sh"

export AI_MEMORY_CWD="$WORK/sub"
crumb="$(content_sections proj identity project index working | md_render_breadcrumb proj "$WORK/sub")"
assert_contains "$crumb" "project: proj" "md breadcrumb: active project"
assert_contains "$crumb" "working.md"    "md breadcrumb: working write target"
assert_contains "$crumb" "$MEM/projects/proj/working.md" "md breadcrumb: advertises absent working path"

printf '# Working\n\nSHARED-HOOK-SCRATCH\n' > "$MEM/projects/proj/working.md"

stage_old_claude_hooks() {
    mkdir -p "$OLD_REPO/harnesses/claude/hooks" "$OLD_REPO/scripts/formatters"
    git -C "$REPO" show HEAD:harnesses/claude/hooks/inject_memory.sh \
        > "$OLD_REPO/harnesses/claude/hooks/inject_memory.sh"
    git -C "$REPO" show HEAD:harnesses/claude/hooks/session_start_memory.sh \
        > "$OLD_REPO/harnesses/claude/hooks/session_start_memory.sh"
    git -C "$REPO" show HEAD:harnesses/claude/hooks/memory_common.sh \
        > "$OLD_REPO/harnesses/claude/hooks/memory_common.sh"
    cp "$REPO/scripts/content-core.sh" "$OLD_REPO/scripts/content-core.sh"
    cp "$REPO/scripts/formatters/xml.sh" "$OLD_REPO/scripts/formatters/xml.sh"
    chmod +x "$OLD_REPO/harnesses/claude/hooks/"*.sh
}

stage_old_claude_hooks
CLAUDE_INJECT="$OLD_REPO/harnesses/claude/hooks/inject_memory.sh"
OLD_SESSION="$OLD_REPO/harnesses/claude/hooks/session_start_memory.sh"
NEW_SESSION="$REPO/harnesses/claude/hooks/session_start_memory.sh"

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
else
    printf '  SKIP python3 absent; shared/Claude JSON payload comparison not run\n'
fi

md_out="$(json_payload "reload @memory" "$WORK" "s3" | AI_MEMORY_HOOK_FORMAT=md bash "$SHARED_INJECT")"
assert_contains "$md_out" "# === IDENTITY ===" "shared md inject: full md identity heading"
assert_contains "$md_out" "# === PROJECT: proj ===" "shared md inject: full md project heading"

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
