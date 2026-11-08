#!/usr/bin/env bash
# opencode executor face: harnesses/opencode/scripts/opencode-mem.sh + executor.sh
# resolution. Hermetic: a stub `opencode` records argv/env and replays the captured
# `run --format json` fixture; no real opencode, HOME or config is touched.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
EXE="$REPO/scripts/executor.sh"
FIX="$REPO/scripts/tests/fixtures/opencode/run-format-json.jsonl"
WRAP_SRC="$REPO/harnesses/opencode/scripts/opencode-mem.sh"

MEM="$(new_sandbox)"
BIN="$(new_sandbox)"
FAKEHOME="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN" "$FAKEHOME"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

mkdir -p "$MEM/harnesses/opencode/scripts"
cp "$REPO/harnesses/opencode/manifest" "$MEM/harnesses/opencode/manifest"
cp "$WRAP_SRC" "$MEM/harnesses/opencode/scripts/opencode-mem.sh"
chmod +x "$MEM/harnesses/opencode/scripts/opencode-mem.sh"
export AI_MEMORY_HARNESSES_DIR="$MEM/harnesses"
WRAP="$MEM/harnesses/opencode/scripts/opencode-mem.sh"

# The wrapper refuses to run without the guard plugin: install a symlink to this tree's plugin
# into a throwaway global opencode config dir (never the real ~/.config/opencode).
mkdir -p "$MEM/harnesses/opencode/plugin"
printf '// stub plugin\n' > "$MEM/harnesses/opencode/plugin/ai-memory.ts"
PLUG="$MEM/harnesses/opencode/plugin/ai-memory.ts"
CFGDIR="$FAKEHOME/ocfg"
mkdir -p "$CFGDIR/plugins"
ln -s "$PLUG" "$CFGDIR/plugins/ai-memory.ts"
export OPENCODE_CONFIG_DIR="$CFGDIR"
unset XDG_CONFIG_HOME

EXPECT="$(jq -Rrn '[inputs | fromjson? | select(.type == "text")] | last | .part.text' "$FIX")"
assert_contains "$EXPECT" "PINEAPPLE42" "fixture last assistant text is non-empty"

CAP="$BIN/args"
ENVCAP="$BIN/env"
make_stub() { # make_stub <path>
    cat > "$1" <<STUB
#!/bin/sh
printf '%s\n' "\$@" > "$CAP"
printf 'SKILLS=%s\n' "\${OPENCODE_DISABLE_CLAUDE_CODE_SKILLS:-}" > "$ENVCAP"
case "\${FAKE_OC_MODE:-ok}" in
  multi) printf '{"type":"text","part":{"type":"text","text":"EARLY-TEXT"}}\n'; cat "$FIX" ;;
  trunc) printf '{"type":"text","part":{"type":"text","text":"EARLY-TEXT"}}\n{"type":"text","part":{"type":"text","te' ;;
  notext) printf '{"type":"step_start","part":{}}\n{"type":"step_finish","part":{}}\n' ;;
  cfg) printf 'CFG=%s\n' "\${OPENCODE_CONFIG_CONTENT:-}" >> "$ENVCAP"; cat "$FIX" ;;
  objtext) cat "$FIX"; printf '{"type":"text","part":{"type":"text","text":{"a":1}}}\n' ;;
  arrtext) cat "$FIX"; printf '{"type":"text","part":{"type":"text","text":["x"]}}\n' ;;
  scalar) cat "$FIX"; printf '42\n' ;;
  error) printf '{"type":"error","error":{"type":"provider.no-route","message":"Model unavailable: x/y"}}\n' ;;
  emptyerr) printf '{"type":"text","part":{"text":"EARLY"}}\n{"type":"error","error":{"message":""}}\n' ;;
  noerrobj) printf '{"type":"text","part":{"text":"EARLY"}}\n{"type":"error"}\n' ;;
  finalnl) printf '{"type":"text","part":{"text":"FINAL\\\\n\\\\n"}}\n' ;;
  *) cat "$FIX" ;;
esac
exit "\${FAKE_OC_RC:-0}"
STUB
    chmod +x "$1"
}
make_stub "$BIN/opencode"

OLDPATH="$PATH"
export PATH="$BIN:$PATH"

# --- wrapper, driven directly ---------------------------------------------
LM="$BIN/lastmsg"
set +e
OUT="$(bash "$WRAP" run --auto "do it" -m openai/gpt-4.1-mini --last-message "$LM" 2>"$BIN/err")"
CODE=$?
set -e
assert_exit 0 "$CODE" "wrapper exits 0 on success"
assert_eq "$EXPECT" "$(cat "$LM")" "--last-message file holds only the last assistant text"
assert_eq "$(wc -c < "$LM" | tr -d ' ')" "$(printf '%s' "$EXPECT" | wc -c | tr -d ' ')" "--last-message file is byte-exact (no extra bytes)"
assert_contains "$OUT" '"type": "step_start"' "wrapper streams the JSON stdout through"
args="$(cat "$CAP")"
assert_not_contains "$args" "--last-message" "--last-message flag stripped from opencode argv"
assert_not_contains "$args" "$LM" "--last-message file stripped from opencode argv"
assert_contains "$args" "--format" "--last-message adds --format"
assert_contains "$args" "json" "--last-message adds --format json"
assert_contains "$args" "--standalone" "wrapper forces --standalone (guard plugin must load)"
assert_eq "run" "$(sed -n 1p "$CAP")" "run stays the first argument"
assert_contains "$args" "-m" "model flag passes through"
assert_contains "$args" "openai/gpt-4.1-mini" "model value passes through"
assert_contains "$(cat "$ENVCAP")" "SKILLS=1" "OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1 exported"

# --last-message first in argv is stripped just the same
rm -f "$LM"
set +e; bash "$WRAP" --last-message "$LM" run --auto p >/dev/null 2>&1; CODE=$?; set -e
assert_exit 0 "$CODE" "--last-message accepted before the subcommand"
assert_not_contains "$(cat "$CAP")" "--last-message" "leading --last-message stripped"
assert_eq "$EXPECT" "$(cat "$LM")" "leading --last-message still extracts the text"

# without --last-message: no --format forced, still standalone, stdout passthrough
set +e; OUT="$(bash "$WRAP" run --auto plain 2>/dev/null)"; CODE=$?; set -e
assert_exit 0 "$CODE" "wrapper without --last-message exits 0"
assert_not_contains "$(cat "$CAP")" "--format" "no --format injected without --last-message"
assert_contains "$(cat "$CAP")" "--standalone" "plain mode is standalone too"

# several text events: only the LAST one is extracted
set +e; FAKE_OC_MODE=multi bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 0 "$CODE" "multi-text stream exits 0"
assert_eq "$EXPECT" "$(cat "$LM")" "only the last text event is extracted, not earlier ones"

# exit-code propagation
set +e; FAKE_OC_RC=1 bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 1 "$CODE" "exit code 1 propagates (--last-message mode)"
set +e; FAKE_OC_RC=7 bash "$WRAP" run --auto p >/dev/null 2>&1; CODE=$?; set -e
assert_exit 7 "$CODE" "exit code propagates (plain mode)"

# error event: exit 0 from the CLI still fails, message reaches stderr, no text written
set +e; FAKE_OC_MODE=error bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "type=error event forces exit 1"
assert_contains "$(cat "$BIN/err")" "Model unavailable: x/y" "type=error message emitted on stderr"
assert_eq "0" "$(wc -c < "$LM" | tr -d ' ')" "no assistant text written on error"

# any error event is a failure, whatever its message (empty or missing included)
for m in emptyerr noerrobj; do
    set +e; FAKE_OC_MODE=$m bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
    assert_exit 1 "$CODE" "$m: CLI exit 0 but error event forces failure"
    assert_contains "$(cat "$BIN/err")" "opencode reported an error event with no message" "$m: fallback message on stderr"
    assert_eq "0" "$(wc -c < "$LM" | tr -d ' ')" "$m: no EARLY text written"
    set +e; OUT="$(AI_MEMORY_EXECUTOR_TASK=opencode FAKE_OC_MODE=$m bash "$EXE" --role task --run --clean p 2>/dev/null)"; CODE=$?; set -e
    assert_exit 1 "$CODE" "$m: executor --run --clean non-zero"
    assert_not_contains "$OUT" "EARLY" "$m: executor --run --clean stdout has no EARLY"
done

# last message is byte-exact, trailing newlines included
set +e; FAKE_OC_MODE=finalnl bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 0 "$CODE" "finalnl: exits 0"
assert_eq "7" "$(wc -c < "$LM" | tr -d ' ')" "finalnl: FINAL plus two newlines preserved (7 bytes)"

# B3: malformed / failed / empty streams never leave a (stale) final message
printf 'STALE' > "$LM"
set +e; FAKE_OC_MODE=trunc bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "truncated final JSON line: non-zero exit"
assert_eq "0" "$(wc -c < "$LM" | tr -d ' ')" "truncated final JSON line: no stale or earlier text promoted"
assert_contains "$(cat "$BIN/err")" "malformed JSON" "truncated final JSON line: reason on stderr"
printf 'STALE' > "$LM"
set +e; FAKE_OC_MODE=notext bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "stream with no text event: non-zero exit"
assert_eq "0" "$(wc -c < "$LM" | tr -d ' ')" "stream with no text event: file empty"
assert_contains "$(cat "$BIN/err")" "no final assistant text" "stream with no text event: reason on stderr"
printf 'STALE' > "$LM"
set +e; FAKE_OC_RC=3 bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 3 "$CODE" "failed run keeps the CLI exit code"
assert_eq "0" "$(wc -c < "$LM" | tr -d ' ')" "failed run (valid stream): no last-message written"
set +e; AI_MEMORY_EXECUTOR_TASK=opencode FAKE_OC_MODE=trunc bash "$EXE" --role task --run --clean p >"$BIN/out" 2>/dev/null; CODE=$?; set -e
assert_exit 1 "$CODE" "executor --run --clean: truncated stream fails"
assert_eq "0" "$(wc -c < "$BIN/out" | tr -d ' ')" "executor --run --clean: truncated stream emits nothing"

# fix round 2: capture failure must not promote earlier output
TEEDIR="$(new_sandbox)"
cat > "$TEEDIR/tee" <<'TEE'
#!/bin/sh
# failing capture: keeps only the first line, then dies (earlier commentary stays a valid JSON file)
head -n 1 > "$1"; cat >/dev/null; exit 1
TEE
chmod +x "$TEEDIR/tee"
printf 'STALE' > "$LM"
set +e; PATH="$TEEDIR:$PATH" FAKE_OC_MODE=multi bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "capture (tee) failure: non-zero exit"
assert_eq "0" "$(wc -c < "$LM" | tr -d ' ')" "capture (tee) failure: earlier text not promoted, file empty"
assert_contains "$(cat "$BIN/err")" "capture" "capture (tee) failure: reason on stderr"
rm -rf "$TEEDIR"
set +e; TMPDIR="$BIN/does-not-exist" bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 1 "$CODE" "unusable capture path (mktemp fails): non-zero exit"
for m in objtext arrtext; do
    printf 'STALE' > "$LM"
    set +e; FAKE_OC_MODE=$m bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
    assert_exit 1 "$CODE" "$m: non-string part.text is rejected"
    assert_eq "0" "$(wc -c < "$LM" | tr -d ' ')" "$m: non-string part.text: file empty"
done
printf 'STALE' > "$LM"
set +e; FAKE_OC_MODE=scalar bash "$WRAP" run --auto p --last-message "$LM" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "last line not a JSON object: rejected"
assert_eq "0" "$(wc -c < "$LM" | tr -d ' ')" "last line not a JSON object: file empty"

# B4a: Code Mode execute tool is denied via OPENCODE_CONFIG_CONTENT
env -u OPENCODE_CONFIG_CONTENT FAKE_OC_MODE=cfg bash "$WRAP" run --auto p >/dev/null 2>&1
assert_contains "$(grep '^CFG=' "$ENVCAP" | tail -1)" '"execute":"deny"' "OPENCODE_CONFIG_CONTENT carries permission.execute=deny"
OPENCODE_CONFIG_CONTENT='{"model":"x/y","permission":{"bash":"ask","execute":"allow"}}' FAKE_OC_MODE=cfg bash "$WRAP" run --auto p >/dev/null 2>&1
merged="$(grep '^CFG=' "$ENVCAP" | tail -1 | sed 's/^CFG=//')"
assert_eq deny "$(printf '%s' "$merged" | jq -r .permission.execute)" "caller config merged: execute forced to deny"
assert_eq ask "$(printf '%s' "$merged" | jq -r .permission.bash)" "caller config merged: caller permission keys kept"
assert_eq x/y "$(printf '%s' "$merged" | jq -r .model)" "caller config merged: caller top-level keys kept"
set +e; OPENCODE_CONFIG_CONTENT='not json' bash "$WRAP" run --auto p >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "unparseable caller OPENCODE_CONFIG_CONTENT refuses to run"

# fix round 2: caller config must be exactly one JSON object
for bad in '{"a":1}{"b":2}' '[{"a":1}]' '42' '"str"' 'null'; do
    set +e; OPENCODE_CONFIG_CONTENT="$bad" bash "$WRAP" run --auto p >/dev/null 2>"$BIN/err"; CODE=$?; set -e
    assert_exit 1 "$CODE" "OPENCODE_CONFIG_CONTENT $bad: refused"
    assert_contains "$(cat "$BIN/err")" "exactly one JSON object" "OPENCODE_CONFIG_CONTENT $bad: clear message"
done

# fix round 2: guard registration must be established before any run
GCFG2="$(new_sandbox)"; PROJ="$(new_sandbox)"; OTHER="$BIN/other-plugin.ts"; printf 'x' > "$OTHER"
rm -f "$CAP"
set +e; OPENCODE_CONFIG_DIR="$GCFG2" bash -c "cd '$PROJ' && bash '$WRAP' run --auto p" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "no plugin installed: run refused"
assert_contains "$(cat "$BIN/err")" "guard plugin is not installed" "no plugin installed: clear message"
assert_not_file "$CAP" "no plugin installed: opencode never started"
mkdir -p "$GCFG2/plugins"; ln -s "$OTHER" "$GCFG2/plugins/ai-memory.ts"
set +e; OPENCODE_CONFIG_DIR="$GCFG2" bash -c "cd '$PROJ' && bash '$WRAP' run --auto p" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 1 "$CODE" "wrong-target symlink: refused"
assert_not_file "$CAP" "wrong-target symlink: opencode never started"
rm -f "$GCFG2/plugins/ai-memory.ts"; ln -s "$GCFG2/nonexistent.ts" "$GCFG2/plugins/ai-memory.ts"
set +e; OPENCODE_CONFIG_DIR="$GCFG2" bash -c "cd '$PROJ' && bash '$WRAP' run --auto p" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 1 "$CODE" "dangling symlink: refused"
rm -f "$GCFG2/plugins/ai-memory.ts"; ln -s "$PLUG" "$GCFG2/plugins/ai-memory.ts"
set +e; OPENCODE_CONFIG_DIR="$GCFG2" bash -c "cd '$PROJ' && bash '$WRAP' run --auto p" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 0 "$CODE" "global plugin symlink (OPENCODE_CONFIG_DIR): proceeds"
assert_file "$CAP" "global plugin symlink: opencode started"
rm -f "$GCFG2/plugins/ai-memory.ts" "$CAP"
# XDG_CONFIG_HOME/opencode and $HOME/.config/opencode fallbacks
mkdir -p "$GCFG2/xdg/opencode/plugins" "$GCFG2/home/.config/opencode/plugins"
ln -s "$PLUG" "$GCFG2/xdg/opencode/plugins/ai-memory.ts"; ln -s "$PLUG" "$GCFG2/home/.config/opencode/plugins/ai-memory.ts"
set +e; env -u OPENCODE_CONFIG_DIR XDG_CONFIG_HOME="$GCFG2/xdg" bash -c "cd '$PROJ' && bash '$WRAP' run --auto p" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 0 "$CODE" "global plugin via XDG_CONFIG_HOME: proceeds"
set +e; env -u OPENCODE_CONFIG_DIR -u XDG_CONFIG_HOME HOME="$GCFG2/home" bash -c "cd '$PROJ' && bash '$WRAP' run --auto p" >/dev/null 2>&1; CODE=$?; set -e
assert_exit 0 "$CODE" "global plugin via \$HOME/.config: proceeds"
# project-local plugin is NOT accepted (opencode_session_move leaves it behind)
mkdir -p "$PROJ/.opencode/plugins"; ln -s "$PLUG" "$PROJ/.opencode/plugins/ai-memory.ts"
rm -f "$CAP"
set +e; OPENCODE_CONFIG_DIR="$GCFG2/empty" bash -c "cd '$PROJ' && bash '$WRAP' run --auto p" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "project-local plugin only: run refused"
assert_contains "$(cat "$BIN/err")" "project-local is not accepted" "project-local plugin only: clear message"
assert_not_file "$CAP" "project-local plugin only: opencode never started"
rm -rf "$PROJ/.opencode"; rm -f "$CAP"
# plain no-plugin refusal
set +e; OPENCODE_CONFIG_DIR="$GCFG2/empty" bash -c "cd '$PROJ' && bash '$WRAP' run --auto p" >/dev/null 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "no plugin anywhere: run refused"
assert_contains "$(cat "$BIN/err")" "guard plugin is not installed" "no plugin anywhere: refusal message"
assert_not_file "$CAP" "no plugin anywhere: opencode never started"
# executor.sh --run surfaces the refusal
rm -f "$CAP"
set +e; OPENCODE_CONFIG_DIR="$GCFG2/empty" AI_MEMORY_EXECUTOR_TASK=opencode bash "$EXE" --role task --run p >"$BIN/out" 2>"$BIN/err"; CODE=$?; set -e
assert_exit 1 "$CODE" "executor --run with no plugin: non-zero"
assert_contains "$(cat "$BIN/err")" "guard plugin is not installed" "executor --run with no plugin: refusal surfaced"
assert_not_file "$CAP" "executor --run with no plugin: opencode never started"
rm -rf "$GCFG2" "$PROJ"

# --- binary resolution ----------------------------------------------------
JQDIR="$(dirname "$(command -v jq)")"
SYSPATH="/usr/bin:/bin:$JQDIR"
mkdir -p "$FAKEHOME/.opencode/bin"
make_stub "$FAKEHOME/.opencode/bin/opencode"
rm -f "$CAP"
set +e
HOME="$FAKEHOME" PATH="$SYSPATH" bash "$WRAP" run --auto fb --last-message "$LM" >/dev/null 2>&1
CODE=$?
set -e
assert_exit 0 "$CODE" "falls back to \$HOME/.opencode/bin/opencode"
assert_file "$CAP" "fallback binary was actually executed"
assert_eq "$EXPECT" "$(cat "$LM")" "fallback binary output extracted"

EMPTYHOME="$(new_sandbox)"
set +e
HOME="$EMPTYHOME" PATH="$SYSPATH" bash "$WRAP" run --auto none >/dev/null 2>"$BIN/err"
CODE=$?
set -e
rm -rf "$EMPTYHOME"
assert_exit 127 "$CODE" "exit 127 when opencode is on neither PATH nor \$HOME/.opencode/bin"
assert_contains "$(cat "$BIN/err")" "opencode not found" "clear error when opencode is missing"

# --- executor.sh resolution -----------------------------------------------
run() {
    set +e
    OUT="$(bash "$EXE" "$@" 2>"$BIN/err")"
    CODE=$?
    set -e
    ERR="$(cat "$BIN/err")"
}
export AI_MEMORY_EXECUTOR_FALLBACK=""
unset AI_MEMORY_EXECUTOR AI_MEMORY_EXECUTOR_TASK AI_MEMORY_EXECUTOR_EXPLORE AI_MEMORY_EXECUTOR_VALIDATE

export AI_MEMORY_EXECUTOR_TASK=opencode
run --role task --which
assert_exit 0 "$CODE" "task --which exits 0"
assert_eq "cli:opencode" "$OUT" "task --which resolves to cli:opencode"

export AI_MEMORY_EXECUTOR_TASK="opencode:openai/gpt-4.1-mini"
run --role task --show
assert_contains "$OUT" "-m openai/gpt-4.1-mini" "model id threaded as -m"
assert_contains "$OUT" "opencode-mem.sh run --auto" "task resolves to the --auto exec_cmd"

export AI_MEMORY_EXECUTOR_TASK="opencode:ollama/qwen3:8b"
run --role task --show
assert_contains "$OUT" "-m ollama/qwen3:8b" "model id containing ':' kept whole"
run --role task --run "colon prompt"
assert_exit 0 "$CODE" "task --run with colon model exits 0"
args="$(cat "$CAP")"
assert_contains "$args" "ollama/qwen3:8b" "stub received the full colon model id"
assert_contains "$args" "colon prompt" "stub received the prompt"
assert_contains "$args" "--auto" "task run passes --auto"
assert_contains "$args" "--standalone" "task run is standalone"

export AI_MEMORY_EXECUTOR_EXPLORE="opencode:openai/gpt-4.1-mini"
run --role explore --which
assert_eq "cli:opencode" "$OUT" "explore --which resolves to cli:opencode"
run --role explore --show
assert_contains "$OUT" "--agent ai-memory-explore" "explore resolves to the readonly line"
assert_not_contains "$OUT" "--auto" "explore command does not auto-approve"
run --role explore --run "scout"
assert_exit 0 "$CODE" "explore --run exits 0"
args="$(cat "$CAP")"
assert_contains "$args" "ai-memory-explore" "explore run selects the explore agent"
assert_not_contains "$args" "--auto" "explore run never passes --auto"

export AI_MEMORY_EXECUTOR_TASK="opencode:openai/gpt-4.1-mini"
run --role task --run --clean "clean prompt"
assert_exit 0 "$CODE" "--run --clean exits 0"
assert_eq "$EXPECT" "$OUT" "--run --clean emits only the final assistant message"
assert_not_contains "$(cat "$CAP")" "--last-message" "executor --clean: flag never reaches opencode"

FAKE_OC_RC=1 run --role task --run --clean "fail prompt"
assert_exit 1 "$CODE" "--run --clean propagates exit 1"

# --- off-PATH probe (opencode installer puts the bin at ~/.opencode/bin) -------
# opencode only at $HOME/.opencode/bin/opencode, none on PATH: the probe finds it.
export AI_MEMORY_EXECUTOR_TASK=opencode
set +e; HOME="$FAKEHOME" PATH="$SYSPATH" bash "$WRAP" --probe >"$BIN/probe.out" 2>&1; CODE=$?; set -e
assert_exit 0 "$CODE" "--probe exits 0 when only \$HOME/.opencode/bin/opencode exists"
assert_eq "0" "$(wc -c < "$BIN/probe.out" | tr -d ' ')" "--probe prints nothing"
set +e; OUT="$(HOME="$FAKEHOME" PATH="$SYSPATH" bash "$EXE" --role task --which 2>"$BIN/err")"; CODE=$?; set -e
assert_exit 0 "$CODE" "off-PATH opencode: task --which exits 0"
assert_eq "cli:opencode" "$OUT" "off-PATH opencode (only \$HOME/.opencode/bin) resolves to cli:opencode"

# neither present: degrades exactly like any unavailable CLI (subagent plane, notice on stderr)
EMPTYHOME="$(new_sandbox)"
set +e; OUT="$(HOME="$EMPTYHOME" PATH="$SYSPATH" bash "$WRAP" --probe 2>"$BIN/probe.err")"; CODE=$?; set -e
assert_exit 1 "$CODE" "--probe exits 1 when opencode is nowhere"
assert_eq "" "$OUT$(cat "$BIN/probe.err")" "--probe prints nothing when absent either"
set +e; OUT="$(HOME="$EMPTYHOME" PATH="$SYSPATH" bash "$EXE" --role task --which 2>"$BIN/err")"; CODE=$?; set -e
ERR="$(cat "$BIN/err")"
assert_exit 1 "$CODE" "no opencode anywhere: task --which exits 1 like any unavailable CLI (no fallback configured)"
assert_eq "" "$OUT" "no opencode anywhere: nothing resolved"
assert_contains "$ERR" "opencode unavailable" "no opencode anywhere: unavailable notice on stderr"
# parity: an unavailable codex (bare exec_probe) degrades the same way
mkdir -p "$MEM/harnesses/codex"
cp "$REPO/harnesses/codex/manifest" "$MEM/harnesses/codex/manifest"
export AI_MEMORY_EXECUTOR_TASK=codex
set +e; OUT2="$(HOME="$EMPTYHOME" PATH="$SYSPATH" bash "$EXE" --role task --which 2>/dev/null)"; CODE2=$?; set -e
assert_exit "$CODE" "$CODE2" "opencode and codex fail identically when their CLI is absent"
# with the subagent fallback configured, an absent opencode degrades to it
export AI_MEMORY_EXECUTOR_TASK=opencode AI_MEMORY_EXECUTOR_FALLBACK=subagent
set +e; OUT3="$(HOME="$EMPTYHOME" PATH="$SYSPATH" bash "$EXE" --role task --which 2>/dev/null)"; set -e
assert_eq "subagent" "$OUT3" "absent opencode degrades to the subagent plane when fallback=subagent"
export AI_MEMORY_EXECUTOR_FALLBACK=""
rm -rf "$EMPTYHOME"

# exec_probe goes through expand_memdir: a $MEMORY_DIR-relative probe path resolves
mkdir -p "$MEM/harnesses/probetest" "$MEM/bin"
printf '#!/bin/sh\nexit 0\n' > "$MEM/bin/probebin"; chmod +x "$MEM/bin/probebin"
printf 'name = probetest\narchetype = file\nexec_cmd = echo {prompt}\nexec_probe = $MEMORY_DIR/bin/probebin\n' > "$MEM/harnesses/probetest/manifest"
export AI_MEMORY_EXECUTOR_TASK=probetest
run --role task --which
assert_eq "cli:probetest" "$OUT" "exec_probe with \$MEMORY_DIR is expanded before the availability check"
rm -f "$MEM/bin/probebin"
run --role task --which
assert_exit 1 "$CODE" "exec_probe path that does not exist is unavailable"

export PATH="$OLDPATH"
finish
