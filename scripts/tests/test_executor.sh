#!/usr/bin/env bash
# executor.sh: selection/dispatch resolver. Uses stub binaries on PATH so no
# real codex/aider is needed. Targets bash 3.2.
. "$(dirname "$0")/_assert.sh"

EXE="$SCRIPTS_DIR/executor.sh"
MEM="$(new_sandbox)"
BIN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

run() { # run <args...> ; sets OUT (stdout), ERR (stderr), CODE
    local tmp_out tmp_err
    tmp_out="$BIN/.o"; tmp_err="$BIN/.e"
    set +e
    bash "$EXE" "$@" >"$tmp_out" 2>"$tmp_err"; CODE=$?
    set -e
    OUT="$(cat "$tmp_out")"; ERR="$(cat "$tmp_err")"
}

# --- 1. default (unset) -> subagent ---
set +e
( unset AI_MEMORY_EXECUTOR; export MEMORY_DIR="$MEM"
  bash "$EXE" --which ) > "$BIN/o" 2> "$BIN/e"; CODE=$?
set -e
assert_eq "subagent" "$(cat "$BIN/o")" "default executor resolves to subagent"
assert_exit 0 "$CODE" "default --which exits 0"

# --- 1b. explicit claude-subagent -> subagent ---
export AI_MEMORY_EXECUTOR="claude-subagent"
run --which
assert_eq "subagent" "$OUT" "explicit claude-subagent -> subagent"
assert_exit 0 "$CODE" "claude-subagent --which exits 0"

# --- 2. codex selected + codex present on PATH -> cli:codex ---
cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/codex"
OLDPATH="$PATH"; export PATH="$BIN:$PATH"
export AI_MEMORY_EXECUTOR="codex"
run --which
assert_eq "cli:codex" "$OUT" "codex present -> cli:codex"
assert_exit 0 "$CODE" "codex present --which exits 0"

# --- 3. codex selected + codex ABSENT + default fallback -> subagent ---
export PATH="$OLDPATH"   # codex no longer reachable
run --which
assert_eq "subagent" "$OUT" "codex absent -> falls back to subagent"
assert_exit 0 "$CODE" "codex absent w/ fallback exits 0"
assert_contains "$ERR" "falling back" "fallback note on stderr"

# --- 4. codex absent + empty fallback -> hard-fail exit 1 ---
export AI_MEMORY_EXECUTOR_FALLBACK=""
run --which
assert_exit 1 "$CODE" "codex absent + no fallback exits 1"
unset AI_MEMORY_EXECUTOR_FALLBACK

finish
