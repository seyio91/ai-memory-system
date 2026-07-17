#!/usr/bin/env bash
# GitHub Copilot delivery face: sessionStart adapter envelope + owned hooks file
# registration. Uses real Phase 0 stdin fixtures; no real Copilot binary or HOME.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
HOOK="$REPO/harnesses/copilot/hooks/sessionstart.sh"
PRECOMPACT="$REPO/harnesses/copilot/hooks/precompact.sh"
POSTTOOL="$REPO/harnesses/copilot/hooks/posttooluse.sh"
FIXTURE="$REPO/scripts/tests/fixtures/copilot/session_start_camel.json"
PRE_TOOL_FIXTURE="$REPO/scripts/tests/fixtures/copilot/pre_tool_use_bash.json"
PRE_COMPACT_FIXTURE="$REPO/scripts/tests/fixtures/copilot/pre_compact.json"
POST_TOOL_FIXTURE="$REPO/scripts/tests/fixtures/copilot/post_tool_use_bash.json"
TMP="$(new_sandbox)"
MEM="$(new_sandbox)"
trap 'rm -rf "$TMP" "$MEM"' EXIT

seed_min_tree "$MEM"
mkdir -p "$MEM/scripts"
cp "$REPO/scripts/_lib.sh" "$MEM/scripts/_lib.sh"
mkdir -p "$MEM/projects/copilotproj"
cat > "$MEM/projects/copilotproj/memory.md" <<'EOF'
---
topic: copilotproj
scope: project
summary: Copilot project summary
---
# Project: copilotproj

COPILOT-PROJECT-MARKER
EOF
printf '# Working\n\nCOPILOT-WORKING-MARKER\n' > "$MEM/projects/copilotproj/working.md"
cat > "$MEM/projects/copilotproj/todo.md" <<'EOF'
# Todo

- [ ] first open item
- [x] completed item

```
- [ ] fenced example only
```

- [ ] second open item
EOF

# Rewrite the fixture's captured absolute cwd to a path inside this test's own
# sandbox — never materialize (or clean up) the literal recorded path, which on
# the capture machine is a live directory outside the sandbox.
FIXTURE_CWD="$TMP/probe-cwd"
mkdir -p "$FIXTURE_CWD/.agents"
printf 'copilotproj\n' > "$FIXTURE_CWD/.agents/memory-project"
ORIG_CWD="$(sed -n 's/.*"cwd": "\(.*\)",/\1/p' "$FIXTURE" | head -1)"
sed "s|$ORIG_CWD|$FIXTURE_CWD|" "$FIXTURE" > "$TMP/session_start_camel.json"

STATE_DIR="$TMP/state"
mkdir -p "$STATE_DIR"

OUT="$(MEMORY_DIR="$MEM" bash "$HOOK" < "$TMP/session_start_camel.json")"
assert_contains "$OUT" '"additionalContext"' "sessionstart: emits Copilot flat additionalContext"
assert_not_contains "$OUT" "hookSpecificOutput" "sessionstart: does not emit Claude hookSpecificOutput"
assert_contains "$OUT" "COPILOT-PROJECT-MARKER" "sessionstart: payload contains project memory"
assert_contains "$OUT" "COPILOT-WORKING-MARKER" "sessionstart: payload contains working memory"

if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$OUT" | python3 -m json.tool >/dev/null 2>&1
    assert_exit 0 "$?" "sessionstart: output is valid JSON"
    OUT="$OUT" python3 - <<'PY' >"$TMP/adapter-check.out" 2>&1
import json, os, sys
data = json.loads(os.environ["OUT"])
ctx = data.get("additionalContext")
if not isinstance(ctx, str):
    sys.stderr.write("additionalContext is not a string\n")
    sys.exit(1)
for needle in ("# Identity", "# Project: copilotproj", "COPILOT-PROJECT-MARKER"):
    if needle not in ctx:
        sys.stderr.write("missing %s\n" % needle)
        sys.exit(1)
PY
    rc=$?
    if [ "$rc" -eq 0 ]; then
        _ok "sessionstart: additionalContext string carries full md payload"
    else
        _bad "sessionstart: additionalContext string carries full md payload"
        cat "$TMP/adapter-check.out"
    fi
fi

# No pinned project -> dormant empty object, not an empty additionalContext string.
NO_PROJECT="$(printf '{"cwd":"%s/no-marker"}' "$TMP" | MEMORY_DIR="$MEM" bash "$HOOK")"
assert_eq '{}' "$NO_PROJECT" "sessionstart: no project -> empty object"

PRE_COMPACT_CWD="$TMP/precompact-cwd"
mkdir -p "$PRE_COMPACT_CWD"
ORIG_PRE_COMPACT_CWD="$(sed -n 's/.*"cwd": "\(.*\)",/\1/p' "$PRE_COMPACT_FIXTURE" | head -1)"
PRE_COMPACT_ID="$(sed -n 's/.*"sessionId": "\(.*\)",/\1/p' "$PRE_COMPACT_FIXTURE" | head -1)"
sed "s|$ORIG_PRE_COMPACT_CWD|$PRE_COMPACT_CWD|" "$PRE_COMPACT_FIXTURE" > "$TMP/pre_compact.json"

OUT="$(MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$PRECOMPACT" < "$TMP/pre_compact.json")"; RC=$?
assert_exit 0 "$RC" "precompact: exits 0 for real fixture"
assert_eq '{}' "$OUT" "precompact: emits empty object"
assert_file "$STATE_DIR/$PRE_COMPACT_ID.recompact" "precompact: writes shared recompact sentinel"

OUT="$(printf 'not json' | MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$PRECOMPACT")"; RC=$?
assert_exit 0 "$RC" "precompact: malformed stdin exits 0"
assert_eq '{}' "$OUT" "precompact: malformed stdin emits empty object"
OUT="$(printf '' | MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$PRECOMPACT")"; RC=$?
assert_exit 0 "$RC" "precompact: empty stdin exits 0"
assert_eq '{}' "$OUT" "precompact: empty stdin emits empty object"

POST_TOOL_CWD="$TMP/posttool-cwd"
mkdir -p "$POST_TOOL_CWD/.agents"
printf 'copilotproj\n' > "$POST_TOOL_CWD/.agents/memory-project"
ORIG_POST_TOOL_CWD="$(sed -n 's/.*"cwd": "\(.*\)",/\1/p' "$POST_TOOL_FIXTURE" | head -1)"
POST_TOOL_ID="$(sed -n 's/.*"sessionId": "\(.*\)",/\1/p' "$POST_TOOL_FIXTURE" | head -1)"
sed "s|$ORIG_POST_TOOL_CWD|$POST_TOOL_CWD|" "$POST_TOOL_FIXTURE" > "$TMP/post_tool_use_bash.json"

: > "$STATE_DIR/$POST_TOOL_ID.recompact"
OUT="$(MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$POSTTOOL" < "$TMP/post_tool_use_bash.json")"; RC=$?
assert_exit 0 "$RC" "posttooluse: armed sentinel exits 0"
assert_contains "$OUT" '"additionalContext"' "posttooluse: armed sentinel emits additionalContext"
assert_contains "$OUT" "COPILOT-PROJECT-MARKER" "posttooluse: payload contains project marker"
if [ ! -e "$STATE_DIR/$POST_TOOL_ID.recompact" ]; then
    _ok "posttooluse: removes sentinel after re-inject"
else
    _bad "posttooluse: removes sentinel after re-inject"
fi
if command -v python3 >/dev/null 2>&1; then
    printf '%s' "$OUT" | python3 -m json.tool >/dev/null 2>&1
    assert_exit 0 "$?" "posttooluse: armed output is valid JSON"
fi

OUT="$(MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$POSTTOOL" < "$TMP/post_tool_use_bash.json")"; RC=$?
assert_exit 0 "$RC" "posttooluse: no sentinel exits 0"
assert_eq '{}' "$OUT" "posttooluse: no sentinel emits empty object"
if [ ! -e "$STATE_DIR/$POST_TOOL_ID.recompact" ]; then
    _ok "posttooluse: no-sentinel path leaves sentinel dir untouched"
else
    _bad "posttooluse: no-sentinel path leaves sentinel dir untouched"
fi

HANDSHAKE_ID="11111111-2222-3333-4444-555555555555"
sed "s|$ORIG_PRE_COMPACT_CWD|$PRE_COMPACT_CWD|;s|$PRE_COMPACT_ID|$HANDSHAKE_ID|" \
    "$PRE_COMPACT_FIXTURE" > "$TMP/pre_compact_handshake.json"
sed "s|$ORIG_POST_TOOL_CWD|$POST_TOOL_CWD|;s|$POST_TOOL_ID|$HANDSHAKE_ID|" \
    "$POST_TOOL_FIXTURE" > "$TMP/post_tool_use_handshake.json"
OUT="$(MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$PRECOMPACT" < "$TMP/pre_compact_handshake.json")"; RC=$?
assert_exit 0 "$RC" "handshake: precompact exits 0"
assert_eq '{}' "$OUT" "handshake: precompact emits empty object"
assert_file "$STATE_DIR/$HANDSHAKE_ID.recompact" "handshake: precompact arms sentinel"
OUT="$(MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$POSTTOOL" < "$TMP/post_tool_use_handshake.json")"; RC=$?
assert_exit 0 "$RC" "handshake: first posttooluse exits 0"
assert_contains "$OUT" '"additionalContext"' "handshake: first posttooluse re-injects"
assert_contains "$OUT" "COPILOT-PROJECT-MARKER" "handshake: first payload contains project marker"
OUT="$(MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$POSTTOOL" < "$TMP/post_tool_use_handshake.json")"; RC=$?
assert_exit 0 "$RC" "handshake: second posttooluse exits 0"
assert_eq '{}' "$OUT" "handshake: second posttooluse is dormant"

OUT="$(printf 'not json' | MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$POSTTOOL")"; RC=$?
assert_exit 0 "$RC" "posttooluse: malformed stdin exits 0"
assert_eq '{}' "$OUT" "posttooluse: malformed stdin emits empty object"
OUT="$(printf '' | MEMORY_DIR="$MEM" MEMORY_STATE_DIR="$STATE_DIR" bash "$POSTTOOL")"; RC=$?
assert_exit 0 "$RC" "posttooluse: empty stdin exits 0"
assert_eq '{}' "$OUT" "posttooluse: empty stdin emits empty object"

GUARD="$REPO/scripts/hooks/guard.sh"
PRE_TOOL_CWD="$TMP/pretool-cwd"
mkdir -p "$PRE_TOOL_CWD"
ORIG_PRE_TOOL_CWD="$(sed -n 's/.*"cwd": "\(.*\)",/\1/p' "$PRE_TOOL_FIXTURE" | head -1)"
sed "s|$ORIG_PRE_TOOL_CWD|$PRE_TOOL_CWD|" "$PRE_TOOL_FIXTURE" > "$TMP/pre_tool_use_bash.json"
sed 's|printf fixture > fixture-tool.txt|gh pr merge 42|' "$TMP/pre_tool_use_bash.json" > "$TMP/pre_tool_use_deny.json"
GUARD_OUT="$TMP/guard.out"
GUARD_ERR="$TMP/guard.err"

AI_MEMORY_ROLE=task AI_MEMORY_GUARD_OUTPUT=copilot-json bash "$GUARD" \
    < "$TMP/pre_tool_use_deny.json" > "$GUARD_OUT" 2>"$GUARD_ERR"
RC=$?
assert_exit 0 "$RC" "guard: Copilot deny exits 0 for JSON permission contract"
assert_contains "$(cat "$GUARD_OUT")" '"permissionDecision":"deny"' "guard: Copilot deny emits permissionDecision deny"
if command -v python3 >/dev/null 2>&1; then
    OUT_FILE="$GUARD_OUT" python3 - <<'PY' >"$TMP/guard-json-check.out" 2>&1
import json, os, sys
with open(os.environ["OUT_FILE"]) as f:
    data = json.load(f)
if data.get("permissionDecision") != "deny":
    sys.stderr.write("decision mismatch: %r\n" % data)
    sys.exit(1)
reason = data.get("permissionDecisionReason")
if not isinstance(reason, str) or not reason:
    sys.stderr.write("missing non-empty reason: %r\n" % data)
    sys.exit(1)
PY
    rc=$?
    if [ "$rc" -eq 0 ]; then
        _ok "guard: Copilot deny stdout is valid JSON with non-empty reason"
    else
        _bad "guard: Copilot deny stdout is valid JSON with non-empty reason"
        cat "$TMP/guard-json-check.out"
    fi
fi

AI_MEMORY_ROLE=task AI_MEMORY_GUARD_OUTPUT=copilot-json bash "$GUARD" \
    < "$TMP/pre_tool_use_bash.json" > "$GUARD_OUT" 2>"$GUARD_ERR"
RC=$?
assert_exit 0 "$RC" "guard: Copilot benign fixture exits 0"
assert_eq "" "$(cat "$GUARD_OUT")" "guard: Copilot allow emits empty stdout"
assert_not_contains "$(cat "$GUARD_OUT")" "deny" "guard: Copilot allow output has no deny"

env -u AI_MEMORY_GUARD_OUTPUT AI_MEMORY_ROLE=task bash "$GUARD" \
    < "$TMP/pre_tool_use_deny.json" > "$GUARD_OUT" 2>"$GUARD_ERR"
RC=$?
assert_exit 2 "$RC" "guard: Copilot deny without output mode uses legacy exit 2"
assert_contains "$(cat "$GUARD_ERR")" "gh pr merge" "guard: legacy deny explains blocked Copilot command"

env -u AI_MEMORY_ROLE AI_MEMORY_GUARD_OUTPUT=copilot-json bash "$GUARD" \
    < "$TMP/pre_tool_use_deny.json" > "$GUARD_OUT" 2>"$GUARD_ERR"
RC=$?
assert_exit 0 "$RC" "guard: Copilot no role leaves interactive sessions unguarded"
assert_eq "" "$(cat "$GUARD_OUT")" "guard: Copilot no role emits empty stdout"

SL="$REPO/harnesses/copilot/statusline.sh"
STATUS_CWD="$TMP/status-cwd"
mkdir -p "$STATUS_CWD/.agents"
printf 'copilotproj\n' > "$STATUS_CWD/.agents/memory-project"
if command -v git >/dev/null 2>&1; then
    git -C "$STATUS_CWD" init -q
    git -C "$STATUS_CWD" symbolic-ref HEAD refs/heads/status-main
fi
PAYLOAD="$(printf '{"model":{"display_name":"GPT-5 Copilot"},"workspace":{"current_dir":"%s"},"context_window":{"current_context_used_percentage":72.5}}' "$STATUS_CWD")"
OUT="$(printf '%s' "$PAYLOAD" | MEMORY_DIR="$MEM" bash "$SL")"; RC=$?
assert_exit 0 "$RC" "statusline: project render exits 0"
assert_contains "$OUT" "GPT-5 Copilot" "statusline: shows the model"
assert_contains "$OUT" "status-cwd" "statusline: shows the folder"
assert_contains "$OUT" "copilotproj" "statusline: shows the memory project"
assert_contains "$OUT" "2 open" "statusline: shows memory open todo count"
if command -v git >/dev/null 2>&1; then
    assert_contains "$OUT" "status-main" "statusline: derives git branch from workspace dir"
fi
assert_contains "$OUT" "72% ctx" "statusline: shows context percentage without cost"

DORMANT="$TMP/no-project-cwd"
mkdir -p "$DORMANT"
PAYLOAD="$(printf '{"model":{"display_name":"GPT-5 Copilot"},"workspace":{"current_dir":"%s"},"context_window":{"used_percentage":11}}' "$DORMANT")"
OUT="$(printf '%s' "$PAYLOAD" | MEMORY_DIR="$MEM" bash "$SL")"; RC=$?
assert_exit 0 "$RC" "statusline: dormant render exits 0"
assert_contains "$OUT" "🧠 (no project)" "statusline: dormant shows no-project memory segment"
assert_not_contains "$OUT" "📋" "statusline: dormant omits todo glyph"
assert_not_contains "$OUT" "open" "statusline: dormant omits open todo count"

NOJQ_BIN="$TMP/nojq-bin"
mkdir -p "$NOJQ_BIN"
ln -s /bin/bash "$NOJQ_BIN/bash"
ln -s /bin/cat "$NOJQ_BIN/cat"
OUT="$(printf '%s' "$PAYLOAD" | PATH="$NOJQ_BIN" MEMORY_DIR="$MEM" bash "$SL" 2>&1)"; RC=$?
assert_exit 0 "$RC" "statusline: no-jq fallback exits 0"

. "$REPO/scripts/manifest.sh"
MANIFEST="$REPO/harnesses/copilot/manifest"
MEMORY_DIR="$REPO"
HARNESS=copilot
step() { :; }
info() { :; }
link() { :; }
. "$REPO/scripts/drivers/hook.sh"

HOOKDIR="$TMP/copilot-home/hooks"
mkdir -p "$HOOKDIR"
printf '{"version":1,"hooks":{"sessionStart":[]}}\n' > "$HOOKDIR/foo.json"
FOO_BEFORE="$(cat "$HOOKDIR/foo.json")"
COPILOT_JSON="$HOOKDIR/ai-memory.json"

_hook_register_copilot_json "$COPILOT_JSON"
assert_file "$COPILOT_JSON" "registration: owned ai-memory.json created"
assert_eq "$FOO_BEFORE" "$(cat "$HOOKDIR/foo.json")" "registration: sibling foo.json untouched"
if [ -x "$REPO/harnesses/copilot/hooks/sessionstart.sh" ]; then
    _ok "registration: referenced script is executable"
else
    _bad "registration: referenced script is executable"
fi
if [ -x "$PRECOMPACT" ] && [ -x "$POSTTOOL" ]; then
    _ok "registration: compaction scripts are executable"
else
    _bad "registration: compaction scripts are executable"
fi
FIRST="$(cat "$COPILOT_JSON")"
_hook_register_copilot_json "$COPILOT_JSON"
assert_eq "$FIRST" "$(cat "$COPILOT_JSON")" "registration: re-run is byte-identical"

if command -v python3 >/dev/null 2>&1; then
    COPILOT_JSON="$COPILOT_JSON" REPO="$REPO" python3 - <<'PY' >"$TMP/registration-check.out" 2>&1
import json, os, sys
repo = os.environ["REPO"]
with open(os.environ["COPILOT_JSON"]) as f:
    data = json.load(f)
if data.get("version") != 1:
    sys.stderr.write("version mismatch: %r\n" % data.get("version"))
    sys.exit(1)
entries = data.get("hooks", {}).get("sessionStart")
if not isinstance(entries, list) or len(entries) != 1:
    sys.stderr.write("sessionStart entries mismatch: %r\n" % entries)
    sys.exit(1)
entry = entries[0]
expected = "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=md AI_MEMORY_HOOK_EVENT=sessionStart bash %s/harnesses/copilot/hooks/sessionstart.sh" % (repo, repo)
checks = [
    ("type", entry.get("type") == "command"),
    ("timeoutSec", entry.get("timeoutSec") == 10),
    ("bash", entry.get("bash") == expected),
]
guard_entries = data.get("hooks", {}).get("preToolUse")
if not isinstance(guard_entries, list) or len(guard_entries) != 1:
    sys.stderr.write("preToolUse entries mismatch: %r\n" % guard_entries)
    sys.exit(1)
guard = guard_entries[0]
expected_guard = "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=md AI_MEMORY_HOOK_EVENT=preToolUse AI_MEMORY_GUARD_OUTPUT=copilot-json bash %s/scripts/hooks/guard.sh" % (repo, repo)
checks.extend([
    ("guard type", guard.get("type") == "command"),
    ("guard timeoutSec", guard.get("timeoutSec") == 5),
    ("guard bash", guard.get("bash") == expected_guard),
])
arm_entries = data.get("hooks", {}).get("preCompact")
if not isinstance(arm_entries, list) or len(arm_entries) != 1:
    sys.stderr.write("preCompact entries mismatch: %r\n" % arm_entries)
    sys.exit(1)
arm = arm_entries[0]
expected_arm = "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=md AI_MEMORY_HOOK_EVENT=preCompact bash %s/harnesses/copilot/hooks/precompact.sh" % (repo, repo)
post_entries = data.get("hooks", {}).get("postToolUse")
if not isinstance(post_entries, list) or len(post_entries) != 1:
    sys.stderr.write("postToolUse entries mismatch: %r\n" % post_entries)
    sys.exit(1)
post = post_entries[0]
expected_post = "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=md AI_MEMORY_HOOK_EVENT=postToolUse bash %s/harnesses/copilot/hooks/posttooluse.sh" % (repo, repo)
checks.extend([
    ("arm type", arm.get("type") == "command"),
    ("arm timeoutSec", arm.get("timeoutSec") == 10),
    ("arm bash", arm.get("bash") == expected_arm),
    ("post type", post.get("type") == "command"),
    ("post timeoutSec", post.get("timeoutSec") == 10),
    ("post bash", post.get("bash") == expected_post),
    ("event count", sorted(data.get("hooks", {}).keys()) == ["postToolUse", "preCompact", "preToolUse", "sessionStart"]),
])
for label, ok in checks:
    if not ok:
        sys.stderr.write("%s failed: session=%r guard=%r arm=%r post=%r\n" % (label, entry, guard, arm, post))
        sys.exit(1)
PY
    rc=$?
    if [ "$rc" -eq 0 ]; then
        _ok "registration: schema matches Copilot hooks contract"
    else
        _bad "registration: schema matches Copilot hooks contract"
        cat "$TMP/registration-check.out"
    fi
fi

OUT="$(bash "$REPO/scripts/validate-manifest.sh" "$MANIFEST" 2>&1)"; RC=$?
assert_exit 0 "$RC" "manifest: copilot manifest validates"
assert_not_contains "$OUT" "WARN" "manifest: copilot manifest has no warnings"

finish
