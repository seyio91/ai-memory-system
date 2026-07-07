#!/usr/bin/env bash
# install.sh (manifest-driven engine): --harness claude reproduces the hook
# wiring (hooks/commands/statusline/skills/agents); --harness codex runs the file
# archetype (context prep, no symlink, deferred surfaces reported); idempotent
# re-run; unknown harness errors; --list. Hermetic: a fake repo + fake HOME, so
# config-stamp and template-seed never touch the real tree.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
SBROOT="$(new_sandbox)"; FAKE="$SBROOT/repo"; FHOME="$SBROOT/home"
trap 'rm -rf "$SBROOT"' EXIT
mkdir -p "$FAKE" "$FHOME"
# install.sh resolves its repo root with `pwd -P`; match that physical path so the
# symlink-target string assertions below compare equal (macOS /var -> /private/var).
FAKE="$(cd "$FAKE" && pwd -P)"

# Stage a self-contained fake repo: real engine + harness assets, minimal stores.
cp -R "$REPO/scripts" "$FAKE/scripts"
cp -R "$REPO/harnesses" "$FAKE/harnesses"
cp "$REPO/install.sh" "$FAKE/install.sh"
printf '# identity template\n' > "$FAKE/identity.template.md"
printf '# index template\n'    > "$FAKE/index.template.md"
mkdir -p "$FAKE/skills/demo-skill"
printf -- '---\nname: demo-skill\ndescription: demo\n---\n# demo\n' > "$FAKE/skills/demo-skill/SKILL.md"
mkdir -p "$FAKE/agents"
printf -- '---\nname: demo-agent\ndescription: demo\n---\nbody\n' > "$FAKE/agents/demo-agent.md"

run_install() { HOME="$FHOME" MEMORY_DIR="$FAKE" bash "$FAKE/install.sh" "$@"; }

# --- claude (hook archetype) ---
run_install --harness claude >"$SBROOT/log.claude" 2>&1; rc=$?
assert_exit 0 "$rc" "claude install exits 0"
for h in inject_memory.sh session_start_memory.sh memory_common.sh block_task_tools.sh; do
    assert_file "$FHOME/.claude/hooks/$h" "hook present: $h"
done
assert_file "$FHOME/.claude/statusline.sh"        "statusline linked"
assert_file "$FHOME/.claude/commands/pin.md"      "native command linked (pin)"
assert_file "$FHOME/.claude/skills/demo-skill"    "skill fanned out"
assert_file "$FHOME/.claude/agents/demo-agent.md" "agent fanned out"
assert_eq "$FAKE/harnesses/claude/hooks/inject_memory.sh" \
    "$(readlink "$FHOME/.claude/hooks/inject_memory.sh")" "hook target -> harnesses/claude/hooks"
assert_eq "$FAKE/harnesses/claude/commands/pin.md" \
    "$(readlink "$FHOME/.claude/commands/pin.md")" "command target -> harnesses/claude/commands"
assert_contains "$(cat "$FAKE/config.local.sh")" "export MEMORY_DIR=" "config.local.sh stamped in FAKE repo"

# --- idempotent re-run ---
run_install --harness claude >"$SBROOT/log.claude2" 2>&1; rc=$?
assert_exit 0 "$rc" "claude re-run exits 0"
assert_contains "$(cat "$SBROOT/log.claude2")" "ok (already linked)" "re-run: already-linked (no churn)"

# --- codex (file archetype): context prep + skills + commands-as-skills ---
run_install --harness codex >"$SBROOT/log.codex" 2>&1; rc=$?
assert_exit 0 "$rc" "codex install exits 0"
assert_file "$FHOME/.codex" "codex context dir prepared"
if [ ! -e "$FHOME/.codex/AGENTS.md" ]; then _ok "codex: no AGENTS.md symlink (built at launch)"; else _bad "codex: unexpected AGENTS.md symlink"; fi
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
run_install --harness bogus >"$SBROOT/log.bogus" 2>&1; rc=$?
assert_exit 1 "$rc" "unknown harness: exit 1"

# --- --list ---
out="$(HOME="$FHOME" bash "$FAKE/install.sh" --list 2>&1)"
assert_contains "$out" "claude"      "--list shows claude"
assert_contains "$out" "codex"       "--list shows codex"
assert_contains "$out" "antigravity" "--list shows antigravity"

finish
