#!/usr/bin/env bash
# Data-driven hook role maps in harness manifests.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
. "$REPO/scripts/manifest.sh"

AGY_MF="$REPO/harnesses/antigravity/manifest"
CLAUDE_MF="$REPO/harnesses/claude/manifest"

expected="$(printf 'per_turn_inject\tPreInvocation\ninfra_guard\tPreToolUse:*')"
actual="$(manifest_hooks "$AGY_MF")"
assert_eq "$expected" "$actual" "antigravity manifest_hooks emits role/event map"

expected="$(printf 'session_bootstrap\tSessionStart\nper_turn_inject\tUserPromptSubmit\ntask_tool_block\tPreToolUse:TaskCreate|TaskUpdate')"
actual="$(manifest_hooks "$CLAUDE_MF")"
assert_eq "$expected" "$actual" "claude manifest_hooks emits role/event map"

assert_eq "" "$(manifest_get "$AGY_MF" per_turn_inject)" "section key does not leak through manifest_get"
keys="$(manifest_keys "$AGY_MF")"
assert_not_contains "$keys" "per_turn_inject" "section key per_turn_inject does not leak through manifest_keys"
assert_not_contains "$keys" "infra_guard" "section key infra_guard does not leak through manifest_keys"
assert_eq "antigravity" "$(manifest_get "$AGY_MF" name)" "top-level manifest key remains readable"

if command -v python3 >/dev/null 2>&1; then
    TMP="$(new_sandbox)"
    trap 'rm -rf "$TMP"' EXIT
    MANIFEST="$AGY_MF"
    MEMORY_DIR="$REPO"
    HARNESS=antigravity
    step() { :; }
    info() { :; }
    link() { :; }
    . "$REPO/scripts/drivers/hook.sh"

    _hook_register_json "$TMP/hooks.json"
    PYOUT="$TMP/python.out"
    PRODUCED="$TMP/hooks.json" REPO="$REPO" python3 - <<'PY' >"$PYOUT" 2>&1
import json, os, sys
repo = os.environ["REPO"]
with open(os.environ["PRODUCED"]) as f:
    actual_raw = f.read()
actual = json.loads(actual_raw)
expected = {
    "ai-memory-inject": {
        "PreInvocation": [
            {
                "type": "command",
                "command": "bash %s/harnesses/antigravity/hooks/preinvocation.sh" % repo,
            }
        ]
    },
    "ai-memory-guard": {
        "PreToolUse": [
            {
                "matcher": "*",
                "hooks": [
                    {
                        "type": "command",
                        "command": "bash %s/harnesses/antigravity/hooks/pretooluse.sh" % repo,
                    }
                ],
            }
        ]
    },
}
if actual != expected:
    sys.stderr.write("JSON mismatch\nexpected=%r\nactual=%r\n" % (expected, actual))
    sys.exit(1)
expected_raw = json.dumps(expected, indent=2) + "\n"
if actual_raw != expected_raw:
    sys.stderr.write("raw JSON rendering differs from old hardcoded json.dump output\n")
    sys.exit(1)
guard = actual["ai-memory-guard"]["PreToolUse"][0]
if guard.get("matcher") != "*":
    sys.stderr.write("matcher was %r\n" % guard.get("matcher"))
    sys.exit(1)
if "PreInvocation" not in actual["ai-memory-inject"]:
    sys.stderr.write("missing PreInvocation event\n")
    sys.exit(1)
if "PreToolUse" not in actual["ai-memory-guard"]:
    sys.stderr.write("missing PreToolUse event\n")
    sys.exit(1)
PY
    rc=$?
    if [ "$rc" -eq 0 ]; then
        _ok "antigravity hooks_json matches old hardcoded structure"
    else
        _bad "antigravity hooks_json matches old hardcoded structure"
        cat "$PYOUT"
    fi
else
    printf '  SKIP antigravity hooks_json byte-identity check (python3 unavailable)\n'
fi

finish
