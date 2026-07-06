#!/usr/bin/env bash
# Antigravity hook archetype. agy.sh resolves the active project from the launch
# cwd and exports it (+ MEMORY_DIR + cwd) into agy's env — the PreInvocation hook
# has no workspace handle and reads these. preinvocation.sh emits injectSteps:
# full payload on invocationNum 0, the <memory:active> breadcrumb after, and
# dormant ({"injectSteps":[]}) with no project. Stub `agy` on PATH; no real binary.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
WRAP="$REPO/harnesses/antigravity/scripts/agy.sh"
HOOK="$REPO/harnesses/antigravity/hooks/preinvocation.sh"

MEM="$(new_sandbox)"; BIN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOF
printf 'working note\n' > "$MEM/projects/proj/working.md"
WORK="$MEM/work"; mkdir -p "$WORK/.agents"; printf 'proj\n' > "$WORK/.agents/memory-project"

# --- agy.sh: stub agy records its args AND the env agy.sh exported ---
CAP="$BIN/agy-args"; ENVCAP="$BIN/agy-env"
cat > "$BIN/agy" <<EOF
#!/usr/bin/env bash
printf '%s ' "\$@" > "$CAP"
{ printf 'PROJECT=%s\n' "\${AI_MEMORY_PROJECT:-}"
  printf 'CWD=%s\n'     "\${AI_MEMORY_CWD:-}"
  printf 'MEMORY_DIR=%s\n' "\${MEMORY_DIR:-}"; } > "$ENVCAP"
exit 0
EOF
chmod +x "$BIN/agy"
export PATH="$BIN:$PATH"

set +e
(cd "$WORK" && bash "$WRAP" -p "do the thing" --model gpt-x) >/dev/null 2>&1; CODE=$?
set -e
assert_exit 0 "$CODE" "agy.sh exits 0 via stub"
args="$(cat "$CAP")"
assert_contains "$args" "-p do the thing" "agy.sh passes the prompt through"
assert_contains "$args" "--model gpt-x"   "agy.sh passes the model flag through"
env_dump="$(cat "$ENVCAP")"
assert_contains "$env_dump" "PROJECT=proj"    "agy.sh exports resolved AI_MEMORY_PROJECT"
assert_contains "$env_dump" "CWD=$WORK"       "agy.sh exports the launch cwd"
assert_contains "$env_dump" "MEMORY_DIR=$MEM" "agy.sh exports MEMORY_DIR"

# --- agy.sh: missing agy binary -> clear error, no exec ---
set +e
(PATH="/usr/bin:/bin" bash "$WRAP" -p x) >/dev/null 2>&1; CODE=$?
set -e
assert_exit 1 "$CODE" "agy.sh errors when agy is absent"

# --- preinvocation.sh: inject payload by invocationNum + project ---
run_hook() { # run_hook <invnum> <project> ; sets OUT
    OUT="$(printf '{"invocationNum":%s}' "$1" \
        | AI_MEMORY_PROJECT="$2" AI_MEMORY_CWD="$WORK" MEMORY_DIR="$MEM" bash "$HOOK")"
}

# invocationNum 0 -> full payload
run_hook 0 proj
assert_contains "$OUT" '"injectSteps"'      "hook 0: emits injectSteps"
assert_contains "$OUT" 'ephemeralMessage'   "hook 0: uses ephemeralMessage"
assert_contains "$OUT" 'memory:identity'    "hook 0: full payload has identity"
assert_contains "$OUT" 'memory:project name=' "hook 0: full payload has project section"
assert_contains "$OUT" 'Project: proj'      "hook 0: full payload inlines the project body"

# later invocation -> lightweight breadcrumb (paths + re-read directive, no body)
run_hook 1 proj
assert_contains "$OUT" 'memory:active project=' "hook 1: emits the active breadcrumb"
assert_contains "$OUT" 'read them before proceeding' "hook 1: breadcrumb carries the re-read directive"
case "$OUT" in
    *"Project: proj"*) _bad "hook 1: breadcrumb should not inline the project body" ;;
    *) _ok "hook 1: breadcrumb omits the full body" ;;
esac

# no active project -> dormant
run_hook 0 ""
assert_eq '{"injectSteps":[]}' "$OUT" "hook: no project -> empty injectSteps"

# emitted payload is valid JSON
if command -v python3 >/dev/null 2>&1; then
    run_hook 0 proj
    if printf '%s' "$OUT" | python3 -m json.tool >/dev/null 2>&1; then
        _ok "hook 0: output parses as JSON"
    else
        _bad "hook 0: output is not valid JSON"
    fi
fi

finish
