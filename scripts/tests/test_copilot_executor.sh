#!/usr/bin/env bash
# GitHub Copilot executor face. Uses fake copilot/gh binaries on PATH; no real
# API calls, HOME, or Copilot config are touched.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
EXE="$REPO/scripts/executor.sh"
WRAP="$REPO/harnesses/copilot/scripts/copilot-mem.sh"

MEM="$(new_sandbox)"
BIN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

mkdir -p "$MEM/harnesses/copilot/scripts"
cp "$REPO/harnesses/copilot/manifest" "$MEM/harnesses/copilot/manifest"
cp "$WRAP" "$MEM/harnesses/copilot/scripts/copilot-mem.sh"
chmod +x "$MEM/harnesses/copilot/scripts/copilot-mem.sh"
export AI_MEMORY_HARNESSES_DIR="$MEM/harnesses"

CAP="$BIN/copilot-args"
ENVCAP="$BIN/copilot-env"
STDINCAP="$BIN/copilot-stdin"
cat > "$BIN/copilot" <<EOF
#!/bin/sh
stdin_bytes=0
if IFS= read -r line; then
  stdin_bytes=nonzero
elif [ -n "\$line" ]; then
  stdin_bytes=nonzero
fi
printf '%s\n' "\$stdin_bytes" > "$STDINCAP"
printf '%s\n' "\$@" > "$CAP"
{
  printf 'ROLE=%s\n' "\${AI_MEMORY_ROLE:-}"
  printf 'GH_TOKEN=%s\n' "\${GH_TOKEN:-}"
} > "$ENVCAP"
if [ -n "\${FAKE_COPILOT_RC:-}" ]; then
  exit "\$FAKE_COPILOT_RC"
fi
printf 'FAKE-COPILOT-OUT\n'
exit 0
EOF
chmod +x "$BIN/copilot"

cat > "$BIN/gh" <<EOF
#!/usr/bin/env bash
printf 'called\n' >> "$BIN/gh-called"
if [ "\$1" = auth ] && [ "\$2" = token ]; then
  printf 'FAKE-GH-TOKEN'
  exit 0
fi
exit 2
EOF
chmod +x "$BIN/gh"

OLDPATH="$PATH"
export PATH="$BIN:$PATH"

run() {
    local tmp_out tmp_err
    tmp_out="$BIN/.out"; tmp_err="$BIN/.err"
    set +e
    env -u COPILOT_GITHUB_TOKEN -u GH_TOKEN -u GITHUB_TOKEN \
        bash "$EXE" "$@" >"$tmp_out" 2>"$tmp_err"
    CODE=$?
    set -e
    OUT="$(cat "$tmp_out")"
    ERR="$(cat "$tmp_err")"
}

export AI_MEMORY_EXECUTOR=copilot
export AI_MEMORY_EXECUTOR_FALLBACK=""
unset AI_MEMORY_EXECUTOR_TASK AI_MEMORY_EXECUTOR_EXPLORE AI_MEMORY_EXECUTOR_VALIDATE

run --role task --which
assert_exit 0 "$CODE" "task --which exits 0"
assert_eq "cli:copilot" "$OUT" "task --which resolves to cli:copilot"

run --role explore --which
assert_exit 0 "$CODE" "explore --which exits 0"
assert_eq "cli:copilot" "$OUT" "explore --which resolves to cli:copilot"

run --role task --run "task prompt"
assert_exit 0 "$CODE" "task --run exits 0 via fake copilot"
assert_eq "FAKE-COPILOT-OUT" "$OUT" "task --run streams fake copilot stdout"
args="$(cat "$CAP")"
assert_contains "$args" "-p" "task: passes -p"
assert_contains "$args" "task prompt" "task: passes prompt"
assert_contains "$args" "--allow-all" "task: passes --allow-all"
assert_contains "$args" "--silent" "task: passes --silent"
assert_contains "$args" "--stream" "task: passes --stream flag"
assert_contains "$args" "off" "task: disables stream"
assert_contains "$args" "--no-color" "task: disables color"
assert_contains "$args" "--no-auto-update" "task: disables auto-update"
assert_contains "$(cat "$ENVCAP")" "ROLE=task" "task: AI_MEMORY_ROLE reaches copilot"
assert_contains "$(cat "$ENVCAP")" "GH_TOKEN=FAKE-GH-TOKEN" "task: wrapper exports gh auth token fallback"
assert_eq "0" "$(cat "$STDINCAP")" "task: wrapper closes stdin"

export AI_MEMORY_EXECUTOR="copilot:gpt-5-mini"
run --role task --run "model prompt"
assert_exit 0 "$CODE" "task --run with model exits 0"
args="$(cat "$CAP")"
assert_contains "$args" "--model" "task: model flag name is passed"
assert_contains "$args" "gpt-5-mini" "task: configured model is passed"
export AI_MEMORY_EXECUTOR=copilot

run --role explore --run "explore prompt"
assert_exit 0 "$CODE" "explore --run exits 0 via fake copilot"
args="$(cat "$CAP")"
assert_contains "$args" "-p" "explore: passes -p"
assert_contains "$args" "explore prompt" "explore: passes prompt"
assert_contains "$args" "--available-tools=view,grep,glob" "explore: passes read-only tool allowlist"
assert_contains "$args" "--allow-all-tools" "explore: passes pinned read-only approval flag"
assert_contains "$args" "--allow-all-paths" "explore: passes pinned path approval flag"
assert_contains "$args" "--allow-all-urls" "explore: passes pinned URL approval flag"
if grep -Fx -- "--allow-all" "$CAP" >/dev/null 2>&1; then
    _bad "explore: does not pass task-only --allow-all"
else
    _ok "explore: does not pass task-only --allow-all"
fi
assert_contains "$(cat "$ENVCAP")" "ROLE=explore" "explore: AI_MEMORY_ROLE reaches copilot"

# Direct wrapper auth fallback: gh token fills GH_TOKEN when no token env exists.
: > "$CAP"; : > "$ENVCAP"; : > "$BIN/gh-called"
set +e
env -u COPILOT_GITHUB_TOKEN -u GH_TOKEN -u GITHUB_TOKEN \
    bash "$WRAP" -p "auth prompt" >/dev/null 2>"$BIN/wrap.err"
CODE=$?
set -e
assert_exit 0 "$CODE" "wrapper: auth fallback run exits 0"
assert_contains "$(cat "$ENVCAP")" "GH_TOKEN=FAKE-GH-TOKEN" "wrapper: gh auth token populates GH_TOKEN"
assert_contains "$(cat "$BIN/gh-called")" "called" "wrapper: gh was called when no token env existed"

# Wrapper still execs copilot when gh is absent from PATH.
NOGH_BIN="$(new_sandbox)"
cp "$BIN/copilot" "$NOGH_BIN/copilot"
chmod +x "$NOGH_BIN/copilot"
: > "$CAP"; : > "$ENVCAP"; : > "$STDINCAP"; rm -f "$BIN/gh-called"
set +e
env -u COPILOT_GITHUB_TOKEN -u GH_TOKEN -u GITHUB_TOKEN PATH="$NOGH_BIN" \
    /bin/bash "$WRAP" -p "no gh prompt" >"$BIN/no-gh.out" 2>"$BIN/no-gh.err"
CODE=$?
set -e
assert_exit 0 "$CODE" "wrapper: no gh on PATH still exits 0"
assert_eq "FAKE-COPILOT-OUT" "$(cat "$BIN/no-gh.out")" "wrapper: no gh on PATH still execs copilot"
assert_contains "$(cat "$CAP")" "no gh prompt" "wrapper: no gh path passes prompt"
assert_contains "$(cat "$ENVCAP")" "GH_TOKEN=" "wrapper: no gh path leaves GH_TOKEN empty"
if [ -e "$BIN/gh-called" ]; then
    _bad "wrapper: no gh path did not call fake gh"
else
    _ok "wrapper: no gh path did not call fake gh"
fi

# Existing token env wins; gh must not be called or overwrite GH_TOKEN.
: > "$CAP"; : > "$ENVCAP"; rm -f "$BIN/gh-called"
set +e
GH_TOKEN=PRESET-TOKEN bash "$WRAP" -p "auth prompt" >/dev/null 2>"$BIN/wrap.err"
CODE=$?
set -e
assert_exit 0 "$CODE" "wrapper: preset GH_TOKEN run exits 0"
assert_contains "$(cat "$ENVCAP")" "GH_TOKEN=PRESET-TOKEN" "wrapper: preset GH_TOKEN is preserved"
if [ -e "$BIN/gh-called" ]; then
    _bad "wrapper: gh not called when GH_TOKEN is preset"
else
    _ok "wrapper: gh not called when GH_TOKEN is preset"
fi

# Copilot's exit code is propagated by the exec wrapper.
set +e
FAKE_COPILOT_RC=7 bash "$WRAP" -p "exit prompt" >/dev/null 2>"$BIN/wrap.err"
CODE=$?
set -e
assert_exit 7 "$CODE" "wrapper: propagates copilot exit code"

# Wrapper closes stdin even if the caller pipes data into it.
: > "$STDINCAP"
set +e
printf 'caller stdin must not reach copilot' | bash "$WRAP" -p "stdin prompt" >/dev/null 2>"$BIN/wrap.err"
CODE=$?
set -e
assert_exit 0 "$CODE" "wrapper: piped stdin run exits 0"
assert_eq "0" "$(cat "$STDINCAP")" "wrapper: copilot receives zero stdin bytes"

OUT="$(bash "$REPO/scripts/validate-manifest.sh" "$REPO/harnesses/copilot/manifest" 2>&1)"; RC=$?
assert_exit 0 "$RC" "manifest: copilot manifest validates"
assert_not_contains "$OUT" "WARN" "manifest: copilot manifest has no warnings"

export PATH="$OLDPATH"
finish
