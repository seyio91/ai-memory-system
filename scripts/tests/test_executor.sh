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

# Build a PATH with every codex-containing dir stripped, so the "codex absent"
# cases are genuinely absent even on hosts where codex IS installed (e.g. via
# nvm). Restoring the raw $PATH is NOT enough there — it still finds codex.
codex_free_path() {
    local d out="" IFS=:
    for d in $1; do
        [ -n "$d" ] || continue
        [ -x "$d/codex" ] && continue
        out="${out:+$out:}$d"
    done
    printf '%s' "$out"
}

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
export PATH="$(codex_free_path "$OLDPATH")"   # codex genuinely unreachable
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

# ============ Phase 7: roles + manifest exec_* resolution ============
unset AI_MEMORY_EXECUTOR AI_MEMORY_EXECUTOR_TASK AI_MEMORY_EXECUTOR_EXPLORE AI_MEMORY_EXECUTOR_FALLBACK

HARN="$(new_sandbox)"; export AI_MEMORY_HARNESSES_DIR="$HARN"
mk_manifest() { local n="$1"; shift; mkdir -p "$HARN/$n"; printf '%s\n' "$@" > "$HARN/$n/manifest"; }

mk_manifest sub1 'name = sub1' 'archetype = hook' 'format = xml' 'exec = subagent'
mk_manifest ww   'name = ww' 'archetype = file' 'format = md' \
    'exec_cmd = wwbin --do {prompt}' 'exec_readonly = wwbin --ro {prompt}' \
    'exec_model_flag = --model {model}' 'exec_probe = wwbin'
mk_manifest tt   'name = tt' 'archetype = file' 'format = md' \
    'exec_cmd = ttbin {prompt}' 'exec_probe = ttbin'
mk_manifest gone 'name = gone' 'archetype = file' 'format = md' \
    'exec_cmd = nope {prompt}' 'exec_probe = nope-xyz-bin'
mk_manifest md1  'name = md1' 'archetype = file' 'format = md' \
    'exec_cmd = $MEMORY_DIR/x {prompt}' 'exec_probe = wwbin'

WMARK="$BIN/ww-ran.txt"
cat > "$BIN/wwbin" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$WMARK"
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ttbin"
chmod +x "$BIN/wwbin" "$BIN/ttbin"
export PATH="$BIN:$PATH"

# task role resolves a registered harness via its manifest exec_cmd
export AI_MEMORY_EXECUTOR_TASK=ww
run --which
assert_eq "cli:ww" "$OUT" "task role: manifest harness -> cli:<name>"

# explore role with a read-only-capable harness -> cli (uses exec_readonly)
export AI_MEMORY_EXECUTOR_EXPLORE=ww
run --role explore --which
assert_eq "cli:ww" "$OUT" "explore role: harness with exec_readonly -> cli"

# explore role with a task-only harness -> degrade to subagent (never write-capable)
export AI_MEMORY_EXECUTOR_EXPLORE=tt
run --role explore --which
assert_eq "subagent" "$OUT" "explore: task-only harness degrades to subagent"
assert_contains "$ERR" "no read-only mode" "explore degrade reported"

# manifest exec=subagent sentinel -> subagent plane
export AI_MEMORY_EXECUTOR_TASK=sub1
run --which
assert_eq "subagent" "$OUT" "manifest exec=subagent -> subagent plane"

# model surfaces on the subagent plane token
export AI_MEMORY_EXECUTOR_TASK="sub1:fast"
run --which
assert_eq "subagent:fast" "$OUT" "subagent plane carries the model"

# role var overrides the legacy single var
export AI_MEMORY_EXECUTOR=sub1
export AI_MEMORY_EXECUTOR_TASK=ww
run --which
assert_eq "cli:ww" "$OUT" "role var overrides legacy AI_MEMORY_EXECUTOR"

# explore falls back to the legacy var when its role var is unset
unset AI_MEMORY_EXECUTOR_EXPLORE
export AI_MEMORY_EXECUTOR=ww
run --role explore --which
assert_eq "cli:ww" "$OUT" "explore falls back to legacy var"

# unavailable harness bin -> fallback to subagent (default fallback)
unset AI_MEMORY_EXECUTOR AI_MEMORY_EXECUTOR_EXPLORE
export AI_MEMORY_EXECUTOR_TASK=gone
run --which
assert_eq "subagent" "$OUT" "unavailable harness bin -> fallback subagent"
assert_contains "$ERR" "falling back" "unavailable harness: fallback note"

# $MEMORY_DIR expands in the resolved command
export AI_MEMORY_EXECUTOR_TASK=md1
run --show
assert_contains "$OUT" "$MEM/x {prompt}" "\$MEMORY_DIR expands in resolved command"

# --run through a manifest harness execs the command with the prompt (+ model)
export AI_MEMORY_EXECUTOR_TASK="ww:m9"
run --run "hello world"
assert_exit 0 "$CODE" "--run manifest harness exits 0 via stub"
args="$(cat "$WMARK")"
assert_contains "$args" "hello world" "--run passes the prompt to the harness command"
assert_contains "$args" "--model m9"  "--run threads the model flag"
export PATH="$OLDPATH"

finish
