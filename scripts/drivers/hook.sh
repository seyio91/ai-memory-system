#!/usr/bin/env bash
# drivers/hook.sh — install driver for the `hook` archetype (in-band, live
# per-prompt injection). Two registration styles, chosen by the manifest:
#   - hooks_dir/settings_json (Claude): install runtime assets and merge hook
#                 entries into the harness's native settings JSON.
#   - hooks_json (Antigravity): register a namespaced PreInvocation entry that runs
#                 hook_script into the harness's JSON hooks file.
# Codex is a sanctioned hybrid: file archetype plus the same native hooks schema
# registration branch called directly by install.sh after the file driver.
# Sourced by install.sh, which provides HARNESS, HARNESS_DIR, MANIFEST, MEMORY_DIR
# and the helpers step/info/link plus manifest_get. Exposes driver_install +
# driver_notes.

# driver_install — dispatch on which registration style the manifest declares.
driver_install() {
    local hooks_dir hooks_json settings_json sl_settings
    hooks_dir="$(manifest_get "$MANIFEST" hooks_dir)"
    hooks_json="$(manifest_get "$MANIFEST" hooks_json)"
    settings_json="$(manifest_get "$MANIFEST" settings_json)"

    if [ -n "$hooks_dir" ]; then
        _hook_install_scripts "$hooks_dir"
        if [ -z "$settings_json" ]; then
            settings_json="${hooks_dir%/hooks}/settings.json"
        fi
        _hook_register_native_json "$settings_json"
    elif [ -n "$hooks_json" ]; then
        _hook_register_json "$hooks_json"
    else
        info "hook archetype but neither hooks_dir nor hooks_json in manifest — nothing wired"
    fi

    # Optional statusline registered into a JSON settings file (Antigravity —
    # ~/.gemini/antigravity-cli/settings.json → "statusLine"). Distinct from the
    # hooks.json above and from Claude's symlinked statusline (hooks_dir style).
    sl_settings="$(manifest_get "$MANIFEST" statusline_settings)"
    if [ -n "$sl_settings" ]; then
        _hook_register_statusline "$sl_settings"
    fi
}

# _hook_ts — timestamp for .bak-<ts> names. install.sh exports TS; fall back so the
# driver stays usable (and testable) standalone.
_hook_ts() { printf '%s' "${TS:-$(date +%Y%m%d-%H%M%S)}"; }

# _hook_merge_rc <rc> <path> — interpret a merge helper's exit status.
#
# FAIL CLOSED. The old code did `except Exception: data = {}` and then rewrote the
# file, so a JSONC / trailing-comma settings.json or hooks.json was silently
# destroyed — with no backup, contradicting install.sh's promise to back up what it
# overwrites. An unparseable file is a file we do not understand; the only safe move
# is to touch nothing and say so loudly. Returning 1 aborts the install under
# `set -e`, which is intended: a half-registered harness nobody noticed is exactly
# the fail-open outcome this replaces.
_hook_merge_rc() {
    local rc="$1" path="$2"
    [ "$rc" -eq 0 ] && return 0
    if [ "$rc" -eq 3 ]; then
        printf '  ERROR %s exists but is not a JSON object.\n' "$path" >&2
        printf '        Refusing to overwrite it. Nothing was written and nothing was backed up.\n' >&2
        printf '        Fix or move the file, then re-run install.\n' >&2
    else
        printf '  ERROR merging into %s failed (exit %s).\n' "$path" "$rc" >&2
    fi
    return 1
}

# _hook_register_statusline <settings_json> — merge a "statusLine" entry pointing
# at statusline_script into the harness's JSON settings file, idempotently and
# WITHOUT clobbering existing keys (colorScheme, trustedWorkspaces, …).
_hook_register_statusline() {
    local settings="$1" ss
    ss="$(manifest_get "$MANIFEST" statusline_script)"; ss="${ss//\$MEMORY_DIR/$MEMORY_DIR}"
    [ -n "$ss" ] || { info "statusline_settings set but no statusline_script — nothing to register"; return; }
    chmod +x "$ss" 2>/dev/null || true

    step "Statusline -> $settings"
    mkdir -p "$(dirname "$settings")"
    if command -v python3 >/dev/null 2>&1; then
        local rc=0 bak
        bak="$settings.bak-$(_hook_ts)"   # resolve ONCE: two calls can straddle a second
        AIM_SL_SETTINGS="$settings" AIM_SL_CMD="bash $ss" AIM_BAK="$bak" python3 - <<'PY' || rc=$?
import json, os, shutil, sys
path = os.environ["AIM_SL_SETTINGS"]
cmd  = os.environ["AIM_SL_CMD"]
bak  = os.environ["AIM_BAK"]
data = {}
if os.path.exists(path):
    with open(path) as f:
        raw = f.read()
    # An empty/whitespace-only file carries no user config: treat as {} and proceed.
    if raw.strip():
        try:
            data = json.loads(raw)
        except Exception as e:
            sys.stderr.write("not valid JSON: %s\n" % e)
            sys.exit(3)
        if not isinstance(data, dict):
            sys.stderr.write("top-level JSON is %s, expected an object\n" % type(data).__name__)
            sys.exit(3)
    # Back up BEFORE rewriting — install.sh promises to back up what it overwrites.
    shutil.copy2(path, bak)
data["statusLine"] = {"type": "", "command": cmd, "enabled": True}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
        _hook_merge_rc "$rc" "$settings" || return 1
        if [ -f "$bak" ]; then
            info "backed up existing -> $bak"
        fi
        info "registered statusLine -> bash $ss"
    else
        info "python3 absent — add \"statusLine\": {\"command\": \"bash $ss\", \"enabled\": true} to $settings by hand"
    fi
}

# _hook_install_scripts <hooks_dir> — Claude style: keep the runtime root around
# and symlink the statusline, if any. Hook scripts run by absolute path from
# settings.json, so harnesses/claude/hooks/*.sh is no longer fanned into HOME.
_hook_install_scripts() {
    local hooks_dir="$1" statusline
    step "Hook runtime -> $hooks_dir"
    mkdir -p "$hooks_dir"

    statusline="$(manifest_get "$MANIFEST" statusline)"
    if [ -n "$statusline" ]; then
        if [ -f "$HARNESS_DIR/statusline.sh" ]; then
            step "Status line -> $statusline"
            chmod +x "$HARNESS_DIR/statusline.sh"
            link "$HARNESS_DIR/statusline.sh" "$statusline"
        else
            info "no $HARNESS_DIR/statusline.sh — skipping status line"
        fi
    fi
}

# _hook_register_json <hooks_json> — Antigravity style: register namespaced hook
# entries into the JSON hooks file from the manifest's [hooks] role map.
# Idempotent merge via python3 (preserves any other hooks + only touches our
# namespaced keys); if python3 is absent, write a new file wholesale, or (file
# already exists) defer to a manual merge note.
_hook_register_json() {
    local hooks_json="$1" hs gs role spec event matcher
    local inject_event="" inject_matcher="" guard_event="" guard_matcher="" hook_count=0
    hs="$(manifest_get "$MANIFEST" hook_script)"; hs="${hs//\$MEMORY_DIR/$MEMORY_DIR}"
    gs="$(manifest_get "$MANIFEST" guard_script)"; gs="${gs//\$MEMORY_DIR/$MEMORY_DIR}"
    [ -n "$hs" ] || { info "hooks_json set but no hook_script in manifest — nothing to register"; return; }
    chmod +x "$hs" 2>/dev/null || true
    [ -n "$gs" ] && chmod +x "$gs" 2>/dev/null || true

    while IFS=$'\t' read -r role spec; do
        [ -n "$role" ] || continue
        event="${spec%%:*}"
        matcher=""
        case "$spec" in *:*) matcher="${spec#*:}" ;; esac
        case "$role" in
            per_turn_inject)
                inject_event="$event"
                inject_matcher="$matcher"
                hook_count=$((hook_count + 1))
                ;;
            infra_guard)
                [ -n "$gs" ] || continue
                guard_event="$event"
                guard_matcher="$matcher"
                hook_count=$((hook_count + 1))
                ;;
            *)
                info "hook role '$role' has no hooks_json script association — skipping"
                ;;
        esac
    done < <(manifest_hooks "$MANIFEST")

    if [ "$hook_count" -eq 0 ]; then
        info "hooks_json set but [hooks] has no registerable roles — nothing to register"
        return
    fi

    step "Hooks -> $hooks_json"
    mkdir -p "$(dirname "$hooks_json")"
    if command -v python3 >/dev/null 2>&1; then
        local rc=0 bak
        bak="$hooks_json.bak-$(_hook_ts)"   # resolve ONCE: two calls can straddle a second
        AIM_HOOKS_JSON="$hooks_json" AIM_INJECT_CMD="bash $hs" AIM_GUARD_CMD="${gs:+bash $gs}" \
            AIM_INJECT_EVENT="$inject_event" AIM_INJECT_MATCHER="$inject_matcher" \
            AIM_GUARD_EVENT="$guard_event" AIM_GUARD_MATCHER="$guard_matcher" \
            AIM_BAK="$bak" python3 - <<'PY' || rc=$?
import json, os, shutil, sys
path = os.environ["AIM_HOOKS_JSON"]
inject = os.environ["AIM_INJECT_CMD"]
guard  = os.environ.get("AIM_GUARD_CMD", "")
inject_event = os.environ.get("AIM_INJECT_EVENT", "")
inject_matcher = os.environ.get("AIM_INJECT_MATCHER", "")
guard_event = os.environ.get("AIM_GUARD_EVENT", "")
guard_matcher = os.environ.get("AIM_GUARD_MATCHER", "")
bak  = os.environ["AIM_BAK"]
data = {}
if os.path.exists(path):
    with open(path) as f:
        raw = f.read()
    # An empty/whitespace-only file carries no user config: treat as {} and proceed.
    if raw.strip():
        try:
            data = json.loads(raw)
        except Exception as e:
            sys.stderr.write("not valid JSON: %s\n" % e)
            sys.exit(3)
        if not isinstance(data, dict):
            sys.stderr.write("top-level JSON is %s, expected an object\n" % type(data).__name__)
            sys.exit(3)
    # Back up BEFORE rewriting — install.sh promises to back up what it overwrites.
    shutil.copy2(path, bak)
def entry(event, matcher, cmd):
    if matcher:
        return {event: [{"matcher": matcher, "hooks": [{"type": "command", "command": cmd}]}]}
    return {event: [{"type": "command", "command": cmd}]}

if inject_event:
    data["ai-memory-inject"] = entry(inject_event, inject_matcher, inject)
if guard and guard_event:
    data["ai-memory-guard"] = entry(guard_event, guard_matcher, guard)
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
        _hook_merge_rc "$rc" "$hooks_json" || return 1
        # NB: an `[ -f x ] && info …` one-liner here would be the `set -e`
        # last-statement trap that once aborted install.sh mid-run. Use an if.
        if [ -f "$bak" ]; then
            info "backed up existing -> $bak"
        fi
        if [ -n "$inject_event" ]; then
            info "registered $inject_event 'ai-memory-inject' -> bash $hs"
        fi
        if [ -n "$guard_event" ]; then
            info "registered $guard_event  'ai-memory-guard'  -> bash $gs"
        fi
    elif [ ! -e "$hooks_json" ]; then
        {
            if [ -n "$inject_event" ]; then
                printf '{\n  "ai-memory-inject": {\n    "%s": [\n' "$inject_event"
                if [ -n "$inject_matcher" ]; then
                    printf '      { "matcher": "%s", "hooks": [ { "type": "command", "command": "bash %s" } ] }\n' "$inject_matcher" "$hs"
                else
                    printf '      { "type": "command", "command": "bash %s" }\n' "$hs"
                fi
                printf '    ]\n  }'
            fi
            if [ -n "$guard_event" ]; then
                if [ -n "$inject_event" ]; then
                    printf ','
                else
                    printf '{'
                fi
                printf '\n  "ai-memory-guard": {\n    "%s": [\n' "$guard_event"
                if [ -n "$guard_matcher" ]; then
                    printf '      { "matcher": "%s", "hooks": [ { "type": "command", "command": "bash %s" } ] }\n' "$guard_matcher" "$gs"
                else
                    printf '      { "type": "command", "command": "bash %s" }\n' "$gs"
                fi
                printf '    ]\n  }'
            fi
            printf '\n}\n'
        } > "$hooks_json"
        info "wrote $hooks_json (no python3 — new file)"
    else
        info "python3 absent and $hooks_json exists — merge the 'ai-memory-inject'/'ai-memory-guard' entries by hand (see notes)"
    fi
}

# _hook_register_native_json <settings_or_hooks_json> — register Claude/Codex
# native hook schema: top-level {"hooks": {"Event": [{matcher?, hooks:[...]}]}}.
# Only ai-memory hook commands are removed/replaced; sibling top-level settings
# and unrelated hook groups are preserved.
_hook_register_native_json() {
    local hooks_json="$1" fmt role spec event matcher key script hook_count=0
    local inject_event="" inject_matcher="" inject_cmd=""
    local guard_event="" guard_matcher="" guard_cmd=""
    local session_event="" session_matcher="" session_cmd=""
    local block_event="" block_matcher="" block_cmd=""
    fmt="$(manifest_get "$MANIFEST" format)"
    [ -n "$fmt" ] || fmt=xml

    while IFS=$'\t' read -r role spec; do
        [ -n "$role" ] || continue
        event="${spec%%:*}"
        matcher=""
        case "$spec" in *:*) matcher="${spec#*:}" ;; esac
        key=""
        case "$role" in
            per_turn_inject)   key=hook_script ;;
            infra_guard)       key=guard_script ;;
            session_bootstrap) key=session_script ;;
            task_tool_block)   key=block_script ;;
            *)
                info "hook role '$role' has no native JSON script association — skipping"
                continue
                ;;
        esac
        script="$(manifest_get "$MANIFEST" "$key")"; script="${script//\$MEMORY_DIR/$MEMORY_DIR}"
        if [ -z "$script" ]; then
            info "hook role '$role' missing $key — skipping"
            continue
        fi
        chmod +x "$script" 2>/dev/null || true
        case "$role" in
            per_turn_inject)
                inject_event="$event"; inject_matcher="$matcher"
                inject_cmd="env MEMORY_DIR=$MEMORY_DIR AI_MEMORY_HOOK_FORMAT=$fmt AI_MEMORY_HOOK_EVENT=$event bash $script"
                ;;
            infra_guard)
                guard_event="$event"; guard_matcher="$matcher"
                guard_cmd="env MEMORY_DIR=$MEMORY_DIR bash $script"
                ;;
            session_bootstrap)
                session_event="$event"; session_matcher="$matcher"
                session_cmd="bash $script"
                ;;
            task_tool_block)
                block_event="$event"; block_matcher="$matcher"
                block_cmd="bash $script"
                ;;
        esac
        hook_count=$((hook_count + 1))
    done < <(manifest_hooks "$MANIFEST")

    if [ "$hook_count" -eq 0 ]; then
        info "native hook target set but [hooks] has no registerable roles — nothing to register"
        return
    fi

    step "Native hooks -> $hooks_json"
    mkdir -p "$(dirname "$hooks_json")"
    if command -v python3 >/dev/null 2>&1; then
        local rc=0 bak
        bak="$hooks_json.bak-$(_hook_ts)"
        AIM_HOOKS_JSON="$hooks_json" AIM_BAK="$bak" \
            AIM_INJECT_EVENT="$inject_event" AIM_INJECT_MATCHER="$inject_matcher" AIM_INJECT_CMD="$inject_cmd" \
            AIM_GUARD_EVENT="$guard_event" AIM_GUARD_MATCHER="$guard_matcher" AIM_GUARD_CMD="$guard_cmd" \
            AIM_SESSION_EVENT="$session_event" AIM_SESSION_MATCHER="$session_matcher" AIM_SESSION_CMD="$session_cmd" \
            AIM_BLOCK_EVENT="$block_event" AIM_BLOCK_MATCHER="$block_matcher" AIM_BLOCK_CMD="$block_cmd" \
            python3 - <<'PY' || rc=$?
import json, os, shutil, sys

path = os.environ["AIM_HOOKS_JSON"]
bak = os.environ["AIM_BAK"]
ours = (
    "scripts/hooks/inject.sh",
    "scripts/hooks/guard.sh",
    "session_start_memory.sh",
    "block_task_tools.sh",
)

data = {}
if os.path.exists(path):
    with open(path) as f:
        raw = f.read()
    if raw.strip():
        try:
            data = json.loads(raw)
        except Exception as e:
            sys.stderr.write("not valid JSON: %s\n" % e)
            sys.exit(3)
        if not isinstance(data, dict):
            sys.stderr.write("top-level JSON is %s, expected an object\n" % type(data).__name__)
            sys.exit(3)
    shutil.copy2(path, bak)

hooks = data.get("hooks", {})
if hooks is None:
    hooks = {}
if not isinstance(hooks, dict):
    sys.stderr.write("hooks key is %s, expected an object\n" % type(hooks).__name__)
    sys.exit(3)
data["hooks"] = hooks

def is_ours(cmd):
    return any(marker in cmd for marker in ours)

for event in list(hooks.keys()):
    groups = hooks.get(event, [])
    if groups is None:
        groups = []
    if not isinstance(groups, list):
        sys.stderr.write("hooks.%s is %s, expected an array\n" % (event, type(groups).__name__))
        sys.exit(3)
    cleaned = []
    for group in groups:
        if not isinstance(group, dict):
            cleaned.append(group)
            continue
        entries = group.get("hooks")
        if isinstance(entries, list):
            kept = [
                h for h in entries
                if not (isinstance(h, dict) and is_ours(str(h.get("command", ""))))
            ]
            if kept:
                new_group = dict(group)
                new_group["hooks"] = kept
                cleaned.append(new_group)
        else:
            cmd = str(group.get("command", ""))
            if not is_ours(cmd):
                cleaned.append(group)
    hooks[event] = cleaned

def add(event, matcher, cmd):
    if not event or not cmd:
        return
    group = {"hooks": [{"type": "command", "command": cmd}]}
    if matcher:
        group["matcher"] = matcher
    hooks.setdefault(event, []).append(group)

for prefix in ("INJECT", "GUARD", "SESSION", "BLOCK"):
    add(
        os.environ.get("AIM_%s_EVENT" % prefix, ""),
        os.environ.get("AIM_%s_MATCHER" % prefix, ""),
        os.environ.get("AIM_%s_CMD" % prefix, ""),
    )

with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
        if ! _hook_merge_rc "$rc" "$hooks_json"; then
            return "$rc"
        fi
        if [ -f "$bak" ]; then
            info "backed up existing -> $bak"
        fi
        [ -z "$session_event" ] || info "registered $session_event -> $session_cmd"
        [ -z "$inject_event" ] || info "registered $inject_event -> $inject_cmd"
        [ -z "$block_event" ] || info "registered $block_event -> $block_cmd"
        [ -z "$guard_event" ] || info "registered $guard_event -> $guard_cmd"
    elif [ ! -e "$hooks_json" ]; then
        {
            printf '{\n  "hooks": {'
            local wrote=0
            _hook_native_print_group() {
                local ev="$1" mt="$2" cm="$3"
                [ -n "$ev" ] && [ -n "$cm" ] || return 0
                [ "$wrote" -eq 0 ] || printf ','
                printf '\n    "%s": [\n      { ' "$ev"
                [ -z "$mt" ] || printf '"matcher": "%s", ' "$mt"
                printf '"hooks": [ { "type": "command", "command": "%s" } ] }\n    ]' "$cm"
                wrote=1
            }
            _hook_native_print_group "$session_event" "$session_matcher" "$session_cmd"
            _hook_native_print_group "$inject_event" "$inject_matcher" "$inject_cmd"
            _hook_native_print_group "$block_event" "$block_matcher" "$block_cmd"
            _hook_native_print_group "$guard_event" "$guard_matcher" "$guard_cmd"
            printf '\n  }\n}\n'
        } > "$hooks_json"
        info "wrote $hooks_json (no python3 — new file)"
    else
        info "python3 absent and $hooks_json exists — merge native hook entries by hand (see notes)"
    fi
}

_hook_register_codex_json() {
    _hook_register_native_json "$1"
}

# driver_notes — manual steps the installer cannot fully do (global-rules
# placement, trust prompts). Printed at the end.
driver_notes() {
    local hooks_json; hooks_json="$(manifest_get "$MANIFEST" hooks_json)"
    if [ -n "$hooks_json" ]; then
        local cd; cd="$(dirname "$hooks_json")"
        cat <<EOF
  1. Alias the launch wrapper so every agy session resolves the active project:
       alias agy='$MEMORY_DIR/harnesses/$HARNESS/scripts/agy.sh'
  2. Static workflow-rules base (the ~/.claude/CLAUDE.md analogue) is a hand-owned
     $cd/AGENTS.md — create/edit it yourself; the memory system never writes it.
     Per-project memory is injected live by the PreInvocation hook now registered
     in $hooks_json. Verify: run 'agy' in a pinned repo and check it sees memory.
  3. Statusline (if wired): registered in $(manifest_get "$MANIFEST" statusline_settings).
     It shows the memory project + folder + brain/runtime state. Needs a Nerd Font in
     your terminal (or set USE_NERD_FONTS=false for emoji). Toggle in-CLI: /statusline.
EOF
        return
    fi

    local sd sj; sd="$(manifest_get "$MANIFEST" hooks_dir)"; sd="${sd%/hooks}"
    sj="$(manifest_get "$MANIFEST" settings_json)"
    [ -n "$sj" ] || sj="$sd/settings.json"
    cat <<EOF
  1. Hook entries were auto-merged into $sj. The statusline script is symlinked to
     $sd/statusline.sh, but the statusLine ENTRY is not auto-merged (optional +
     user-owned). To enable the memory-aware statusline, add to $sj:
       "statusLine": { "type": "command", "command": "\$HOME/.claude/statusline.sh", "padding": 0 }

  2. Workflow rules: review $HARNESS_DIR/CLAUDE.md, then wire it into $sd/CLAUDE.md.
     PREFERRED — a thin shim that @-imports the versioned copy, so it never drifts and
     you keep machine-specific lines (e.g. @RTK.md):
       # in $sd/CLAUDE.md
       @$HARNESS_DIR/CLAUDE.md
     Or symlink it if you have no machine-specific additions:
       ln -s "$HARNESS_DIR/CLAUDE.md" "$sd/CLAUDE.md"
     Do NOT copy/merge the body inline — a merged copy freezes and drifts from the repo
     every time the doctrine changes.
EOF
}
