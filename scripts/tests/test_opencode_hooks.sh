#!/usr/bin/env bash
# opencode context hook script (harnesses/opencode/hooks/context.sh), driven by the
# REAL payloads captured from opencode v2.2.6 (scripts/tests/fixtures/opencode/):
# every `context` call emits the full payload ending in <memory:working>. The plugin (ai-memory.ts) is covered by the live smoke
# test in the P3 report, not here (needs a real opencode).
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
CTX="$REPO/harnesses/opencode/hooks/context.sh"
FIX="$SCRIPTS_DIR/tests/fixtures/opencode"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"
export MEMORY_STATE_DIR="$MEM/.sessions"
unset AI_MEMORY_SKIP_INJECT AI_MEMORY_HOOK_FORMAT
seed_min_tree "$MEM"
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOM'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOM
printf 'working note\n' > "$MEM/projects/proj/working.md"
WORK="$MEM/work"; mkdir -p "$WORK/.agents" "$MEM/bare"
printf 'proj\n' > "$WORK/.agents/memory-project"

SID_B="ses_other_session_0002"

# payload <fixture> <directory> [sessionID override]: the plugin's stdin envelope around a real event.
payload() {
    jq -c --arg d "$2" --arg s "${3:-}" '{directory:$d, sessionID:(if $s=="" then .sessionID else $s end), event:.}' "$FIX/$1"
}
ctx() { payload "$1" "${2:-$WORK}" "${3:-}" | bash "$CTX" 2>"$MEM/err"; }
is_full()  { case "$1" in *'<memory:identity>'*'<memory:working>'*) return 0 ;; esac; return 1; }

# --- every context call emits the full payload (opencode rebuilds event.system per
# model call and pushes do not persist, so a breadcrumb or "already sent" state would
# drop memory from call 2 onward) ---
out1="$(ctx context.json)"
is_full "$out1" && r=full || r=other
assert_eq full "$r" "opencode: first context call emits the full payload"
assert_eq '</memory:working>' "$(printf '%s' "$out1" | tail -n 1)" "opencode: full payload ends with the working section"
assert_contains "$out1" "working note" "opencode: full payload carries working.md"
assert_not_contains "$out1" "<memory:active" "opencode: payload is not the breadcrumb"

out2="$(ctx context.json)"
is_full "$out2" && r=full || r=other
assert_eq full "$r" "opencode: second context call of the same session ALSO emits the full payload"
assert_eq "$out1" "$out2" "opencode: consecutive calls emit identical payloads"
assert_eq '</memory:working>' "$(printf '%s' "$out2" | tail -n 1)" "opencode: second payload ends with the working section"
out3="$(ctx context-after-tool.json)"
is_full "$out3" && r=full || r=other
assert_eq full "$r" "opencode: context after a tool call (captured fixture) emits the full payload"

outB="$(ctx context.json "$WORK" "$SID_B")"
is_full "$outB" && r=full || r=other
assert_eq full "$r" "opencode: another sessionID also gets the full payload"
assert_not_file "$MEMORY_STATE_DIR" "opencode: no per-session state is written"

# --- live working.md edits surface on the next call ---
printf 'edited note\n' > "$MEM/projects/proj/working.md"
assert_contains "$(ctx context.json)" "edited note" "opencode: working.md edits surface on the next call"

# --- dormant / failing inputs degrade to nothing, exit 0 ---
assert_eq "" "$(ctx context.json "$MEM/bare" ses_noproject)" "opencode: no active project -> no injection"
assert_eq "" "$(cat "$MEM/err")" "opencode: no active project is silent dormancy, not a logged failure"
assert_eq "" "$(printf 'not json' | bash "$CTX" 2>/dev/null)" "opencode: malformed stdin -> no injection"
set +e; printf 'not json' | bash "$CTX" >/dev/null 2>&1; code=$?; set -e
assert_exit 0 "$code" "opencode: context.sh exits 0 on malformed input"
assert_eq "" "$(payload context.json "$WORK" | AI_MEMORY_SKIP_INJECT=1 bash "$CTX" 2>/dev/null)" "opencode: AI_MEMORY_SKIP_INJECT suppresses injection"
set +e
payload context.json "$WORK" | AI_MEMORY_HOOK_FORMAT=bogus bash "$CTX" >"$MEM/bad.out" 2>"$MEM/bad.err"; code=$?
set -e
assert_exit 0 "$code" "opencode: a failing payload build still exits 0"
assert_eq "" "$(cat "$MEM/bad.out")" "opencode: a failing payload build emits nothing"
assert_contains "$(cat "$MEM/bad.err")" "no injection" "opencode: a failing payload build is logged"

# --- plugin spawn timeout (B5): a hung guard denies, a hung context degrades to no injection ---
if command -v bun >/dev/null 2>&1; then
    HUNG="$MEM/hung"; mkdir -p "$HUNG/scripts/hooks" "$HUNG/harnesses/opencode/hooks"
    printf '#!/bin/sh\nsleep 30\n' > "$HUNG/scripts/hooks/guard.sh"
    printf '#!/bin/sh\nsleep 30\n' > "$HUNG/harnesses/opencode/hooks/context.sh"
    chmod +x "$HUNG/scripts/hooks/guard.sh" "$HUNG/harnesses/opencode/hooks/context.sh"
    cat > "$MEM/plugin-timeout.ts" <<EOT
import plugin from "$REPO/harnesses/opencode/plugin/ai-memory.ts"
const hooks: Record<string, any> = {}
await (plugin as any).setup({
  directory: "/tmp",
  session: { hook: async (n: string, f: any) => { hooks[n] = f } },
  tool: { hook: async (n: string, f: any) => { hooks[n] = f } },
})
const t0 = Date.now()
let denied = false
try { await hooks["execute.before"]({ tool: "shell", sessionID: "s", input: { command: "echo" } }) } catch (e) { denied = true }
const ev = { sessionID: "s", system: [] as any[] }
await hooks["context"](ev)
console.log(JSON.stringify({ denied, injected: ev.system.length, ms: Date.now() - t0 }))
EOT
    set +e; res="$(MEMORY_DIR="$HUNG" AI_MEMORY_PLUGIN_TIMEOUT_MS=500 bun run "$MEM/plugin-timeout.ts" 2>"$MEM/plugin.err" | tail -1)"; set -e
    assert_eq true "$(printf '%s' "$res" | jq -r .denied 2>/dev/null)" "plugin: a hung guard times out and the call is denied (fail closed)"
    assert_eq 0 "$(printf '%s' "$res" | jq -r .injected 2>/dev/null)" "plugin: a hung context script degrades to no injection"
    assert_eq true "$(printf '%s' "$res" | jq '.ms < 10000' 2>/dev/null)" "plugin: hung scripts are cut off by the timeout, not waited out"
    # H4: the override is accepted only as an integer 1..120000; anything else falls back to 15000 (logged)
    printf 'import plugin from "%s/harnesses/opencode/plugin/ai-memory.ts"\nvoid plugin\n' "$REPO" > "$MEM/plugin-import.ts"
    for bad in 120001 999999999 0 -5 1.5 1e3 abc "" ; do
        [ -n "$bad" ] || continue
        AI_MEMORY_PLUGIN_TIMEOUT_MS="$bad" bun run "$MEM/plugin-import.ts" >/dev/null 2>"$MEM/imp.err" || true
        assert_contains "$(cat "$MEM/imp.err")" "ignoring invalid AI_MEMORY_PLUGIN_TIMEOUT_MS" "plugin: timeout override '$bad' is rejected"
    done
    for ok in 1 500 120000; do
        AI_MEMORY_PLUGIN_TIMEOUT_MS="$ok" bun run "$MEM/plugin-import.ts" >/dev/null 2>"$MEM/imp.err" || true
        assert_not_contains "$(cat "$MEM/imp.err")" "ignoring invalid" "plugin: timeout override '$ok' is accepted"
    done
else
    echo "  skip plugin timeout test: bun not available"
fi

# fix round 4: the plugin sends context.sh only {directory, sessionID}, never the event (messages)
if command -v bun >/dev/null 2>&1; then
    SNIFF="$MEM/sniff"; mkdir -p "$SNIFF/scripts/hooks" "$SNIFF/harnesses/opencode/hooks"
    printf '#!/bin/sh\ncat > "%s/ctx.stdin"\n' "$SNIFF" > "$SNIFF/harnesses/opencode/hooks/context.sh"
    printf '#!/bin/sh\ncat >/dev/null\n' > "$SNIFF/scripts/hooks/guard.sh"
    chmod +x "$SNIFF/harnesses/opencode/hooks/context.sh" "$SNIFF/scripts/hooks/guard.sh"
    cat > "$MEM/plugin-sniff.ts" <<EOT
import plugin from "$REPO/harnesses/opencode/plugin/ai-memory.ts"
const hooks: Record<string, any> = {}
await (plugin as any).setup({
  directory: "/tmp",
  session: { hook: async (n: string, f: any) => { hooks[n] = f } },
  tool: { hook: async (n: string, f: any) => { hooks[n] = f } },
})
await hooks["context"]({ sessionID: "s1", system: [], messages: [{ secret: "BIGMESSAGE" }] })
EOT
    MEMORY_DIR="$SNIFF" bun run "$MEM/plugin-sniff.ts" >/dev/null 2>&1 || true
    assert_eq "directory,sessionID" "$(jq -r 'keys_unsorted | sort | join(",")' "$SNIFF/ctx.stdin" 2>/dev/null)" "plugin: context.sh stdin holds only directory and sessionID"
    assert_not_contains "$(cat "$SNIFF/ctx.stdin" 2>/dev/null)" "BIGMESSAGE" "plugin: context.sh stdin carries no messages"
fi

finish
