#!/usr/bin/env bash
# Shared hook scripts: format-param rendering, Claude XML payload equivalence,
# and exit-2 infra guard behavior.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
SHARED_INJECT="$REPO/scripts/hooks/inject.sh"
CLAUDE_INJECT="$REPO/harnesses/claude/hooks/inject_memory.sh"
SHARED_GUARD="$REPO/scripts/hooks/guard.sh"

MEM="$(new_sandbox)"
WORK="$(new_sandbox)"
trap 'rm -rf "$MEM" "$WORK"' EXIT
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
else
    printf '  SKIP python3 absent; shared/Claude JSON payload comparison not run\n'
fi

md_out="$(json_payload "reload @memory" "$WORK" "s3" | AI_MEMORY_HOOK_FORMAT=md bash "$SHARED_INJECT")"
assert_contains "$md_out" "# === IDENTITY ===" "shared md inject: full md identity heading"
assert_contains "$md_out" "# === PROJECT: proj ===" "shared md inject: full md project heading"

guard_payload() {
    printf '{"toolCall":{"name":"run_command","args":{"CommandLine":"%s"}}}' "$1"
}

ERR="$MEM/guard.err"

set +e
guard_payload "terraform apply -auto-approve" | AI_MEMORY_ROLE=task bash "$SHARED_GUARD" >/dev/null 2>"$ERR"
code=$?
set -e
assert_exit 2 "$code" "shared guard: executor denied command exits 2"
assert_contains "$(cat "$ERR")" "terraform apply" "shared guard: denied command explains reason"

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
