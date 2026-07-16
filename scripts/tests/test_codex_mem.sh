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

finish
