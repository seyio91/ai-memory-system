#!/usr/bin/env bash
# Session-scoped project pin: SessionStart records the resolved project, inject.sh
# honours it for the rest of the session regardless of cwd.
#
# The bug this gates: project resolution ran from cwd on EVERY prompt, so a
# session that cd'd into another repo silently repointed every memory write —
# /checkpoint, /promote-memory, plan and todo edits — at the wrong project.
. "$(dirname "$0")/_assert.sh"

INJECT="$SCRIPTS_DIR/hooks/inject.sh"
SESSION_START="$SCRIPTS_DIR/hooks/session_start_memory.sh"
PIN_SH="$SCRIPTS_DIR/memory-pin.sh"

MEM="$(new_sandbox)"
REPOS="$(new_sandbox)"
STATE="$MEM/.sessions"
trap 'rm -rf "$MEM" "$REPOS"' EXIT

# Two projects, two checkouts, each pinned to its own project by marker.
for p in alpha beta; do
    mkdir -p "$MEM/projects/$p"
    printf -- '---\ntopic: %s\nscope: project\nsummary: s\n---\n# %s\n' "$p" "$p" > "$MEM/projects/$p/memory.md"
    mkdir -p "$REPOS/$p/.agents"
    printf '%s\n' "$p" > "$REPOS/$p/.agents/memory-project"
done
printf -- '---\ntopic: t\n---\n# identity\n' > "$MEM/identity.md"
printf '# index\n' > "$MEM/index.md"

# Decode hookSpecificOutput.additionalContext — asserting against the raw JSON
# would compare escaped bytes (project=\"beta\") and quietly never match.
additional_context() {
    python3 -c 'import json,sys
raw = sys.stdin.read().strip()
print(json.loads(raw)["hookSpecificOutput"]["additionalContext"] if raw else "", end="")'
}

run_inject() {  # <cwd> <session_id> [prompt]
    printf '{"prompt":"%s","cwd":"%s","session_id":"%s"}' "${3:-hi}" "$1" "$2" \
        | MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE" AI_MEMORY_HOOK_FORMAT=xml \
          bash "$INJECT" 2>/dev/null | additional_context
}
run_start() {   # <cwd> <session_id> [chunk]
    printf '{"cwd":"%s","session_id":"%s"}' "$1" "$2" \
        | MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE" AI_MEMORY_HOOK_FORMAT=xml \
          AI_MEMORY_HOOK_CHUNK="${3:-1/12}" bash "$SESSION_START" >/dev/null 2>&1
}

# === criterion 7: SessionStart writes the pin exactly once ==================
run_start "$REPOS/alpha" sA
assert_file "$STATE/sA.project" "SessionStart writes the pin"
assert_eq "alpha" "$(cat "$STATE/sA.project")" "pin records the resolved project"

before="$(cat "$STATE/sA.project")"
for c in 2/12 7/12 12/12; do run_start "$REPOS/alpha" sA "$c"; done
assert_eq "$before" "$(cat "$STATE/sA.project")" "later chunk invocations do not rewrite the pin"

# A non-first chunk must not create a pin at all for a fresh session.
run_start "$REPOS/beta" sChunk9 9/12
assert_not_file "$STATE/sChunk9.project" "only the first chunk writes a pin"

# === compact path writes no pin (criterion 7, second half) =================
printf '{"source":"compact","cwd":"%s","session_id":"%s"}' "$REPOS/alpha" sCompact \
    | MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE" AI_MEMORY_HOOK_CHUNK=1/12 \
      bash "$SESSION_START" >/dev/null 2>&1
assert_not_file "$STATE/sCompact.project" "compact SessionStart writes no pin"

# === no project resolves -> no pin =========================================
mkdir -p "$REPOS/unpinned"
run_start "$REPOS/unpinned" sNone
assert_not_file "$STATE/sNone.project" "no resolvable project writes no pin"

# === criterion 1: the pin beats cwd — THE bug =============================
out="$(run_inject "$REPOS/beta" sA)"
assert_contains "$out" 'project="alpha"' "pin wins over cwd (session pinned to alpha, standing in beta)"
assert_contains "$out" "projects/alpha/working.md" "working: path follows the pin, not cwd"
assert_not_contains "$out" "projects/beta/working.md" "beta's working file is never advertised"

# === criterion 3: divergence note, exactly once, only on disagreement =====
assert_eq "1" "$(printf '%s\n' "$out" | grep -c '^pinned: ')" "exactly one pinned: note on divergence"
assert_contains "$out" "pinned: alpha (cwd resolves to 'beta'" "note names both projects"

agree="$(run_inject "$REPOS/alpha" sA)"
assert_not_contains "$agree" "pinned: " "no note when cwd and pin agree"

# === criterion 2: session line ============================================
assert_contains "$out" "session: sA" "breadcrumb advertises the session id"

# === criterion 5: no session_id -> unchanged behaviour ====================
nosess="$(run_inject "$REPOS/beta" "")"
assert_contains "$nosess" 'project="beta"' "no session_id falls back to cwd resolution"
assert_not_contains "$nosess" "session: " "no session line when the harness supplies no id"
assert_not_contains "$nosess" "pinned: " "no note without a pin"

# === criterion 6: a pin naming a dead project falls back ==================
printf 'ghost\n' > "$STATE/sGhost.project"
ghost="$(run_inject "$REPOS/beta" sGhost)"
assert_contains "$ghost" 'project="beta"' "pin naming a missing project falls back to cwd"
assert_not_contains "$ghost" "ghost" "dead pin never reaches the breadcrumb"

# An empty pin file is equally inert.
: > "$STATE/sEmpty.project"
empty="$(run_inject "$REPOS/beta" sEmpty)"
assert_contains "$empty" 'project="beta"' "empty pin file falls back to cwd"

# === criterion 4: memory-pin.sh --session repins the live session =========
( cd "$REPOS/beta" && git init -q . && git -c user.name=T -c user.email=t@e.com commit --allow-empty -qm i ) >/dev/null 2>&1
set +e
pin_out="$(cd "$REPOS/beta" && MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE" bash "$PIN_SH" beta --session sA 2>&1)"
pin_code=$?
set -e
assert_exit 0 "$pin_code" "memory-pin --session exits 0"
assert_eq "beta" "$(cat "$STATE/sA.project")" "--session rewrites the live session's pin"
assert_contains "$pin_out" "live session repinned" "--session says it repinned the session"

repinned="$(run_inject "$REPOS/beta" sA)"
assert_contains "$repinned" 'project="beta"' "next prompt after --session follows the new pin"
assert_not_contains "$repinned" "pinned: " "no divergence note once pin and cwd agree again"

# Without --session the live pin is untouched (marker-only, as before).
printf 'alpha\n' > "$STATE/sA.project"
( cd "$REPOS/beta" && MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE" bash "$PIN_SH" beta >/dev/null 2>&1 )
assert_eq "alpha" "$(cat "$STATE/sA.project")" "no --session leaves live pins alone"

set +e
(cd "$REPOS/beta" && MEMORY_DIR="$MEM" bash "$PIN_SH" beta --session >/dev/null 2>&1); code=$?
set -e
assert_exit 2 "$code" "--session with no value exits 2"

# === criterion 8: pruning ================================================
mkdir -p "$STATE"
printf 'alpha\n' > "$STATE/old.project"
printf 'alpha\n' > "$STATE/fresh.project"
touch -t "$(date -v-30d +%Y%m%d0000 2>/dev/null || date -d '30 days ago' +%Y%m%d0000)" "$STATE/old.project"
run_start "$REPOS/alpha" sPrune
assert_not_file "$STATE/old.project" "stale pin pruned"
assert_file "$STATE/fresh.project" "fresh pin survives pruning"

finish
