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
cp "$REPO/install.sh" "$FAKE/install.sh"
printf '# identity template\n' > "$FAKE/identity.template.md"
printf '# index template\n'    > "$FAKE/index.template.md"
printf '# skills template\n[[skills]]\nname = "template-skill"\nurl = "https://example.invalid/skills.git"\nref = "main"\n' > "$FAKE/skills.toml.example"
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
export PATH="$FBIN:$PATH"

run_install() { HOME="$FHOME" MEMORY_DIR="$FAKE" bash "$FAKE/install.sh" "$@"; }

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
assert_contains "$csj" "statusLine" "claude settings: existing statusLine preserved"
assert_contains "$csj" "bash /custom/statusline.sh" "claude settings: existing statusLine command preserved"
assert_contains "$csj" "permissions" "claude settings: permissions preserved"
assert_contains "$csj" "Stop" "claude settings: user Stop hook preserved"
assert_contains "$csj" "echo user-stop-hook" "claude settings: user hook command preserved"
assert_contains "$(cat "$SBROOT/log.claude")" "Hook entries were auto-merged" "claude notes: settings auto-merge reported"
assert_file "$FAKE/skills.toml"                   "root skills.toml seeded from template"
assert_eq "$(cat "$FAKE/skills.toml.example")" "$(cat "$FAKE/skills.toml")" "skills.toml seeded as an exact template copy"
assert_contains "$(cat "$SBROOT/log.claude")" "seeded skills.toml from template" "install reports the skills.toml seed step"
set +e; [ -d "$FAKE/.skill-cache/template-skill" ]
# Intentional status capture around a negative assertion.
# shellcheck disable=SC2319
e=$?; set -e
assert_exit 1 "$e" "install seed step does not resolve remote skills"
assert_eq "$FAKE/harnesses/claude/commands/pin.md" \
    "$(readlink "$FHOME/.claude/commands/pin.md")" "command target -> harnesses/claude/commands"
assert_contains "$(cat "$FAKE/config.local.sh")" "export MEMORY_DIR=" "config.local.sh stamped in FAKE repo"

# --- idempotent re-run ---
printf '# keep local choices\n' > "$FAKE/skills.toml"
run_install --harness claude >"$SBROOT/log.claude2" 2>&1; rc=$?
assert_exit 0 "$rc" "claude re-run exits 0"
assert_contains "$(cat "$SBROOT/log.claude2")" "ok (already linked)" "re-run: already-linked (no churn)"
assert_eq "# keep local choices" "$(cat "$FAKE/skills.toml")" "existing skills.toml is not overwritten"
assert_not_contains "$(cat "$SBROOT/log.claude2")" "seeded skills.toml from template" "existing skills.toml skips seed step"
if command -v python3 >/dev/null 2>&1; then
    CLAUDE_SETTINGS="$FHOME/.claude/settings.json" FAKE_REPO="$FAKE" python3 - <<'PY' >"$SBROOT/claude-settings-check.out" 2>&1
import json, os, sys
path = os.environ["CLAUDE_SETTINGS"]
repo = os.environ["FAKE_REPO"]
with open(path) as f:
    data = json.load(f)
hooks = data.get("hooks", {})
expected = {
    "SessionStart": ("", "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=xml AI_MEMORY_HOOK_EVENT=SessionStart bash %s/scripts/hooks/session_start_memory.sh" % (repo, repo)),
    "UserPromptSubmit": ("", "env MEMORY_DIR=%s AI_MEMORY_HOOK_FORMAT=xml AI_MEMORY_HOOK_EVENT=UserPromptSubmit bash %s/scripts/hooks/inject.sh" % (repo, repo)),
    "PreToolUse": ("TaskCreate|TaskUpdate", "bash %s/harnesses/claude/hooks/block_task_tools.sh" % repo),
}
for event, (matcher, command) in expected.items():
    groups = hooks.get(event, [])
    matches = [
        g for g in groups
        if isinstance(g, dict)
        and (not matcher or g.get("matcher") == matcher)
        and any(isinstance(h, dict) and h.get("command") == command for h in g.get("hooks", []))
    ]
    if len(matches) != 1:
        sys.stderr.write("%s expected one ai-memory hook, got %d\n" % (event, len(matches)))
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
    rc=$?
    if [ "$rc" -eq 0 ]; then
        _ok "claude settings: re-run is idempotent and preserves siblings"
    else
        _bad "claude settings: re-run is idempotent and preserves siblings"
        cat "$SBROOT/claude-settings-check.out"
    fi
fi

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
assert_contains "$chj" '"SessionStart"' "codex: SessionStart hook registered (base injects via hook, post-flip)"
assert_contains "$chj" "scripts/hooks/session_start_memory.sh" "codex: SessionStart command -> shared session-start script"
assert_not_contains "$chj" "arm_recompact.sh" "codex: SessionStart no longer wired to arm_recompact (shim only for stale hooks.json)"
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
