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

# --- 5. unknown key (no template) -> exit 2 ---
export AI_MEMORY_EXECUTOR="bogus"
run --which
assert_exit 2 "$CODE" "unknown executor key exits 2"
assert_contains "$ERR" "unknown executor" "unknown key message"

# --- 5b. template without {prompt} -> exit 2 ---
export AI_MEMORY_EXECUTOR="aider"
export AI_MEMORY_EXECUTOR_CMD_aider="aider --yes"
run --which
assert_exit 2 "$CODE" "template missing {prompt} exits 2"
assert_contains "$ERR" "must contain {prompt}" "missing-token message"

# --- 6. generic CLI present on PATH -> cli:aider ---
cat > "$BIN/aider" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/aider"
export PATH="$BIN:$PATH"
export AI_MEMORY_EXECUTOR_CMD_aider="aider --yes --message {prompt}"
run --which
assert_eq "cli:aider" "$OUT" "generic CLI present -> cli:aider"
assert_exit 0 "$CODE" "generic CLI --which exits 0"
export PATH="$OLDPATH"

# --- 7. --run with generic CLI substitutes {prompt} and executes ---
MARK="$BIN/ran.txt"
cat > "$BIN/echoexec" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$MARK"
exit 0
EOF
chmod +x "$BIN/echoexec"
export PATH="$BIN:$PATH"
export AI_MEMORY_EXECUTOR="echoexec"
export AI_MEMORY_EXECUTOR_CMD_echoexec="echoexec ARG {prompt} END"
run --run "do the thing"
assert_exit 0 "$CODE" "--run generic CLI exits 0 via stub"
assert_eq "ARG do the thing END" "$(cat "$MARK")" "--run substitutes {prompt} (quoted)"
export PATH="$OLDPATH"

# --- 8. --run resolving to subagent -> sentinel + exit 3 ---
export AI_MEMORY_EXECUTOR="claude-subagent"
run --run "anything"
assert_eq "EXECUTOR_USE_SUBAGENT" "$OUT" "--run subagent prints sentinel"
assert_exit 3 "$CODE" "--run subagent exits 3"

# --- 8b. --run with missing prompt -> exit 2 ---
run --run
assert_exit 2 "$CODE" "--run without prompt exits 2"

# --- 9. --run prompt with an apostrophe survives quoting ---
MARK2="$BIN/ran2.txt"
cat > "$BIN/echoexec2" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$MARK2"
exit 0
EOF
chmod +x "$BIN/echoexec2"
export PATH="$BIN:$PATH"
export AI_MEMORY_EXECUTOR="echoexec2"
export AI_MEMORY_EXECUTOR_CMD_echoexec2="echoexec2 {prompt}"
run --run "it's a test"
assert_exit 0 "$CODE" "--run apostrophe prompt exits 0"
assert_eq "it's a test" "$(cat "$MARK2")" "--run preserves apostrophe in prompt"
export PATH="$OLDPATH"

finish
