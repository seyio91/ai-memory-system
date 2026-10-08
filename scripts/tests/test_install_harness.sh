#!/usr/bin/env bash
# install.sh (manifest-driven engine): --harness claude reproduces the hook
# wiring (hooks/commands/statusline/skills/agents); --harness codex runs the file
# archetype (context prep, no symlink, deferred surfaces reported); idempotent
# re-run; unknown harness errors; --list. Hermetic: a fake repo + fake HOME, so
# config-stamp and template-seed never touch the real tree.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
SBROOT="$(new_sandbox)"; FAKE="$SBROOT/repo"; FHOME="$SBROOT/home"; FBIN="$SBROOT/bin"
trap 'rm -rf "$SBROOT"' EXIT
mkdir -p "$FAKE" "$FHOME" "$FBIN"
# install.sh resolves its repo root with `pwd -P`; match that physical path so the
# symlink-target string assertions below compare equal (macOS /var -> /private/var).
FAKE="$(cd "$FAKE" && pwd -P)"

# Stage a self-contained fake repo: real engine + harness assets, minimal stores.
cp -R "$REPO/scripts" "$FAKE/scripts"
cp -R "$REPO/harnesses" "$FAKE/harnesses"
cp -R "$REPO/commands" "$FAKE/commands"
cp -R "$REPO/doctrine" "$FAKE/doctrine"
cp "$REPO/install.sh" "$FAKE/install.sh"
# Seed templates live under templates/, not the repo root. If these fixture paths
# and install.sh ever disagree, install seeds nothing and every assertion below
# still passes on the pre-existing files -- so keep them in lockstep.
# No orchestrator seed file here on purpose: the old per-instance seed under
# templates/ was deleted (doctrine moved to the tracked doctrine/ core).
# Fabricating one in this fixture would hide install.sh ever regressing back to
# the deleted file -- that is exactly how R1 (a fresh install dying under set -e
# at the `cp` of a file that no longer exists) went unnoticed.
mkdir -p "$FAKE/templates"
printf '# identity template\n' > "$FAKE/templates/identity.template.md"
printf '# index template\n'    > "$FAKE/templates/index.template.md"
printf '# skills template\n[[skills]]\nname = "template-skill"\nurl = "https://example.invalid/skills.git"\nref = "main"\n' > "$FAKE/templates/skills.toml.example"
mkdir -p "$FAKE/skills/demo-skill"
printf -- '---\nname: demo-skill\ndescription: demo\n---\n# demo\n' > "$FAKE/skills/demo-skill/SKILL.md"
mkdir -p "$FAKE/agents"
printf -- '---\nname: demo-agent\ndescription: demo\n---\nbody\n' > "$FAKE/agents/demo-agent.md"

cat > "$FBIN/codex" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version) printf 'codex-cli 0.144.1\n'; exit 0 ;;
esac
exit 0
EOF
chmod +x "$FBIN/codex"
cat > "$FBIN/copilot" <<'EOF'
#!/usr/bin/env bash
case "${1:-}" in
    --version) printf 'GitHub Copilot CLI 1.0.71.\n'; exit 0 ;;
esac
exit 0
EOF
chmod +x "$FBIN/copilot"
export PATH="$FBIN:$PATH"

run_install() { HOME="$FHOME" MEMORY_DIR="$FAKE" bash "$FAKE/install.sh" "$@"; }
# The guard scope reaches install via config.local.sh; an inherited shell value
# would make the default-scope assertions below depend on the caller's env.
unset AI_MEMORY_GUARD_SCOPE

# --- claude (hook archetype) ---
mkdir -p "$FHOME/.claude"
cat > "$FHOME/.claude/settings.json" <<'EOF'
{
  "statusLine": {
    "type": "command",
    "command": "bash /custom/statusline.sh",
    "enabled": true
  },
  "permissions": {
    "allow": ["Bash(git status:*)"]
  },
  "hooks": {
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "echo user-stop-hook" }
        ]
      }
    ]
  }
}
EOF
run_install --harness claude >"$SBROOT/log.claude" 2>&1; rc=$?
assert_exit 0 "$rc" "claude install exits 0"
assert_file "$FHOME/.claude/settings.json"       "claude settings.json present"
assert_file "$FHOME/.claude/statusline.sh"        "statusline linked"
assert_file "$FHOME/.claude/commands/pin.md"      "native command linked (pin)"
assert_file "$FHOME/.claude/commands/new-initiative.md" "native command linked (new-initiative)"
assert_file "$FHOME/.claude/skills/demo-skill"    "skill fanned out"
assert_file "$FHOME/.claude/agents/demo-agent.md" "agent fanned out"
for h in inject_memory.sh memory_common.sh session_start_memory.sh block_task_tools.sh; do
    if [ ! -e "$FHOME/.claude/hooks/$h" ]; then _ok "claude: hook script not symlinked: $h"; else _bad "claude: unexpected hook symlink: $h"; fi
done
csj="$(cat "$FHOME/.claude/settings.json")"
assert_contains "$csj" "SessionStart" "claude settings: SessionStart hook registered"
assert_contains "$csj" "UserPromptSubmit" "claude settings: UserPromptSubmit hook registered"
assert_contains "$csj" "PreToolUse" "claude settings: PreToolUse hook registered"
assert_contains "$csj" "scripts/hooks/inject.sh" "claude settings: inject command -> shared inject.sh"
assert_contains "$csj" "AI_MEMORY_HOOK_FORMAT=xml" "claude settings: inject command renders xml"
assert_contains "$csj" "session_start_memory.sh" "claude settings: SessionStart command -> migrated script"
assert_contains "$csj" "block_task_tools.sh" "claude settings: task-tool block command -> block script"
assert_contains "$csj" '"matcher": "TaskCreate|TaskUpdate"' "claude settings: task-tool matcher registered"
assert_contains "$csj" "AI_MEMORY_GUARD_SCOPE=executor bash $FAKE/scripts/hooks/guard.sh" "claude settings: guard command carries the default scope"
assert_contains "$csj" '"matcher": "Bash"' "claude settings: guard matcher registered"
assert_contains "$csj" "env MEMORY_DIR=$FAKE bash $FAKE/scripts/hooks/memory_write_guard.sh" "claude settings: write-guard command registered"
assert_contains "$csj" '"matcher": "Write|Edit"' "claude settings: write-guard matcher registered"
assert_not_contains "$(cat "$SBROOT/log.claude")" "ai-memory install:" "claude: no sweep report when nothing of ours was swept"
assert_contains "$csj" "statusLine" "claude settings: existing statusLine preserved"
assert_contains "$csj" "bash /custom/statusline.sh" "claude settings: existing statusLine command preserved"
assert_contains "$csj" "permissions" "claude settings: permissions preserved"
assert_contains "$csj" "Stop" "claude settings: user Stop hook preserved"
assert_contains "$csj" "echo user-stop-hook" "claude settings: user hook command preserved"
assert_contains "$(cat "$SBROOT/log.claude")" "Hook entries were auto-merged" "claude notes: settings auto-merge reported"
assert_file "$FAKE/skills.toml"                   "root skills.toml seeded from template"
assert_file "$FAKE/orchestrator.local.md"         "orchestrator.local.md seeded (empty overlay)"
assert_eq "" "$(cat "$FAKE/orchestrator.local.md")" "orchestrator.local.md seeded empty (zero bytes, not a header)"
assert_not_file "$FAKE/orchestrator.md"           "install does not create a root orchestrator.md (migration owns legacy files)"
assert_eq "$(cat "$FAKE/templates/skills.toml.example")" "$(cat "$FAKE/skills.toml")" "skills.toml seeded as an exact template copy"
assert_eq "# identity template" "$(cat "$FAKE/identity.md")" "identity.md seeded as an exact template copy"
assert_eq "# index template" "$(cat "$FAKE/index.md")" "index.md seeded as an exact template copy"
# No seed template may be left at the repo root -- a stray root copy would let a
# half-migrated install.sh keep working and hide the real path from this suite.
assert_eq "0" "$(find "$FAKE" -maxdepth 1 \( -name '*.template.md' -o -name '*.example' \) | grep -c .)" \
    "no seed template remains at the fake repo root"
assert_contains "$(cat "$SBROOT/log.claude")" "seeded skills.toml from template" "install reports the skills.toml seed step"
set +e; [ -d "$FAKE/.skill-cache/template-skill" ]
# Intentional status capture around a negative assertion.
# shellcheck disable=SC2319
e=$?; set -e
assert_exit 1 "$e" "install seed step does not resolve remote skills"
assert_eq "$FAKE/commands/pin.md" \
    "$(readlink "$FHOME/.claude/commands/pin.md")" "command target -> commands/"
assert_eq "$FAKE/commands/new-initiative.md" \
    "$(readlink "$FHOME/.claude/commands/new-initiative.md")" "new-initiative target -> commands/"
assert_contains "$(cat "$FAKE/config.local.sh")" "export MEMORY_DIR=" "config.local.sh stamped in FAKE repo"

# --- idempotent re-run ---
printf '# keep local choices\n' > "$FAKE/skills.toml"
# An overlay already carrying personal rules, plus a pre-1.6.0 legacy root file
# (simulating an un-migrated instance) -- install.sh must leave both exactly as
# they are: the overlay is seeded only when absent, and the legacy file is the
# migration's to move, never install.sh's.
printf '# personal overlay rules\n' > "$FAKE/orchestrator.local.md"
printf '# legacy per-instance orchestrator\n' > "$FAKE/orchestrator.md"
run_install --harness claude >"$SBROOT/log.claude2" 2>&1; rc=$?
assert_exit 0 "$rc" "claude re-run exits 0"
assert_contains "$(cat "$SBROOT/log.claude2")" "ok (already linked)" "re-run: already-linked (no churn)"
assert_eq "# keep local choices" "$(cat "$FAKE/skills.toml")" "existing skills.toml is not overwritten"
assert_eq "# personal overlay rules" "$(cat "$FAKE/orchestrator.local.md")" "existing orchestrator.local.md (with content) is not overwritten"
assert_eq "# legacy per-instance orchestrator" "$(cat "$FAKE/orchestrator.md")" "existing legacy orchestrator.md is left untouched by install (the migration owns it, not install.sh)"
assert_not_contains "$(cat "$SBROOT/log.claude2")" "seeded skills.toml from template" "existing skills.toml skips seed step"
if command -v python3 >/dev/null 2>&1; then
    # set +e: a failing check must reach _bad and print its captured output. Under
    # set -e the script exits at the python call, so the suite saw only a bare rc=1
    # with no reason and no summary line — which is how a broken expectation here
    # went unnoticed from 742f083 until 2026-07-18.
    set +e
    CLAUDE_SETTINGS="$FHOME/.claude/settings.json" FAKE_REPO="$FAKE" python3 - <<'PY' >"$SBROOT/claude-settings-check.out" 2>&1
import json, os, sys
path = os.environ["CLAUDE_SETTINGS"]
repo = os.environ["FAKE_REPO"]
with open(path) as f:
    data = json.load(f)
hooks = data.get("hooks", {})
# Chunk counts come from the manifest, not a literal: this check exists to catch
# registration drift, and hardcoding the count is how it silently stopped doing
# that (742f083 chunked registration; this expectation was never updated, so it
# matched 0 entries and the whole test died before reporting).
def chunk_count(key):
    with open(os.path.join(repo, "harnesses", "claude", "manifest")) as f:
        for line in f:
            k, _, v = line.partition("=")
            if k.strip() == key:
                return int(v.strip())
    return 1

# A list, not a dict keyed by event: PreToolUse carries two groups (task-tool
# block + infra guard).
expected = [
    ("SessionStart", "", "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=xml AI_MEMORY_HOOK_EVENT=SessionStart%%s bash %s/scripts/hooks/session_start_memory.sh" % (repo, repo), chunk_count("session_chunks")),
    ("UserPromptSubmit", "", "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=xml AI_MEMORY_HOOK_EVENT=UserPromptSubmit%%s bash %s/scripts/hooks/inject.sh" % (repo, repo), chunk_count("inject_chunks")),
    # chunks=None marks an event that is not chunk-capable at all (no %s slot).
    # That is different from chunks==1, where _hook_chunked_commands emits the
    # un-chunked form of a chunk-capable event.
    ("PreToolUse", "TaskCreate|TaskUpdate", "bash %s/harnesses/claude/hooks/block_task_tools.sh" % repo, None),
    ("PreToolUse", "Bash", "env MEMORY_DIR=%s AI_MEMORY_GUARD_SCOPE=executor bash %s/scripts/hooks/guard.sh" % (repo, repo), None),
    ("PostToolUse", "Write|Edit", "env MEMORY_DIR=%s bash %s/scripts/hooks/memory_write_guard.sh" % (repo, repo), None),
]
for event, matcher, template, chunks in expected:
    groups = hooks.get(event, [])
    if chunks is None:
        wanted = [template]
    elif chunks == 1:
        wanted = [template % ""]
    else:
        wanted = [template % (" AI_MEMORY_HOOK_CHUNK=%d/%d" % (i, chunks)) for i in range(1, chunks + 1)]
    for command in wanted:
        matches = [
            g for g in groups
            if isinstance(g, dict)
            and (not matcher or g.get("matcher") == matcher)
            and any(isinstance(h, dict) and h.get("command") == command for h in g.get("hooks", []))
        ]
        if len(matches) != 1:
            sys.stderr.write("%s expected one ai-memory hook for %r, got %d\n" % (event, command, len(matches)))
            sys.exit(1)
# Exactly one guard and one write-guard entry across ALL events, not just the
# expected group: a stray copy under another event/matcher would still run.
for script in ("scripts/hooks/guard.sh", "scripts/hooks/memory_write_guard.sh"):
    n = sum(
        1 for groups in hooks.values() if isinstance(groups, list)
        for g in groups if isinstance(g, dict)
        for h in g.get("hooks", []) if isinstance(h, dict) and ("/" + script) in h.get("command", "")
    )
    if n != 1:
        sys.stderr.write("expected exactly one %s entry, got %d\n" % (script, n))
        sys.exit(1)
stop = hooks.get("Stop", [])
if not stop or "user-stop-hook" not in json.dumps(stop):
    sys.stderr.write("user Stop hook was not preserved\n")
    sys.exit(1)
if data.get("statusLine", {}).get("command") != "bash /custom/statusline.sh":
    sys.stderr.write("statusLine command was not preserved\n")
    sys.exit(1)
if "permissions" not in data:
    sys.stderr.write("permissions missing\n")
    sys.exit(1)
PY
    # shellcheck disable=SC2319
    rc=$?; set -e
    if [ "$rc" -eq 0 ]; then
        _ok "claude settings: re-run is idempotent and preserves siblings"
    else
        _bad "claude settings: re-run is idempotent and preserves siblings"
        cat "$SBROOT/claude-settings-check.out"
    fi
fi

# --- claude: guard scope bake + sweep report ---------------------------------
CSJ="$FHOME/.claude/settings.json"
WG_CMD="env MEMORY_DIR=$FAKE bash $FAKE/scripts/hooks/memory_write_guard.sh"
# set_scope <value|""> — rewrite config.local.sh's AI_MEMORY_GUARD_SCOPE line
# (install re-stamps only the MEMORY_DIR line, so this survives a run).
set_scope() {
    grep -v '^export AI_MEMORY_GUARD_SCOPE=' "$FAKE/config.local.sh" > "$SBROOT/cl.tmp" || true
    [ -z "$1" ] || printf 'export AI_MEMORY_GUARD_SCOPE="%s"\n' "$1" >> "$SBROOT/cl.tmp"
    mv "$SBROOT/cl.tmp" "$FAKE/config.local.sh"
}
# hook_lines <script-suffix> — one "event<TAB>matcher<TAB>hook-json" line per
# registered hook whose command names the script, across every event.
hook_lines() {
    if command -v python3 >/dev/null 2>&1; then
        AIM_P="$CSJ" AIM_S="$1" python3 -c '
import json, os
d = json.load(open(os.environ["AIM_P"])).get("hooks", {})
for ev, groups in d.items():
    for g in groups:
        for h in g.get("hooks", []):
            if "/" + os.environ["AIM_S"] in h.get("command", ""):
                print("%s\t%s\t%s" % (ev, g.get("matcher", ""), json.dumps(h, sort_keys=True)))
'
    fi
}
seed_settings() {
    cat > "$CSJ"
}
if command -v python3 >/dev/null 2>&1; then
    # (1) AI_MEMORY_GUARD_SCOPE="all" in config is baked into the guard command.
    set_scope all
    run_install --harness claude >"$SBROOT/log.scope-all" 2>&1; rc=$?
    assert_exit 0 "$rc" "scope=all: claude install exits 0"
    g="$(hook_lines scripts/hooks/guard.sh)"
    assert_eq "1" "$(printf '%s\n' "$g" | grep -c .)" "scope=all: exactly one guard entry"
    assert_contains "$g" "PreToolUse	Bash	" "scope=all: guard on PreToolUse matcher Bash"
    assert_contains "$g" "AI_MEMORY_GUARD_SCOPE=all bash $FAKE/scripts/hooks/guard.sh" "scope=all: guard command carries AI_MEMORY_GUARD_SCOPE=all"
    # The flip rewrites our own earlier entry: one "updated" line, no JSON dump.
    flip_log="$(grep 'ai-memory install:' "$SBROOT/log.scope-all" || true)"
    assert_contains "$flip_log" "ai-memory install: updated managed hook guard.sh (PreToolUse [Bash]) (backup: $CSJ.bak-" \
        "scope flip: 'updated managed hook guard.sh' line names the backup path"
    assert_eq "1" "$(printf '%s\n' "$flip_log" | grep -c .)" \
        "scope flip: exactly one report line and nothing else"
    assert_not_contains "$flip_log" "{" "scope flip: no JSON dump"

    # (2) an invalid value fails install.sh before ANY step writes: settings.json
    # byte-identical, and surfaces removed here (statusline, a command, a skill)
    # are not recreated, so the tree listing is unchanged too.
    set_scope alll
    rm -f "$FHOME/.claude/statusline.sh" "$FHOME/.claude/commands/pin.md"
    rm -rf "$FHOME/.claude/skills/demo-skill"
    cp "$CSJ" "$SBROOT/settings.before"
    cp "$FAKE/config.local.sh" "$SBROOT/config.before"
    find "$FHOME" "$FAKE" | sort > "$SBROOT/tree.before"
    set +e
    run_install --harness claude >"$SBROOT/log.scope-bad" 2>&1; rc=$?
    set -e
    assert_exit 1 "$rc" "scope=alll: claude install exits 1"
    assert_contains "$(cat "$SBROOT/log.scope-bad")" "AI_MEMORY_GUARD_SCOPE=alll" "scope=alll: error names the value"
    assert_contains "$(cat "$SBROOT/log.scope-bad")" "$FAKE/config.local.sh or the environment" "scope=alll: error names config file or environment"
    if cmp -s "$SBROOT/settings.before" "$CSJ"; then _ok "scope=alll: settings.json byte-identical"; else _bad "scope=alll: settings.json byte-identical"; fi
    if cmp -s "$SBROOT/config.before" "$FAKE/config.local.sh"; then _ok "scope=alll: config.local.sh not re-stamped"; else _bad "scope=alll: config.local.sh not re-stamped"; fi
    find "$FHOME" "$FAKE" | sort > "$SBROOT/tree.after"
    if cmp -s "$SBROOT/tree.before" "$SBROOT/tree.after"; then _ok "scope=alll: no file created or removed in the sandbox"; else _bad "scope=alll: no file created or removed in the sandbox"; diff "$SBROOT/tree.before" "$SBROOT/tree.after" || true; fi
    assert_not_file "$FHOME/.claude/statusline.sh" "scope=alll: statusline not relinked"
    assert_not_file "$FHOME/.claude/commands/pin.md" "scope=alll: commands not relinked"
    assert_not_file "$FHOME/.claude/skills/demo-skill" "scope=alll: skills not fanned out"
    set_scope ""

    # (3) a hand-wired write-guard entry identical to what install writes: swept silently.
    seed_settings <<EOF
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write|Edit", "hooks": [ { "type": "command", "command": "$WG_CMD" } ] }
    ],
    "Stop": [ { "hooks": [ { "type": "command", "command": "echo user-stop-hook" } ] } ]
  }
}
EOF
    run_install --harness claude >"$SBROOT/log.sweep-same" 2>&1; rc=$?
    assert_exit 0 "$rc" "sweep identical: claude install exits 0"
    assert_eq "1" "$(hook_lines scripts/hooks/memory_write_guard.sh | grep -c .)" "sweep identical: exactly one write-guard entry"
    assert_eq "1" "$(hook_lines scripts/hooks/guard.sh | grep -c .)" "sweep identical: exactly one guard entry"
    assert_not_contains "$(cat "$SBROOT/log.sweep-same")" "ai-memory install:" "sweep identical: no report line"
    assert_contains "$(cat "$CSJ")" "echo user-stop-hook" "sweep identical: user hook preserved"

    # (4) customised entries (extra key / wider matcher): replaced by one canonical
    # entry, each reported verbatim with the backup path.
    seed_settings <<EOF
{
  "hooks": {
    "PostToolUse": [
      { "matcher": "Write|Edit", "hooks": [ { "type": "command", "command": "$WG_CMD", "timeout": 9 } ] },
      { "matcher": "Write|Edit|MultiEdit", "hooks": [ { "type": "command", "command": "$WG_CMD" } ] }
    ]
  }
}
EOF
    run_install --harness claude >"$SBROOT/log.sweep-custom" 2>&1; rc=$?
    assert_exit 0 "$rc" "sweep customised: claude install exits 0"
    wg="$(hook_lines scripts/hooks/memory_write_guard.sh)"
    assert_eq "1" "$(printf '%s\n' "$wg" | grep -c .)" "sweep customised: exactly one write-guard entry"
    assert_contains "$wg" "PostToolUse	Write|Edit	" "sweep customised: canonical event + matcher"
    assert_not_contains "$wg" "timeout" "sweep customised: canonical entry has no timeout"
    rep_log="$(grep 'ai-memory install: replaced non-standard hook entry' "$SBROOT/log.sweep-custom" || true)"
    assert_eq "2" "$(printf '%s\n' "$rep_log" | grep -c .)" "sweep customised: one report line per customised entry"
    assert_contains "$rep_log" "(backup: $CSJ.bak-" "sweep customised: report names the backup path"
    assert_contains "$rep_log" '"timeout": 9' "sweep customised: report shows the extra key"
    assert_contains "$rep_log" "PostToolUse [Write|Edit|MultiEdit]" "sweep customised: report shows the customised matcher"
    bk="$(printf '%s\n' "$rep_log" | head -1 | sed -n 's/.*(backup: \([^)]*\)).*/\1/p')"
    assert_contains "$(cat "$bk" 2>/dev/null)" '"timeout": 9' "sweep customised: named backup holds the original entry"

    # (5) an entry naming a retired hook script is reported as removed; a managed
    # script on an event install no longer writes it to is "removed hook entry".
    seed_settings <<EOF
{
  "hooks": {
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "bash $FHOME/.claude/hooks/inject_memory.sh" } ] } ],
    "PostToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "env MEMORY_DIR=$FAKE bash $FAKE/scripts/hooks/guard.sh" } ] } ]
  }
}
EOF
    run_install --harness claude >"$SBROOT/log.sweep-retired" 2>&1; rc=$?
    assert_exit 0 "$rc" "sweep retired: claude install exits 0"
    ret_log="$(grep 'ai-memory install:' "$SBROOT/log.sweep-retired" || true)"
    assert_contains "$ret_log" "ai-memory install: removed (retired hook)" "sweep retired: reported as removed (retired hook)"
    assert_contains "$ret_log" "inject_memory.sh" "sweep retired: report names the retired script"
    assert_not_contains "$ret_log" "replaced non-standard" "sweep retired: not reported as replaced"
    assert_contains "$ret_log" "ai-memory install: removed hook entry in $CSJ (backup: $CSJ.bak-" "sweep orphan: reported as removed hook entry with backup"
    assert_contains "$ret_log" "PostToolUse [Bash]" "sweep orphan: report names event + matcher"
    assert_eq "1" "$(hook_lines scripts/hooks/guard.sh | grep -c .)" "sweep orphan: one guard entry remains (PreToolUse)"
    assert_not_contains "$(cat "$CSJ")" "inject_memory.sh" "sweep retired: entry removed"

    # (6) two further re-runs: byte-identical settings.json, no report on the second.
    run_install --harness claude >"$SBROOT/log.rerun1" 2>&1
    cp "$CSJ" "$SBROOT/settings.rerun1"
    run_install --harness claude >"$SBROOT/log.rerun2" 2>&1; rc=$?
    assert_exit 0 "$rc" "re-run x2: claude install exits 0"
    if cmp -s "$SBROOT/settings.rerun1" "$CSJ"; then _ok "re-run x2: settings.json byte-identical"; else _bad "re-run x2: settings.json byte-identical"; fi
    assert_not_contains "$(cat "$SBROOT/log.rerun2")" "ai-memory install:" "re-run x2: no report lines on the second run"
fi

# --- claude: no-python3 fallback writer ---------------------------------------
# hook.sh picks the hand-printed writer when `command -v python3` fails and the
# target does not exist yet. Drive the driver directly under a PATH holding only
# the tools that branch needs (no python3, no jq), then parse the result.
NOPY_BIN="$SBROOT/nopy-bin"
mkdir -p "$NOPY_BIN"
for prog in sed tr mkdir chmod dirname cat; do
    src="$(command -v "$prog" 2>/dev/null)"
    [ -n "$src" ] && ln -sf "$src" "$NOPY_BIN/$prog"
done
if env -i PATH="$NOPY_BIN" "$(command -v bash)" -c 'command -v python3 || command -v jq' >/dev/null 2>&1; then
    _bad "test setup: stub PATH still exposes python3/jq"
fi
NOPY_OUT="$SBROOT/nopy/settings.json"
set +e
(
    . "$FAKE/scripts/manifest.sh"
    . "$FAKE/scripts/_lib.sh"
    . "$FAKE/scripts/drivers/hook.sh"
    info() { printf '  %s\n' "$1"; }; step() { :; }
    HARNESS=claude MANIFEST="$FAKE/harnesses/claude/manifest" MEMORY_DIR="$FAKE"
    PATH="$NOPY_BIN"
    _hook_register_native_json "$NOPY_OUT"
) >"$SBROOT/log.nopy" 2>&1; rc=$?
set -e
assert_exit 0 "$rc" "no-python3 fallback: driver exits 0"
assert_contains "$(cat "$SBROOT/log.nopy")" "no python3 — new file" "no-python3 fallback: hand-printed writer used"
assert_eq "1" "$(grep -c '"PreToolUse"' "$NOPY_OUT" 2>/dev/null)" "no-python3 fallback: a single PreToolUse key"
if command -v python3 >/dev/null 2>&1; then
    set +e
    NOPY_OUT="$NOPY_OUT" FAKE_REPO="$FAKE" python3 - <<'PY' >"$SBROOT/nopy-check.out" 2>&1
import json, os, sys
repo = os.environ["FAKE_REPO"]
hooks = json.load(open(os.environ["NOPY_OUT"]))["hooks"]
ptu = [(g.get("matcher"), g["hooks"][0]["command"]) for g in hooks["PreToolUse"]]
want = [
    ("TaskCreate|TaskUpdate", "bash %s/harnesses/claude/hooks/block_task_tools.sh" % repo),
    ("Bash", "env MEMORY_DIR=%s AI_MEMORY_GUARD_SCOPE=executor bash %s/scripts/hooks/guard.sh" % (repo, repo)),
]
if ptu != want:
    sys.stderr.write("PreToolUse groups %r != %r\n" % (ptu, want)); sys.exit(1)
post = [(g.get("matcher"), g["hooks"][0]["command"]) for g in hooks["PostToolUse"]]
if post != [("Write|Edit", "env MEMORY_DIR=%s bash %s/scripts/hooks/memory_write_guard.sh" % (repo, repo))]:
    sys.stderr.write("PostToolUse groups %r\n" % (post,)); sys.exit(1)
PY
    # shellcheck disable=SC2319
    rc=$?; set -e
    if [ "$rc" -eq 0 ]; then
        _ok "no-python3 fallback: valid JSON, block + guard (with scope) under one PreToolUse, write guard on PostToolUse"
    else
        _bad "no-python3 fallback: valid JSON, block + guard (with scope) under one PreToolUse, write guard on PostToolUse"
        cat "$SBROOT/nopy-check.out"
    fi
fi

# Scope set to `all` for the codex run: it must still never reach codex's guard.
set_scope all
# A hand-wired write guard in codex's hooks.json is the user's: the write guard is
# a Claude-only role, so codex's sweep must leave it alone.
CODEX_WG_CMD="env MEMORY_DIR=$FAKE bash $FAKE/scripts/hooks/memory_write_guard.sh"
mkdir -p "$FHOME/.codex"
printf '{"hooks": {"PostToolUse": [{"matcher": "apply_patch", "hooks": [{"type": "command", "command": "%s"}]}]}}\n' "$CODEX_WG_CMD" > "$FHOME/.codex/hooks.json"
# --- codex (file archetype, hand-owned base + hooks): context prep + skills + commands-as-skills ---
run_install --harness codex >"$SBROOT/log.codex" 2>&1; rc=$?
assert_exit 0 "$rc" "codex install exits 0"
assert_file "$FHOME/.codex" "codex context dir prepared"
if [ ! -e "$FHOME/.codex/AGENTS.md" ]; then _ok "codex: no AGENTS.md written (hand-owned static base)"; else _bad "codex: unexpected AGENTS.md written by installer"; fi
assert_file "$FHOME/.codex/hooks.json" "codex: native hooks.json registered"
chj="$(cat "$FHOME/.codex/hooks.json")"
assert_contains "$chj" '"hooks"' "codex: hooks.json has top-level hooks object"
assert_contains "$chj" '"UserPromptSubmit"' "codex: UserPromptSubmit hook registered"
assert_contains "$chj" '"PreToolUse"' "codex: PreToolUse hook registered"
assert_contains "$chj" "AI_MEMORY_HOOK_FORMAT=md" "codex: inject command renders md"
assert_contains "$chj" "scripts/hooks/inject.sh" "codex: inject command -> shared inject.sh"
assert_contains "$chj" '"matcher": "^Bash$|apply_patch"' "codex: guard matcher registered"
assert_contains "$chj" "scripts/hooks/guard.sh" "codex: guard command -> shared guard.sh"
assert_not_contains "$chj" "AI_MEMORY_GUARD_SCOPE" "codex: guard command carries no AI_MEMORY_GUARD_SCOPE (claude-only bake)"
assert_eq "1" "$(grep -c 'memory_write_guard.sh' "$FHOME/.codex/hooks.json")" "codex: hand-wired write guard kept, none added (claude-only role)"
assert_contains "$chj" "\"command\": \"$CODEX_WG_CMD\"" "codex: hand-wired write-guard entry preserved verbatim"
assert_not_contains "$(cat "$SBROOT/log.codex")" "ai-memory install:" "codex: hand-wired write guard not reported as swept"
assert_contains "$chj" '"SessionStart"' "codex: SessionStart hook registered (base injects via hook, post-flip)"
assert_contains "$chj" "scripts/hooks/session_start_memory.sh" "codex: SessionStart command -> shared session-start script"
assert_not_contains "$chj" "arm_recompact.sh" "codex: SessionStart never wired to arm_recompact (shim deleted; name survives only in hook.sh's stale-entry sweep set)"
if command -v python3 >/dev/null 2>&1; then
    set +e
    CODEX_HOOKS="$FHOME/.codex/hooks.json" FAKE_REPO="$FAKE" python3 - <<'PY' >"$SBROOT/codex-hooks-count.out" 2>&1
import json, os, sys
with open(os.environ["CODEX_HOOKS"]) as f:
    hooks = json.load(f).get("hooks", {})
# count from the manifest, not a literal — see the claude check above
want_n = 1
with open(os.path.join(os.environ["FAKE_REPO"], "harnesses", "codex", "manifest")) as f:
    for line in f:
        k, _, v = line.partition("=")
        if k.strip() == "session_chunks":
            want_n = int(v.strip())
ss = [
    g for g in hooks.get("SessionStart", [])
    if any("scripts/hooks/session_start_memory.sh" in h.get("command", "") for h in g.get("hooks", []) if isinstance(h, dict))
]
if len(ss) != want_n:
    sys.stderr.write("SessionStart entries=%d, manifest says %d\n" % (len(ss), want_n))
    sys.exit(1)
for i, group in enumerate(ss, 1):
    cmd = group["hooks"][0]["command"]
    want = "AI_MEMORY_HOOK_CHUNK=%d/%d" % (i, want_n)
    if want not in cmd:
        sys.stderr.write("missing %s in %r\n" % (want, cmd))
        sys.exit(1)
PY
    # shellcheck disable=SC2319
    rc=$?; set -e
    if [ "$rc" -eq 0 ]; then
        _ok "codex: hooks.json has 12 ordered SessionStart chunks"
    else
        _bad "codex: hooks.json has 12 ordered SessionStart chunks"
        cat "$SBROOT/codex-hooks-count.out"
    fi
fi
set_scope ""
assert_contains "$(cat "$SBROOT/log.codex")" "Run /hooks in codex once" "codex: manual /hooks trust note printed"
# Phase 4: canonical skills fan into the manifest skills_dir (~/.agents/skills)...
assert_file "$FHOME/.agents/skills/demo-skill" "codex: canonical skill fanned to ~/.agents/skills"
# ...and command bodies are delivered AS skills (commands=skill).
assert_file "$FHOME/.agents/skills/pin/SKILL.md"      "codex: command delivered as skill (pin)"
assert_file "$FHOME/.agents/skills/pin/.from-command" "codex: command-skill marked generated"
assert_contains "$(cat "$FHOME/.agents/skills/pin/SKILL.md")" "name: pin" "codex: command-skill wrapper frontmatter"

# --- antigravity (hook archetype, both faces): install = deliver face ---
# Seed an existing settings.json to prove the statusline merge preserves keys.
mkdir -p "$FHOME/.gemini/antigravity-cli"
printf '{\n  "colorScheme": "dark",\n  "trustedWorkspaces": ["/x"]\n}\n' > "$FHOME/.gemini/antigravity-cli/settings.json"
run_install --harness antigravity >"$SBROOT/log.agy" 2>&1; rc=$?
assert_exit 0 "$rc" "antigravity install exits 0"
# hook archetype registers a PreInvocation entry into the global hooks.json.
assert_file "$FHOME/.gemini/config/hooks.json" "antigravity: hooks.json registered"
hj="$(cat "$FHOME/.gemini/config/hooks.json")"
assert_contains "$hj" "ai-memory-inject" "antigravity: namespaced inject hook key present"
assert_contains "$hj" "PreInvocation"    "antigravity: PreInvocation event registered"
assert_contains "$hj" "harnesses/antigravity/hooks/preinvocation.sh" "antigravity: inject command -> preinvocation.sh"
# ...and the PreToolUse enforcement guard.
assert_contains "$hj" "ai-memory-guard"  "antigravity: namespaced guard hook key present"
assert_contains "$hj" "PreToolUse"       "antigravity: PreToolUse event registered"
assert_contains "$hj" "harnesses/antigravity/hooks/pretooluse.sh" "antigravity: guard command -> pretooluse.sh"
# the built AGENTS.md is gone: the memory system never writes the static base.
if [ ! -e "$FHOME/.gemini/config/AGENTS.md" ]; then _ok "antigravity: no memory-built AGENTS.md"; else _bad "antigravity: unexpected AGENTS.md"; fi
assert_file "$FHOME/.agents/skills/demo-skill"   "antigravity: canonical skill in shared ~/.agents/skills"
assert_file "$FHOME/.agents/skills/pin/SKILL.md" "antigravity: command delivered as skill"
# statusline merged into settings.json, existing keys preserved.
sj="$(cat "$FHOME/.gemini/antigravity-cli/settings.json")"
assert_contains "$sj" "statusLine" "antigravity: statusLine registered in settings.json"
assert_contains "$sj" "harnesses/antigravity/statusline.sh" "antigravity: statusLine -> statusline.sh"
assert_contains "$sj" "colorScheme"       "antigravity: existing settings.json keys preserved"
assert_contains "$sj" "trustedWorkspaces" "antigravity: existing trustedWorkspaces preserved"
# execute face is declared in the manifest (consumed by executor.sh)
assert_contains "$(cat "$FAKE/harnesses/antigravity/manifest")" "exec_cmd" "antigravity: manifest declares an execute face"
# idempotent re-run: hooks.json merge is stable, still exactly one entry.
run_install --harness antigravity >"$SBROOT/log.agy2" 2>&1; rc=$?
assert_exit 0 "$rc" "antigravity re-run exits 0"
assert_eq "1" "$(grep -c 'ai-memory-inject' "$FHOME/.gemini/config/hooks.json")" "antigravity: re-run leaves a single inject entry"
assert_eq "1" "$(grep -c 'ai-memory-guard'  "$FHOME/.gemini/config/hooks.json")" "antigravity: re-run leaves a single guard entry"

# --- copilot (hook archetype, owned ~/.copilot/hooks/ai-memory.json) ---
mkdir -p "$FHOME/.copilot/hooks"
printf '{"version":1,"hooks":{"sessionStart":[]}}\n' > "$FHOME/.copilot/hooks/foo.json"
foo_before="$(cat "$FHOME/.copilot/hooks/foo.json")"
# Copilot-only scenario: the codex block above already fanned ~/.agents/skills;
# wipe it so these assertions prove copilot's OWN install populates the shared
# dir (a copilot-only machine must not depend on codex's fan-out).
rm -rf "$FHOME/.agents/skills"
run_install --harness copilot >"$SBROOT/log.copilot" 2>&1; rc=$?
assert_exit 0 "$rc" "copilot install exits 0"
assert_file "$FHOME/.copilot/hooks/ai-memory.json" "copilot: owned ai-memory.json registered"
assert_file "$FHOME/.copilot/statusline.sh" "copilot: statusline linked"
cphj="$(cat "$FHOME/.copilot/hooks/ai-memory.json")"
assert_contains "$cphj" '"version": 1' "copilot: hooks file declares version 1"
assert_contains "$cphj" '"sessionStart"' "copilot: camelCase sessionStart registered"
assert_contains "$cphj" '"timeoutSec": 10' "copilot: sessionStart timeoutSec registered"
assert_contains "$cphj" "harnesses/copilot/hooks/sessionstart.sh" "copilot: sessionStart command -> adapter"
assert_contains "$cphj" "AI_MEMORY_HOOK_FORMAT=md" "copilot: sessionStart renders md"
assert_contains "$cphj" '"preToolUse"' "copilot: camelCase preToolUse registered"
assert_contains "$cphj" '"timeoutSec": 5' "copilot: guard timeoutSec registered"
assert_contains "$cphj" "scripts/hooks/guard.sh" "copilot: preToolUse command -> shared guard"
assert_file "$FHOME/.agents/skills/demo-skill" "copilot: canonical skill fanned to ~/.agents/skills"
assert_file "$FHOME/.agents/skills/pin/SKILL.md"      "copilot: command delivered as skill (pin)"
assert_file "$FHOME/.agents/skills/pin/.from-command" "copilot: command-skill marked generated"
assert_contains "$(cat "$FHOME/.agents/skills/pin/SKILL.md")" "name: pin" "copilot: command-skill wrapper frontmatter"
assert_contains "$cphj" "AI_MEMORY_GUARD_OUTPUT=copilot-json" "copilot: guard output mode registered"
assert_contains "$cphj" '"preCompact"' "copilot: camelCase preCompact registered"
assert_contains "$cphj" "harnesses/copilot/hooks/precompact.sh" "copilot: preCompact command -> sentinel arm adapter"
assert_contains "$cphj" '"postToolUse"' "copilot: camelCase postToolUse registered"
assert_contains "$cphj" "harnesses/copilot/hooks/posttooluse.sh" "copilot: postToolUse command -> re-inject adapter"
assert_contains "$(cat "$SBROOT/log.copilot")" "STATUS_LINE" "copilot: notes mention manual experimental statusline flag"
assert_contains "$(cat "$SBROOT/log.copilot")" ".copilot/statusline.sh" "copilot: notes mention manual statusline command"
assert_eq "4" "$(grep -c '"type": "command"' "$FHOME/.copilot/hooks/ai-memory.json")" \
    "copilot: owned hooks file has four event rows"
assert_eq "$foo_before" "$(cat "$FHOME/.copilot/hooks/foo.json")" "copilot: sibling hook file untouched"
first_copilot="$(cat "$FHOME/.copilot/hooks/ai-memory.json")"
run_install --harness copilot >"$SBROOT/log.copilot2" 2>&1; rc=$?
assert_exit 0 "$rc" "copilot re-run exits 0"
assert_eq "$first_copilot" "$(cat "$FHOME/.copilot/hooks/ai-memory.json")" "copilot: re-run is byte-identical"

rm -f "$FHOME/.copilot/hooks/ai-memory.json"
PATH="/usr/bin:/bin" run_install --harness copilot >"$SBROOT/log.copilot-missing" 2>&1; rc=$?
assert_exit 0 "$rc" "copilot missing binary: install skips without error"
if [ ! -e "$FHOME/.copilot/hooks/ai-memory.json" ]; then
    _ok "copilot missing binary: hook registration skipped"
else
    _bad "copilot missing binary: unexpected hook file"
fi
assert_contains "$(cat "$SBROOT/log.copilot-missing")" "copilot not found on PATH" \
    "copilot missing binary: skip reason reported"

# --- doc surface (synthetic file harness with commands=doc, no skills_dir) ---
mkdir -p "$FAKE/harnesses/doch"
printf '%s\n' \
    'name = doch' 'archetype = file' 'format = md' \
    'context_target = ~/.doch/CONTEXT.md' 'refresh = launch' 'commands = doc' \
    > "$FAKE/harnesses/doch/manifest"
run_install --harness doch >"$SBROOT/log.doch" 2>&1; rc=$?
assert_exit 0 "$rc" "doc harness install exits 0"
assert_file "$FHOME/.doch/MEMORY-COMMANDS.md" "doc harness: commands reference generated next to context_target"
assert_contains "$(cat "$FHOME/.doch/MEMORY-COMMANDS.md")" "/pin" "doc: reference lists a command"
assert_contains "$(cat "$SBROOT/log.doch")" "skills fan-out skipped" "doc harness: no skills_dir reported, not failed"

# --- unknown harness errors ---
set +e
run_install --harness bogus >"$SBROOT/log.bogus" 2>&1; rc=$?
assert_exit 1 "$rc" "unknown harness: exit 1"

# --- --list ---
# --- hooks_json harness WITHOUT guard_script: injection, no enforcement ---
# The advertised extension point. `guard_script` is optional, so _hook_register_json
# must return 0 when it is absent — a guard notice written as `[ -n "$gs" ] && info …`
# would be the function's last statement, return 1 on the empty case, and `set -e`
# would kill install.sh on return: hooks registered, every later step silently
# skipped, exit code hidden behind the abort. Assert the run REACHES the later steps,
# not merely that it exits 0. No linter detects this; only driving it does.
mkdir -p "$FAKE/harnesses/noguard"
printf '%s\n' \
    'name = noguard' 'archetype = hook' 'format = xml' \
    'hooks_json  = ~/.noguard/hooks.json' \
    'hook_script = $MEMORY_DIR/harnesses/antigravity/hooks/preinvocation.sh' \
    'skills_dir  = ~/.noguard/skills' 'commands = skill' \
    '[hooks]' 'per_turn_inject = PreInvocation' \
    > "$FAKE/harnesses/noguard/manifest"
rm -f "$FAKE/config.local.sh"
run_install --harness noguard >"$SBROOT/log.noguard" 2>&1; rc=$?
assert_exit 0 "$rc" "no-guard hook harness install exits 0"
assert_file "$FHOME/.noguard/hooks.json" "no-guard: hooks.json registered"
nghj="$(cat "$FHOME/.noguard/hooks.json")"
assert_contains     "$nghj" "ai-memory-inject" "no-guard: inject hook registered"
assert_not_contains "$nghj" "ai-memory-guard"  "no-guard: no guard entry without guard_script"
# The abort landed between the hooks step and everything after it — these are the
# steps a returning-1 _hook_register_json silently skipped.
assert_file "$FHOME/.noguard/skills/demo-skill" "no-guard: skills fan-out ran AFTER the hooks step"
assert_file "$FAKE/config.local.sh"             "no-guard: config.local.sh stamped AFTER the hooks step"
assert_not_contains "$(cat "$SBROOT/log.noguard")" "Traceback" "no-guard: no python traceback"

# --- codex hybrid version floor: too-old/absent-compatible path skips hooks ---
mkdir -p "$FAKE/harnesses/codexfloor"
printf '%s\n' \
    'name = codexfloor' 'archetype = file' 'format = md' \
    'context_target = ~/.codexfloor/AGENTS.md' 'refresh = launch' \
    'hooks_json = ~/.codexfloor/hooks.json' \
    'hook_script = $MEMORY_DIR/scripts/hooks/inject.sh' \
    'guard_script = $MEMORY_DIR/scripts/hooks/guard.sh' \
    'hooks_min_version = 999.0.0' \
    '[hooks]' 'per_turn_inject = UserPromptSubmit' 'infra_guard = PreToolUse:^Bash$|apply_patch' \
    > "$FAKE/harnesses/codexfloor/manifest"
run_install --harness codexfloor >"$SBROOT/log.codexfloor" 2>&1; rc=$?
assert_exit 0 "$rc" "codex hybrid version floor: install exits 0"
if [ ! -e "$FHOME/.codexfloor/hooks.json" ]; then
    _ok "codex hybrid version floor: hook registration skipped"
else
    _bad "codex hybrid version floor: unexpected hooks.json"
fi
assert_contains "$(cat "$SBROOT/log.codexfloor")" "below hooks_min_version 999.0.0" \
    "codex hybrid version floor: skip reason reported"

out="$(HOME="$FHOME" bash "$FAKE/install.sh" --list 2>&1)"
assert_contains "$out" "claude"      "--list shows claude"
assert_contains "$out" "codex"       "--list shows codex"
assert_contains "$out" "antigravity" "--list shows antigravity"
assert_contains "$out" "copilot"     "--list shows copilot"

# --- claude settings.json merge must fail closed on a non-object ------------
rm -f "$FHOME/.claude"/settings.json.bak-*
printf '[1, 2, 3]\n' > "$FHOME/.claude/settings.json"
set +e
run_install --harness claude >"$SBROOT/log.claude-bad-settings" 2>&1; rc=$?
set -e
assert_exit 3 "$rc" "claude non-object settings.json: install exits 3"
assert_eq "[1, 2, 3]" "$(cat "$FHOME/.claude/settings.json")" \
    "claude non-object settings.json: file untouched"
assert_eq "0" "$(find "$FHOME/.claude" -name 'settings.json.bak-*' | grep -c .)" \
    "claude non-object settings.json: no backup written"
assert_contains "$(cat "$SBROOT/log.claude-bad-settings")" "not a JSON object" \
    "claude non-object settings.json: says why it refused"

# --- hooks.json merge must never destroy a config it cannot parse -------------
# `except Exception: data = {}` followed by a rewrite silently replaced a JSONC /
# trailing-comma hooks.json with our two keys, no backup — contradicting
# install.sh's "backs up anything it would overwrite". An unparseable file is one
# we do not understand: touch nothing, say so, fail. Verified by driving install,
# not by reading the merge.
mkdir -p "$FAKE/harnesses/jsonmerge"
printf '%s\n' \
    'name = jsonmerge' 'archetype = hook' 'format = xml' \
    'hooks_json  = ~/.jsonmerge/hooks.json' \
    'hook_script = $MEMORY_DIR/harnesses/antigravity/hooks/preinvocation.sh' \
    '[hooks]' 'per_turn_inject = PreInvocation' \
    > "$FAKE/harnesses/jsonmerge/manifest"
JM="$FHOME/.jsonmerge/hooks.json"
mkdir -p "$FHOME/.jsonmerge"

# (1) unparseable (JSONC comment + trailing comma): refuse, preserve, no backup.
cat > "$JM" <<'EOF'
{
  // a real editor writes these
  "userHook": {"PreInvocation": [{"type": "command", "command": "echo mine"}]},
}
EOF
set +e
run_install --harness jsonmerge >"$SBROOT/log.jm1" 2>&1; rc=$?
set -e
assert_exit 1 "$rc" "unparseable hooks.json: install fails rather than clobbering"
assert_contains "$(cat "$JM")" "userHook" "unparseable hooks.json: the user's file is untouched"
assert_not_contains "$(cat "$JM")" "ai-memory-inject" "unparseable hooks.json: nothing was written"
assert_contains "$(cat "$SBROOT/log.jm1")" "not a JSON object" "unparseable hooks.json: says why it refused"
assert_eq "0" "$(find "$FHOME/.jsonmerge" -name 'hooks.json.bak-*' | grep -c .)" \
    "unparseable hooks.json: no backup written (nothing was overwritten)"

# (2) valid JSON carrying a foreign key: merge, preserve it, and BACK UP first.
printf '%s\n' '{"userHook": {"PreInvocation": [{"type": "command", "command": "echo mine"}]}}' > "$JM"
run_install --harness jsonmerge >"$SBROOT/log.jm2" 2>&1; rc=$?
assert_exit 0 "$rc" "valid hooks.json: install succeeds"
assert_contains "$(cat "$JM")" "userHook"         "valid hooks.json: foreign key preserved"
assert_contains "$(cat "$JM")" "ai-memory-inject" "valid hooks.json: our entry merged in"
bak="$(find "$FHOME/.jsonmerge" -name 'hooks.json.bak-*' | head -1)"
assert_file "$bak" "valid hooks.json: a backup was written before the rewrite"
assert_contains "$(cat "$bak")" "userHook" "backup holds the ORIGINAL content"
assert_not_contains "$(cat "$bak")" "ai-memory-inject" "backup predates our merge"

# (3) a top-level JSON array parses fine but is not an object: also refuse.
rm -f "$FHOME/.jsonmerge"/hooks.json.bak-*
printf '%s\n' '[1, 2, 3]' > "$JM"
set +e
run_install --harness jsonmerge >"$SBROOT/log.jm3" 2>&1; rc=$?
set -e
assert_exit 1 "$rc" "top-level array hooks.json: install fails"
assert_contains "$(cat "$JM")" "1" "top-level array hooks.json: file untouched"
assert_eq "0" "$(find "$FHOME/.jsonmerge" -name 'hooks.json.bak-*' | grep -c .)" \
    "top-level array hooks.json: no backup written"

finish
