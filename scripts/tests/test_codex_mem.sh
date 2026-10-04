#!/usr/bin/env bash
# codex-mem.sh (post-flip wrapper): never writes AGENTS.md (the memory base
# injects live via the SessionStart hook), --executor flag expansion,
# --executor-bare injection suppression (AI_MEMORY_SKIP_INJECT=1 +
# project_doc_max_bytes=0). Uses a stub `codex` on PATH that records its args
# and the injection-gate env, so no real codex is needed.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
BIN="$(new_sandbox)"
FHOME="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN" "$FHOME"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

# Active project with non-empty working.md (irrelevant to the wrapper now, but a
# populated tree proves "no AGENTS.md" isn't just "nothing to render").
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOF
printf '# Working\n\nactive scratch\n' > "$MEM/projects/proj/working.md"
WORK="$MEM/work"; mkdir -p "$WORK/.agents"; printf 'proj\n' > "$WORK/.agents/memory-project"

# Stub codex that records args + the injection-gate env, then exits 0.
CAPTURE="$BIN/codex-args"
ENVCAP="$BIN/codex-env"
cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
printf '%s ' "\$@" > "$CAPTURE"
printf 'SKIP_INJECT=%s\n' "\${AI_MEMORY_SKIP_INJECT:-}" > "$ENVCAP"
exit 0
EOF
chmod +x "$BIN/codex"
export PATH="$BIN:$PATH"

# --- interactive: exec's codex, writes NO AGENTS.md (hand-owned static base) ---
set +e
(cd "$WORK" && HOME="$FHOME" bash "$SCRIPTS_DIR/../harnesses/codex/scripts/codex-mem.sh") >/dev/null 2>&1; CODE=$?
set -e
assert_exit 0 "$CODE" "codex-mem (interactive) exits 0 via stub"
if [ ! -e "$FHOME/.codex/AGENTS.md" ]; then
    _ok "interactive: AGENTS.md NOT written (hand-owned static base)"
else
    _bad "interactive: AGENTS.md NOT written (hand-owned static base)"
fi
assert_contains "$(cat "$ENVCAP")" "SKIP_INJECT=" "interactive: injection gate not set"
assert_not_contains "$(cat "$ENVCAP")" "SKIP_INJECT=1" "interactive: AI_MEMORY_SKIP_INJECT unset"

# --- executor mode: flag expansion captured by stub, injection stays on ---
: > "$CAPTURE"; : > "$ENVCAP"
set +e
(cd "$WORK" && HOME="$FHOME" bash "$SCRIPTS_DIR/../harnesses/codex/scripts/codex-mem.sh" --executor "do the thing") >/dev/null 2>&1; CODE=$?
set -e
assert_exit 0 "$CODE" "executor mode exits 0 via stub"
args="$(cat "$CAPTURE")"
assert_contains "$args" "exec --dangerously-bypass-hook-trust --sandbox workspace-write" "executor: exec + workspace-write + hook-trust bypass"
assert_contains "$args" "--skip-git-repo-check"          "executor: skip-git-repo-check"
assert_contains "$args" "sandbox_workspace_write.network_access=true" "executor: network access on"
assert_contains "$args" "do the thing"                   "executor: passes through the prompt"
assert_not_contains "$args" "project_doc_max_bytes"      "executor: repo docs not suppressed"
assert_not_contains "$(cat "$ENVCAP")" "SKIP_INJECT=1"   "executor: memory injection stays on"

# --- executor-bare: injection suppressed at BOTH levers ---
: > "$CAPTURE"; : > "$ENVCAP"
set +e
(cd "$WORK" && HOME="$FHOME" bash "$SCRIPTS_DIR/../harnesses/codex/scripts/codex-mem.sh" --executor-bare "lean review") >/dev/null 2>&1; CODE=$?
set -e
assert_exit 0 "$CODE" "executor-bare exits 0 via stub"
bargs="$(cat "$CAPTURE")"
assert_contains "$bargs" "project_doc_max_bytes=0" "bare: hand-owned AGENTS.md / repo docs suppressed"
assert_contains "$(cat "$ENVCAP")" "SKIP_INJECT=1"  "bare: AI_MEMORY_SKIP_INJECT=1 exported to codex"
if [ ! -e "$FHOME/.codex/AGENTS.md" ]; then
    _ok "bare: AGENTS.md NOT written"
else
    _bad "bare: AGENTS.md NOT written"
fi

# --- validator mode: scratch-dir sandbox, repo never writable, scratch removed on exit ---
cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
printf '%s ' "\$@" > "$CAPTURE"
printf 'GOCACHE=%s\nGOTMPDIR=%s\n' "\${GOCACHE:-}" "\${GOTMPDIR:-}" > "$ENVCAP"
exit "\${STUB_EXIT:-0}"
EOF
chmod +x "$BIN/codex"
for want in 0 7; do
    : > "$CAPTURE"; : > "$ENVCAP"
    set +e
    (cd "$WORK" && HOME="$FHOME" STUB_EXIT=$want bash "$SCRIPTS_DIR/../harnesses/codex/scripts/codex-mem.sh" --validator "check it") >/dev/null 2>&1; CODE=$?
    set -e
    assert_exit "$want" "$CODE" "validator: codex exit $want propagated"
    vargs="$(cat "$CAPTURE")"
    scratch="${vargs##*-C }"; scratch="${scratch%% *}"
    assert_contains "$vargs" "--sandbox workspace-write" "validator($want): workspace-write sandbox"
    assert_contains "$vargs" "check it"                  "validator($want): passes through the prompt"
    assert_not_contains "$vargs" 'writable_roots=["'     "validator($want): no non-empty writable_roots"
    assert_contains "$vargs" "sandbox_workspace_write.network_access=false" "validator($want): network_access pinned off"
    assert_contains "$vargs" "sandbox_workspace_write.writable_roots=[]"    "validator($want): writable_roots pinned empty"
    assert_not_contains "$vargs" "network_access=true"   "validator($want): network stays off"
    case "$scratch" in
        ""|"$WORK"*|"$MEM"*) _bad "validator($want): scratch is outside the repo" ;;
        *) _ok "validator($want): scratch is outside the repo" ;;
    esac
    assert_contains "$(cat "$ENVCAP")" "GOCACHE=$scratch/"      "validator($want): GOCACHE under scratch"
    assert_contains "$(cat "$ENVCAP")" "GOTMPDIR=$scratch/"     "validator($want): GOTMPDIR under scratch"
    if [ -n "$scratch" ] && [ ! -e "$scratch" ]; then
        _ok "validator($want): scratch removed after exit"
    else
        _bad "validator($want): scratch removed after exit"
    fi
done

# --- validator mode: TERM to the wrapper stops codex and removes scratch (exit 143) ---
PIDF="$BIN/stub-pid"; : > "$PIDF"; : > "$CAPTURE"
cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
printf '%s ' "\$@" > "$CAPTURE"
echo \$\$ > "$PIDF"
exec sleep 30
EOF
chmod +x "$BIN/codex"
(cd "$WORK" && HOME="$FHOME" exec bash "$SCRIPTS_DIR/../harnesses/codex/scripts/codex-mem.sh" --validator "sleepy") >/dev/null 2>&1 &
WPID=$!
for _ in $(seq 1 50); do [ -s "$PIDF" ] && [ -s "$CAPTURE" ] && break; sleep 0.1; done
SPID="$(cat "$PIDF")"
sargs="$(cat "$CAPTURE")"; sscratch="${sargs##*-C }"; sscratch="${sscratch%% *}"
sleep 0.2
kill -TERM "$WPID" 2>/dev/null || true
for _ in $(seq 1 50); do
    kill -0 "$WPID" 2>/dev/null || break
    sleep 0.1
done
if kill -0 "$WPID" 2>/dev/null; then
    WCODE=hung; kill -KILL "$WPID" 2>/dev/null || true
else
    set +e; wait "$WPID"; WCODE=$?; set -e
fi
if [ -n "$SPID" ] && ! kill -0 "$SPID" 2>/dev/null; then
    _ok "validator signal: codex child gone after TERM"
else
    _bad "validator signal: codex child gone after TERM"
    [ -n "$SPID" ] && kill -KILL "$SPID" 2>/dev/null || true
fi
if [ -n "$sscratch" ] && [ ! -e "$sscratch" ]; then
    _ok "validator signal: scratch removed"
else
    _bad "validator signal: scratch removed"
    [ -n "$sscratch" ] && rm -rf "$sscratch"
fi
assert_exit 143 "$WCODE" "validator signal: wrapper exits 143"

finish
