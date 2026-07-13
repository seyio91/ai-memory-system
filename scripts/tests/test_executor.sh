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
# Masks codex_free_path status while forcing codex absent.
# shellcheck disable=SC2155
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

WMARK="$BIN/ww-ran.txt"; RMARK="$BIN/ww-role.txt"
cat > "$BIN/wwbin" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$WMARK"
printf '%s' "\${AI_MEMORY_ROLE:-<unset>}" > "$RMARK"
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$BIN/ttbin"
chmod +x "$BIN/wwbin" "$BIN/ttbin"
export PATH="$BIN:$PATH"

# invalid role -> exit 2 with the supported role list
run --role bogus --which
assert_exit 2 "$CODE" "invalid --role exits 2"
assert_contains "$ERR" "task|explore|validate" "invalid --role message lists roles"

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
# --run exports AI_MEMORY_ROLE so a hook-capable harness can enforce it
assert_eq "task" "$(cat "$RMARK")" "--run (task) exports AI_MEMORY_ROLE=task"

# explore --run uses exec_readonly AND advertises the explore role
unset AI_MEMORY_EXECUTOR_TASK
export AI_MEMORY_EXECUTOR_EXPLORE="ww"
run --role explore --run "scout the tree"
assert_exit 0 "$CODE" "--run explore exits 0 via stub"
args="$(cat "$WMARK")"
assert_contains "$args" "--ro" "--run explore uses exec_readonly (wwbin --ro)"
assert_eq "explore" "$(cat "$RMARK")" "--run (explore) exports AI_MEMORY_ROLE=explore"
unset AI_MEMORY_EXECUTOR_EXPLORE

# ====== validate role ======

# validate defaults to subagent and does not chain to legacy or task role vars
export AI_MEMORY_EXECUTOR=ww
export AI_MEMORY_EXECUTOR_TASK=ww
unset AI_MEMORY_EXECUTOR_VALIDATE
run --role validate --which
assert_eq "subagent" "$OUT" "validate: default ignores legacy and task role vars"

# validate role with an explicit read-only-capable harness -> cli
export AI_MEMORY_EXECUTOR_VALIDATE=ww
run --role validate --which
assert_eq "cli:ww" "$OUT" "validate role: explicit harness with exec_readonly -> cli"

# validate subagent plane carries the model
export AI_MEMORY_EXECUTOR_VALIDATE="sub1:careful"
run --role validate --which
assert_eq "subagent:careful" "$OUT" "validate: subagent plane carries the model"

# validate role with a task-only harness -> degrade to subagent (never write-capable)
export AI_MEMORY_EXECUTOR_VALIDATE=tt
run --role validate --which
assert_eq "subagent" "$OUT" "validate: task-only harness degrades to subagent"
assert_contains "$ERR" "no read-only mode" "validate degrade reported"

# degrade clears the model -> no foreign harness model leaks onto the subagent plane
export AI_MEMORY_EXECUTOR_VALIDATE="tt:gpt-5-turbo"
run --role validate --which
assert_eq "subagent" "$OUT" "validate: degrade drops the foreign model suffix"
# same guarantee for explore (the shared read-only degrade path)
export AI_MEMORY_EXECUTOR_EXPLORE="tt:gpt-5-turbo"
run --role explore --which
assert_eq "subagent" "$OUT" "explore: degrade drops the foreign model suffix"
unset AI_MEMORY_EXECUTOR_EXPLORE

# validate --run uses exec_readonly AND advertises the validate role
export AI_MEMORY_EXECUTOR_VALIDATE=ww
run --role validate --run "check the diff"
assert_exit 0 "$CODE" "--run validate exits 0 via stub"
args="$(cat "$WMARK")"
assert_contains "$args" "--ro" "--run validate uses exec_readonly (wwbin --ro)"
assert_eq "validate" "$(cat "$RMARK")" "--run (validate) exports AI_MEMORY_ROLE=validate"
unset AI_MEMORY_EXECUTOR AI_MEMORY_EXECUTOR_TASK AI_MEMORY_EXECUTOR_VALIDATE

export PATH="$OLDPATH"

# ============ arg parsing: `--role` as the trailing argument ============
# `shift 2` with one arg left is a NO-OP that returns 1. executor.sh runs
# `set -uo pipefail` (no -e), so the failure was ignored, $1 stayed "--role",
# and the while-loop spun forever. Reproduced before the fix: the process only
# died on SIGXCPU under `ulimit -t`.
#
# A regression here would HANG the suite rather than fail it, and a hanging test
# is worse than a failing one — nobody can tell it from a slow machine. Bound the
# CPU so a reverted fix dies (SIGXCPU) and the exit-2 assertion fails loudly.
# The spin is CPU-bound, so a cpu-seconds limit catches it; a wall clock would
# not distinguish it from a slow fork.
run_bounded() { # run_bounded <args...> ; sets OUT/ERR/CODE, cannot hang
    local tmp_out tmp_err
    tmp_out="$BIN/.o"; tmp_err="$BIN/.e"
    set +e
    ( ulimit -t 5; exec bash "$EXE" "$@" ) >"$tmp_out" 2>"$tmp_err"; CODE=$?
    set -e
    OUT="$(cat "$tmp_out")"; ERR="$(cat "$tmp_err")"
}

run_bounded --role
assert_exit 2 "$CODE" "trailing --role exits 2 instead of looping forever"
assert_contains "$ERR" "needs a value" "trailing --role explains the missing value"
assert_contains "$ERR" "task|explore|validate" "trailing --role lists the valid roles"

# The value-taking forms must still work (a fix that narrows a matcher is the
# likeliest place to break the happy path).
run --role explore --which
assert_exit 0 "$CODE" "--role explore --which still resolves"
run --role=validate --which
assert_exit 0 "$CODE" "--role=validate --which still resolves"
run --which
assert_exit 0 "$CODE" "bare --which (default role) still resolves"

# ============ --run --clean: uniform final-message output ============
# A `cc` harness emulates codex: it declares exec_last_message (`-o {file}`), writes
# its final message to that file, dumps NOISE to stdout and a TRANSCRIPT to stderr,
# and its exit code / whether-it-writes-the-file are env-driven so we can exercise
# success, hard failure (empty file), and partial-file failure deterministically.
unset AI_MEMORY_EXECUTOR AI_MEMORY_EXECUTOR_TASK AI_MEMORY_EXECUTOR_EXPLORE AI_MEMORY_EXECUTOR_VALIDATE
CLEANMARK="$BIN/clean-ofile.txt"   # records the -o path the CLI saw (for the cleanup assertion)
PPMARK="$BIN/pp-args.txt"          # records the args the pass-through CLI saw
cat > "$BIN/cleanbin" <<EOF
#!/usr/bin/env bash
outfile=""; prev=""
for a in "\$@"; do [ "\$prev" = "-o" ] && outfile="\$a"; prev="\$a"; done
printf '%s' "\$outfile" > "$CLEANMARK"
printf 'STDOUT-NOISE\n'
printf 'STDERR-TRANSCRIPT\n' >&2
if [ -n "\${CLEANBIN_MSG:-}" ] && [ -n "\$outfile" ]; then printf 'CLEAN-MSG' > "\$outfile"; fi
exit "\${CLEANBIN_RC:-0}"
EOF
cat > "$BIN/ppbin" <<EOF
#!/usr/bin/env bash
printf '%s' "\$*" > "$PPMARK"
printf 'PASSTHRU-OUT\n'
exit 0
EOF
chmod +x "$BIN/cleanbin" "$BIN/ppbin"
mk_manifest cc 'name = cc' 'archetype = file' 'format = md' \
    'exec_cmd = cleanbin --do {prompt}' 'exec_readonly = cleanbin --ro {prompt}' \
    'exec_last_message = -o {file}' 'exec_probe = cleanbin'
mk_manifest pp 'name = pp' 'archetype = file' 'format = md' \
    'exec_cmd = ppbin {prompt}' 'exec_probe = ppbin'
export PATH="$BIN:$PATH"
export AI_MEMORY_EXECUTOR_TASK=cc

# success: emit ONLY the final message, discard stdout noise, suppress stderr, exit 0
export CLEANBIN_MSG=1 CLEANBIN_RC=0
run --run --clean "hello"
assert_exit 0 "$CODE" "--run --clean success exits 0"
assert_eq "CLEAN-MSG" "$OUT" "--run --clean emits ONLY the final message"
assert_not_contains "$OUT" "STDOUT-NOISE" "--run --clean discards the CLI's stdout"
assert_eq "" "$ERR" "--run --clean suppresses the CLI's stderr on success"
assert_eq "0a" "$(tail -c1 "$BIN/.o" | od -An -tx1 | tr -d ' \n')" "--run --clean output ends in exactly one newline"

# temp-file cleanup: the -o file the CLI wrote no longer exists (trap EXIT removed it)
ofile="$(cat "$CLEANMARK")"
if [ -n "$ofile" ] && [ ! -e "$ofile" ]; then cleaned=yes; else cleaned=no; fi
assert_eq "yes" "$cleaned" "--run --clean removes its temp file after the run"
unset CLEANBIN_MSG CLEANBIN_RC

# hard failure (CLI writes no message, exits non-zero): empty stdout, exit propagated,
# stderr surfaced for debugging
export CLEANBIN_RC=7
run --run --clean "boom"
assert_exit 7 "$CODE" "--run --clean propagates a non-zero CLI exit code"
assert_eq "" "$OUT" "--run --clean emits nothing when the message file is empty"
assert_eq "0" "$(wc -c < "$BIN/.o" | tr -d ' ')" "--run --clean writes zero bytes (not a stray newline) on an empty message file"
assert_contains "$ERR" "STDERR-TRANSCRIPT" "--run --clean surfaces the CLI's stderr on failure"
unset CLEANBIN_RC

# partial failure (CLI wrote a message but still exited non-zero): message is emitted,
# exit code propagated, stderr still surfaced
export CLEANBIN_MSG=1 CLEANBIN_RC=5
run --run --clean "partial"
assert_exit 5 "$CODE" "--run --clean failure still propagates the exit code (5)"
assert_eq "CLEAN-MSG" "$OUT" "--run --clean emits the partial message on failure"
assert_contains "$ERR" "STDERR-TRANSCRIPT" "--run --clean surfaces stderr on a partial failure"
unset CLEANBIN_MSG CLEANBIN_RC

# pass-through: a harness with NO exec_last_message ignores --clean (raw stdout, no -o flag)
export AI_MEMORY_EXECUTOR_TASK=pp
run --run --clean "x"
assert_exit 0 "$CODE" "--run --clean pass-through exits 0"
assert_contains "$OUT" "PASSTHRU-OUT" "--clean on a harness without exec_last_message passes stdout through"
assert_not_contains "$(cat "$PPMARK")" "-o" "--clean pass-through appends no -o flag"

# regression: --run WITHOUT --clean is unchanged — streams the CLI's stdout, appends no -o
export AI_MEMORY_EXECUTOR_TASK=cc CLEANBIN_MSG=1
run --run "verbose"
assert_exit 0 "$CODE" "--run without --clean exits 0"
assert_contains "$OUT" "STDOUT-NOISE" "--run without --clean streams the CLI's stdout (verbose, unchanged)"
assert_eq "" "$(cat "$CLEANMARK")" "--run without --clean appends no -o flag"
unset AI_MEMORY_EXECUTOR_TASK CLEANBIN_MSG

# --clean is role-agnostic: the explore role (exec_readonly path) is also cleaned
export AI_MEMORY_EXECUTOR_EXPLORE=cc CLEANBIN_MSG=1
run --role explore --run --clean "scout"
assert_exit 0 "$CODE" "--run --clean (explore role) exits 0"
assert_eq "CLEAN-MSG" "$OUT" "--run --clean cleans the explore role (exec_readonly) too"
unset AI_MEMORY_EXECUTOR_EXPLORE CLEANBIN_MSG

# --clean on the subagent plane is a no-op: still prints the sentinel and exits 3
export AI_MEMORY_EXECUTOR_VALIDATE=claude-subagent
run --role validate --run --clean "check"
assert_eq "EXECUTOR_USE_SUBAGENT" "$OUT" "--run --clean on the subagent plane still prints the sentinel"
assert_exit 3 "$CODE" "--run --clean on the subagent plane exits 3 (--clean is a no-op)"
unset AI_MEMORY_EXECUTOR_VALIDATE
export PATH="$OLDPATH"

finish
