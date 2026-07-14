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
if "matcher" in ups[0]:
    sys.stderr.write("UserPromptSubmit group unexpectedly has matcher\n")
    sys.exit(1)
inject_cmd = ups[0]["hooks"][0]["command"]
guard_cmd = ptu[0]["hooks"][0]["command"]
checks = [
    ("inject path", "scripts/hooks/inject.sh" in inject_cmd),
    ("md format", "AI_MEMORY_HOOK_FORMAT=md" in inject_cmd),
    ("memory dir", "MEMORY_DIR=" in inject_cmd),
    ("hook event", "AI_MEMORY_HOOK_EVENT=UserPromptSubmit" in inject_cmd),
    ("guard matcher", ptu[0].get("matcher") == "^Bash$|apply_patch"),
    ("guard path", "scripts/hooks/guard.sh" in guard_cmd),
]
for label, ok in checks:
    if not ok:
        sys.stderr.write("failed check: %s\n" % label)
        sys.exit(1)
inject_entries = [
    g for g in ups
    if any("scripts/hooks/inject.sh" in h.get("command", "") for h in g.get("hooks", []) if isinstance(h, dict))
]
guard_entries = [
    g for g in ptu
    if any("scripts/hooks/guard.sh" in h.get("command", "") for h in g.get("hooks", []) if isinstance(h, dict))
]
if len(inject_entries) != 1 or len(guard_entries) != 1:
    sys.stderr.write("idempotency failure: inject=%d guard=%d\n" % (len(inject_entries), len(guard_entries)))
    sys.exit(1)
expected_inject = "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=md AI_MEMORY_HOOK_EVENT=UserPromptSubmit bash %s/scripts/hooks/inject.sh" % (repo, repo)
expected_guard = "env MEMORY_DIR=%s bash %s/scripts/hooks/guard.sh" % (repo, repo)
if inject_cmd != expected_inject:
    sys.stderr.write("inject command mismatch\nexpected=%r\nactual=%r\n" % (expected_inject, inject_cmd))
    sys.exit(1)
if guard_cmd != expected_guard:
    sys.stderr.write("guard command mismatch\nexpected=%r\nactual=%r\n" % (expected_guard, guard_cmd))
    sys.exit(1)
PY
rc=$?
if [ "$rc" -eq 0 ]; then
    _ok "codex hooks_json schema and idempotency"
else
    _bad "codex hooks_json schema and idempotency"
    cat "$PYOUT"
fi

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

finish
