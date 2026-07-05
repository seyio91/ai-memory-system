#!/usr/bin/env bash
# inject_memory.sh (UserPromptSubmit) contract:
#   - project resolves ONLY by walking cwd up to a .agents/memory-project marker
#     (legacy .claude/memory-project still resolves via fallback; no .active_project global).
#   - plain prompt + project  -> tiny <memory:active ...> breadcrumb
#   - "@memory" prompt + project -> full payload (identity + project + index + working)
#   - no marker (any prompt)   -> silent (generic Claude, memory system dormant)
. "$(dirname "$0")/_assert.sh"

HOOK="$HOOKS_DIR/inject_memory.sh"
if [ ! -f "$HOOK" ]; then
    printf '  SKIP %s not found\n' "$HOOK"
    finish
fi

MEM="$(new_sandbox)"
REPO="$(new_sandbox)"
trap 'rm -rf "$MEM" "$REPO"' EXIT
export MEMORY_DIR="$MEM"

seed_min_tree "$MEM"   # ASCII identity/index — no multibyte to mangle
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOF
printf '# Working\n\nSCRATCH-LINE\n' > "$MEM/projects/proj/working.md"
# Legacy global must NOT influence detection any more.
printf 'stale-global\n' > "$MEM/.active_project"

# Marked repo with a nested working dir to exercise upward traversal.
mkdir -p "$REPO/.agents" "$REPO/sub/deep"
printf 'proj\n' > "$REPO/.agents/memory-project"

valid_json() { # valid_json <file> <label>
    if command -v python3 >/dev/null 2>&1; then
        if python3 -c "import json,sys; json.load(open('$1'))" 2>/dev/null; then
            _ok "$2"; else _bad "$2"
        fi
    else
        case "$(cat "$1")" in '{"hookSpecificOutput"'*) _ok "$2" ;; *) _bad "$2" ;; esac
    fi
}

out="$MEM/out"

# --- plain prompt inside marked tree -> breadcrumb only ---
bash "$HOOK" > "$out" <<<"{\"prompt\":\"hi\",\"cwd\":\"$REPO/sub/deep\"}"
b="$(cat "$out")"
valid_json "$out" "breadcrumb: valid JSON"
assert_contains     "$b" '"additionalContext"'        "breadcrumb: additionalContext key"
assert_contains     "$b" '<memory:active project=\"proj\"' "breadcrumb: names resolved project"
assert_not_contains "$b" '<memory:identity>'          "breadcrumb: no full identity"
assert_not_contains "$b" '<memory:working>'           "breadcrumb: no full working"

# --- @memory inside marked tree -> full payload ---
bash "$HOOK" > "$out" <<<"{\"prompt\":\"reload @memory\",\"cwd\":\"$REPO/sub\"}"
b="$(cat "$out")"
valid_json "$out" "reload: valid JSON"
assert_contains "$b" '<memory:identity>' "reload: identity injected"
assert_contains "$b" '<memory:index>'    "reload: index injected"
assert_contains "$b" '<memory:working>'  "reload: working injected"

# --- no marker, plain prompt -> silent (no fallback to .active_project) ---
bash "$HOOK" > "$out" <<<'{"prompt":"hi","cwd":"/tmp"}'
assert_eq "" "$(cat "$out")" "no marker: plain prompt silent"

# --- no marker, @memory -> still silent (no project = no memory) ---
bash "$HOOK" > "$out" <<<'{"prompt":"reload @memory","cwd":"/tmp"}'
assert_eq "" "$(cat "$out")" "no marker: @memory silent"

# --- legacy .claude/memory-project still resolves via the hook's fallback ---
LEG="$(new_sandbox)"; mkdir -p "$LEG/x"; mkdir -p "$LEG/.claude"; printf 'proj\n' > "$LEG/.claude/memory-project"
bash "$HOOK" > "$out" <<<"{\"prompt\":\"hi\",\"cwd\":\"$LEG/x\"}"
assert_contains "$(cat "$out")" '<memory:active project=\"proj\"' "legacy .claude marker resolves (hook fallback)"
rm -rf "$LEG"

# --- breadcrumb carries memory-file paths + reload directive ---
bash "$HOOK" > "$out" <<<"{\"prompt\":\"hi\",\"cwd\":\"$REPO\",\"session_id\":\"s1\"}"
b="$(cat "$out")"
assert_contains "$b" 'identity: '   "breadcrumb: identity path"
assert_contains "$b" 'index: '      "breadcrumb: index path"
assert_contains "$b" 'after compaction' "breadcrumb: reload directive"

# --- post-compaction flow: SessionStart(compact) sets sentinel, next prompt reloads full ---
SS="$HOOKS_DIR/session_start_memory.sh"
if [ -f "$SS" ]; then
    SENT="$MEM/.sessions/s2.recompact"
    bash "$SS" >/dev/null <<<"{\"source\":\"compact\",\"cwd\":\"$REPO\",\"session_id\":\"s2\"}"
    assert_file "$SENT" "compact: sentinel written"

    bash "$HOOK" > "$out" <<<"{\"prompt\":\"continue\",\"cwd\":\"$REPO\",\"session_id\":\"s2\"}"
    b="$(cat "$out")"
    assert_contains "$b" '<memory:identity>' "post-compact: full payload re-injected"
    [ ! -e "$SENT" ] && _ok "post-compact: sentinel consumed" || _bad "post-compact: sentinel consumed"

    # next prompt is back to a breadcrumb (sentinel already consumed)
    bash "$HOOK" > "$out" <<<"{\"prompt\":\"again\",\"cwd\":\"$REPO\",\"session_id\":\"s2\"}"
    assert_not_contains "$(cat "$out")" '<memory:identity>' "post-compact: subsequent prompt is breadcrumb"
fi

finish
