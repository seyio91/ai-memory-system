#!/usr/bin/env bash
# scripts/hooks/inject.sh (UserPromptSubmit) contract:
#   - project resolves ONLY by walking cwd up to a .agents/memory-project marker
#     (legacy .claude/memory-project still resolves via fallback; no .active_project global).
#   - plain prompt + project  -> tiny <memory:active ...> breadcrumb
#   - "@memory" prompt + project -> full payload (identity + orchestrator + project + index + working)
#   - no marker (any prompt)   -> silent (generic Claude, memory system dormant)
. "$(dirname "$0")/_assert.sh"

REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
HOOK="$REPO_ROOT/scripts/hooks/inject.sh"

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

additional_context() {
    python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"], end="")'
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

# --- @memory chunked: trigger reload fans out across chunks like post-compact ---
if command -v python3 >/dev/null 2>&1; then
    T_EXPECTED="$MEM/trigger.expected"
    T_ASSEMBLED="$MEM/trigger.assembled"
    T_CHUNK="$MEM/trigger.chunk"
    bash "$HOOK" > "$out" <<<"{\"prompt\":\"reload @memory\",\"cwd\":\"$REPO/sub\"}"
    additional_context < "$out" > "$T_EXPECTED"
    : > "$T_ASSEMBLED"
    for i in 1 2 3 4 5 6 7 8; do
        AI_MEMORY_HOOK_CHUNK="$i/8" bash "$HOOK" > "$T_CHUNK" <<<"{\"prompt\":\"reload @memory\",\"cwd\":\"$REPO/sub\"}"
        [ -s "$T_CHUNK" ] && additional_context < "$T_CHUNK" >> "$T_ASSEMBLED"
    done
    if cmp -s "$T_EXPECTED" "$T_ASSEMBLED"; then
        _ok "reload: chunked @memory re-inject reassembles byte-for-byte"
    else
        _bad "reload: chunked @memory re-inject reassembles byte-for-byte"
    fi
else
    printf '  SKIP python3 absent; @memory chunk reassembly not run\n'
fi

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

# --- per-worktree overlay: a linked git worktree injects working.<wt>.md, not the base ---
if command -v git >/dev/null 2>&1; then
    WT_MAIN="$(new_sandbox)"
    git -C "$WT_MAIN" init -q
    git -C "$WT_MAIN" -c user.name=T -c user.email=t@e commit --allow-empty -qm init
    git -C "$WT_MAIN" worktree add -q -b feat "$WT_MAIN/wt-feat" 2>/dev/null
    mkdir -p "$WT_MAIN/wt-feat/.agents"
    printf 'proj\n' > "$WT_MAIN/wt-feat/.agents/memory-project"
    # Overlay scratch file, distinct content from the base working.md (SCRATCH-LINE).
    printf '# Working\n\nOVERLAY-SCRATCH\n' > "$MEM/projects/proj/working.wt-feat.md"

    bash "$HOOK" > "$out" <<<"{\"prompt\":\"reload @memory\",\"cwd\":\"$WT_MAIN/wt-feat\"}"
    b="$(cat "$out")"
    assert_contains     "$b" 'OVERLAY-SCRATCH' "worktree: overlay working.<wt>.md injected"
    assert_not_contains "$b" 'SCRATCH-LINE'    "worktree: base working.md NOT injected in a worktree"

    # main checkout of the same repo still gets the base working.md
    mkdir -p "$WT_MAIN/.agents"; printf 'proj\n' > "$WT_MAIN/.agents/memory-project"
    bash "$HOOK" > "$out" <<<"{\"prompt\":\"reload @memory\",\"cwd\":\"$WT_MAIN\"}"
    assert_contains "$(cat "$out")" 'SCRATCH-LINE' "main checkout: base working.md injected"

    # breadcrumb advertises the overlay WRITE target even before the file exists,
    # so the first /checkpoint in a fresh worktree lands in working.<wt>.md.
    git -C "$WT_MAIN" worktree add -q -b fresh "$WT_MAIN/wt-fresh" 2>/dev/null
    mkdir -p "$WT_MAIN/wt-fresh/.agents"; printf 'proj\n' > "$WT_MAIN/wt-fresh/.agents/memory-project"
    bash "$HOOK" > "$out" <<<"{\"prompt\":\"hi\",\"cwd\":\"$WT_MAIN/wt-fresh\"}"
    assert_contains "$(cat "$out")" 'working: '"$MEM"'/projects/proj/working.wt-fresh.md' \
        "breadcrumb names the overlay write target with no overlay file yet"

    # Real harness topology (Claude EnterWorktree): worktree NESTED under
    # .claude/worktrees/<name>, project marker only at the repo root (found by
    # walking up — the worktree has none of its own), and the memory tree ($MEM)
    # is a SEPARATE dir from the code repo ($WT_MAIN). Overlay must still route
    # into the memory tree, keyed by the worktree name.
    git -C "$WT_MAIN" worktree add -q -b billing "$WT_MAIN/.claude/worktrees/billing" 2>/dev/null
    printf '# Working\n\nBILLING-OVERLAY\n' > "$MEM/projects/proj/working.billing.md"
    bash "$HOOK" > "$out" <<<"{\"prompt\":\"reload @memory\",\"cwd\":\"$WT_MAIN/.claude/worktrees/billing\"}"
    b="$(cat "$out")"
    assert_contains     "$b" 'BILLING-OVERLAY' "nested .claude worktree + root marker + separate memory dir: overlay injected"
    assert_not_contains "$b" 'SCRATCH-LINE'    "…and the base working.md is not"
    rm -rf "$WT_MAIN"
fi

# --- post-compaction flow: SessionStart(compact) sets sentinel, next prompt reloads full ---
SS="$REPO_ROOT/scripts/hooks/session_start_memory.sh"
# Fail loudly if the script moved: a silent `[ -f ]` skip would let the whole
# post-compaction flow vanish from the suite unnoticed (the "green proves nothing" trap).
assert_file "$SS" "post-compact: session_start_memory.sh present at scripts/hooks/"
if [ -f "$SS" ]; then
    if command -v python3 >/dev/null 2>&1; then
        python3 - <<'PY' >> "$MEM/projects/proj/working.md"
import sys
sys.stdout.write("\n")
sys.stdout.write("POST-COMPACT-LARGE\n")
sys.stdout.write("y" * 22000)
sys.stdout.write("\n")
PY
    fi

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

    if command -v python3 >/dev/null 2>&1; then
        EXPECTED="$MEM/postcompact.expected"
        ASSEMBLED="$MEM/postcompact.assembled"
        CHUNK_OUT="$MEM/postcompact.chunk"

        : > "$SENT"
        bash "$HOOK" > "$out" <<<"{\"prompt\":\"continue\",\"cwd\":\"$REPO\",\"session_id\":\"s2\"}"
        additional_context < "$out" > "$EXPECTED"

        : > "$SENT"
        : > "$ASSEMBLED"
        for i in 1 2 3 4 5 6 7 8; do
            AI_MEMORY_HOOK_CHUNK="$i/8" bash "$HOOK" > "$CHUNK_OUT" <<<"{\"prompt\":\"continue\",\"cwd\":\"$REPO\",\"session_id\":\"s2\"}"
            if [ -s "$CHUNK_OUT" ]; then
                additional_context < "$CHUNK_OUT" >> "$ASSEMBLED"
            fi
        done
        if cmp -s "$EXPECTED" "$ASSEMBLED"; then
            _ok "post-compact: chunked full re-inject reassembles byte-for-byte"
        else
            _bad "post-compact: chunked full re-inject reassembles byte-for-byte"
        fi
        [ ! -e "$SENT" ] && _ok "post-compact: chunked flow consumes sentinel on final chunk" \
            || _bad "post-compact: chunked flow consumes sentinel on final chunk"
    else
        printf '  SKIP python3 absent; post-compact chunk reassembly not run\n'
    fi

    AI_MEMORY_HOOK_CHUNK=1/8 bash "$HOOK" > "$out" <<<"{\"prompt\":\"again\",\"cwd\":\"$REPO\",\"session_id\":\"s2\"}"
    assert_contains "$(cat "$out")" '<memory:active project=\"proj\"' "breadcrumb: chunk 1 emits breadcrumb"
    AI_MEMORY_HOOK_CHUNK=2/8 bash "$HOOK" > "$out" <<<"{\"prompt\":\"again\",\"cwd\":\"$REPO\",\"session_id\":\"s2\"}"
    assert_eq "" "$(cat "$out")" "breadcrumb: chunk 2 emits nothing"
fi

finish
