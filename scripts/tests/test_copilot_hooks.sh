#!/usr/bin/env bash
# GitHub Copilot delivery face: sessionStart adapter envelope + owned hooks file
# registration. Uses real Phase 0 stdin fixtures; no real Copilot binary or HOME.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
HOOK="$REPO/harnesses/copilot/hooks/sessionstart.sh"
FIXTURE="$REPO/scripts/tests/fixtures/copilot/session_start_camel.json"
TMP="$(new_sandbox)"
MEM="$(new_sandbox)"
trap 'rm -rf "$TMP" "$MEM"' EXIT

seed_min_tree "$MEM"
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

# Rewrite the fixture's captured absolute cwd to a path inside this test's own
# sandbox — never materialize (or clean up) the literal recorded path, which on
# the capture machine is a live directory outside the sandbox.
FIXTURE_CWD="$TMP/probe-cwd"
mkdir -p "$FIXTURE_CWD/.agents"
printf 'copilotproj\n' > "$FIXTURE_CWD/.agents/memory-project"
ORIG_CWD="$(sed -n 's/.*"cwd": "\(.*\)",/\1/p' "$FIXTURE" | head -1)"
sed "s|$ORIG_CWD|$FIXTURE_CWD|" "$FIXTURE" > "$TMP/session_start_camel.json"

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
for label, ok in checks:
    if not ok:
        sys.stderr.write("%s failed: %r\n" % (label, entry))
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
