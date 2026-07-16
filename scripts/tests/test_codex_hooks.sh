#!/usr/bin/env bash
# Codex hybrid hooks.json registration: Codex schema, idempotency, and
# fail-closed merge behavior for invalid existing files.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
TMP="$(new_sandbox)"
trap 'rm -rf "$TMP"' EXIT

. "$REPO/scripts/manifest.sh"

MANIFEST="$REPO/harnesses/codex/manifest"
MEMORY_DIR="$REPO"
HARNESS=codex
step() { :; }
info() { :; }
link() { :; }
. "$REPO/scripts/drivers/hook.sh"

if ! command -v python3 >/dev/null 2>&1; then
    printf '  SKIP python3 absent; Codex hooks_json merge tests not run\n'
    finish
fi

HOOKS="$TMP/hooks.json"
_hook_register_codex_json "$HOOKS"
_hook_register_codex_json "$HOOKS"

PYOUT="$TMP/python.out"
PRODUCED="$HOOKS" REPO="$REPO" python3 - <<'PY' >"$PYOUT" 2>&1
import json, os, sys
repo = os.environ["REPO"]
with open(os.environ["PRODUCED"]) as f:
    data = json.load(f)
hooks = data.get("hooks")
if not isinstance(hooks, dict):
    sys.stderr.write("missing top-level hooks object\n")
    sys.exit(1)
ups = hooks.get("UserPromptSubmit")
ptu = hooks.get("PreToolUse")
if not isinstance(ups, list) or not ups:
    sys.stderr.write("missing UserPromptSubmit array\n")
    sys.exit(1)
if not isinstance(ptu, list) or not ptu:
    sys.stderr.write("missing PreToolUse array\n")
    sys.exit(1)
guard_cmd = ptu[0]["hooks"][0]["command"]
inject_entries = [
    g for g in ups
    if any("scripts/hooks/inject.sh" in h.get("command", "") for h in g.get("hooks", []) if isinstance(h, dict))
]
if len(inject_entries) != 8:
    sys.stderr.write("idempotency/count failure: inject=%d\n" % len(inject_entries))
    sys.exit(1)
for g in inject_entries:
    if "matcher" in g:
        sys.stderr.write("UserPromptSubmit group unexpectedly has matcher\n")
        sys.exit(1)
inject_cmds = [g["hooks"][0]["command"] for g in inject_entries]
inject_cmd = inject_cmds[0]
checks = [
    ("inject path", "scripts/hooks/inject.sh" in inject_cmd),
    ("md format", "AI_MEMORY_HOOK_FORMAT=md" in inject_cmd),
    ("memory dir", "MEMORY_DIR=" in inject_cmd),
    ("hook event", "AI_MEMORY_HOOK_EVENT=UserPromptSubmit" in inject_cmd),
    ("chunk", "AI_MEMORY_HOOK_CHUNK=1/8" in inject_cmd),
    ("guard matcher", ptu[0].get("matcher") == "^Bash$|apply_patch"),
    ("guard path", "scripts/hooks/guard.sh" in guard_cmd),
]
for label, ok in checks:
    if not ok:
        sys.stderr.write("failed check: %s\n" % label)
        sys.exit(1)
guard_entries = [
    g for g in ptu
    if any("scripts/hooks/guard.sh" in h.get("command", "") for h in g.get("hooks", []) if isinstance(h, dict))
]
if len(guard_entries) != 1:
    sys.stderr.write("idempotency failure: inject=%d guard=%d\n" % (len(inject_entries), len(guard_entries)))
    sys.exit(1)
expected_inject = [
    "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=md AI_MEMORY_HOOK_EVENT=UserPromptSubmit AI_MEMORY_HOOK_CHUNK=%d/8 bash %s/scripts/hooks/inject.sh" % (repo, i, repo)
    for i in range(1, 9)
]
expected_guard = "env MEMORY_DIR=%s bash %s/scripts/hooks/guard.sh" % (repo, repo)
if inject_cmds != expected_inject:
    sys.stderr.write("inject command mismatch\nexpected=%r\nactual=%r\n" % (expected_inject, inject_cmds))
    sys.exit(1)
if guard_cmd != expected_guard:
    sys.stderr.write("guard command mismatch\nexpected=%r\nactual=%r\n" % (expected_guard, guard_cmd))
    sys.exit(1)
# session_bootstrap: SessionStart entry registered exactly once, format-wrapped for md
# (post-flip codex injects the base via the shared session-start script), no matcher.
ss = hooks.get("SessionStart")
if not isinstance(ss, list) or not ss:
    sys.stderr.write("missing SessionStart array\n")
    sys.exit(1)
session_entries = [
    g for g in ss
    if any("scripts/hooks/session_start_memory.sh" in h.get("command", "") for h in g.get("hooks", []) if isinstance(h, dict))
]
if len(session_entries) != 8:
    sys.stderr.write("idempotency failure: session=%d\n" % len(session_entries))
    sys.exit(1)
for g in session_entries:
    if "matcher" in g:
        sys.stderr.write("SessionStart session group unexpectedly has matcher\n")
        sys.exit(1)
session_cmds = [g["hooks"][0]["command"] for g in session_entries]
expected_session = [
    "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=md AI_MEMORY_HOOK_EVENT=SessionStart AI_MEMORY_HOOK_CHUNK=%d/8 bash %s/scripts/hooks/session_start_memory.sh" % (repo, i, repo)
    for i in range(1, 9)
]
if session_cmds != expected_session:
    sys.stderr.write("session command mismatch\nexpected=%r\nactual=%r\n" % (expected_session, session_cmds))
    sys.exit(1)
# The old arm_recompact.sh must NOT be wired by the flipped manifest (it survives only as
# a compatibility shim reachable via a stale pre-flip hooks.json, not a fresh registration).
if any("arm_recompact.sh" in h.get("command", "") for g in ss for h in g.get("hooks", []) if isinstance(h, dict)):
    sys.stderr.write("flipped codex manifest still wires arm_recompact.sh\n")
    sys.exit(1)
PY
rc=$?
if [ "$rc" -eq 0 ]; then
    _ok "codex hooks_json schema and idempotency"
else
    _bad "codex hooks_json schema and idempotency"
    cat "$PYOUT"
fi

# Legacy orphan sweep: a pre-P3 hooks.json carrying a stale inject_memory.sh entry
# (symlink-in-HOME era) must be swept on re-sync, not left dangling. Guards the
# `ours`-tuple fix for the double-injection bug hit live 2026-07-14.
LEGACY="$TMP/legacy-hooks.json"
cat > "$LEGACY" <<'JSON'
{
  "hooks": {
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "bash /Users/x/.claude/hooks/inject_memory.sh" } ] }
    ]
  }
}
JSON
_hook_register_codex_json "$LEGACY"
assert_eq "0" "$(grep -c 'inject_memory.sh' "$LEGACY")" \
    "codex hooks_json: legacy inject_memory.sh entry swept on re-sync"
assert_eq "8" "$(grep -c 'scripts/hooks/inject.sh' "$LEGACY")" \
    "codex hooks_json: current chunked inject.sh entries present after sweep"

BAD="$TMP/bad-hooks.json"
printf '[1, 2, 3]\n' > "$BAD"
set +e
_hook_register_codex_json "$BAD" >"$TMP/bad.out" 2>"$TMP/bad.err"
rc=$?
set -e
assert_exit 3 "$rc" "codex hooks_json top-level array: public writer fails"
assert_eq "[1, 2, 3]" "$(cat "$BAD")" "codex hooks_json top-level array: file untouched"
assert_eq "0" "$(find "$TMP" -name 'bad-hooks.json.bak-*' | grep -c .)" \
    "codex hooks_json top-level array: no backup written"
assert_contains "$(cat "$TMP/bad.err")" "not a JSON object" "codex hooks_json top-level array: says why it refused"

# --- Phase 1: session_bootstrap command is format-wrapped from the manifest `format` ---
# The real codex manifest still wires SessionStart -> arm_recompact (compaction_arm); the
# session_bootstrap md path lands when Phase 3 flips the manifest. Prove the engine threads
# format=md into the SessionStart command NOW, via a synthetic manifest, so the fix is
# guarded independently of that flip.
SYN_MF="$TMP/synthetic-md.manifest"
SYN_SCRIPT="$TMP/session_start_stub.sh"
: > "$SYN_SCRIPT"
cat > "$SYN_MF" <<EOF
name           = synthetic
format         = md
session_script = $SYN_SCRIPT

[hooks]
session_bootstrap = SessionStart
EOF
SYN_HOOKS="$TMP/synthetic-hooks.json"
MANIFEST="$SYN_MF" _hook_register_native_json "$SYN_HOOKS"
SYN_CMD="$(SYN_HOOKS="$SYN_HOOKS" python3 - <<'PY'
import json, os
with open(os.environ["SYN_HOOKS"]) as f:
    data = json.load(f)
print(data["hooks"]["SessionStart"][0]["hooks"][0]["command"])
PY
)"
assert_contains "$SYN_CMD" "AI_MEMORY_HOOK_FORMAT=md" \
    "session_bootstrap: SessionStart command carries md format from manifest"
assert_contains "$SYN_CMD" "AI_MEMORY_HOOK_EVENT=SessionStart" \
    "session_bootstrap: SessionStart command carries the event name"
assert_contains "$SYN_CMD" "bash $SYN_SCRIPT" \
    "session_bootstrap: SessionStart command points at session_script"

finish
