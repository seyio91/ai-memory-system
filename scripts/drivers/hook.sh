#!/usr/bin/env bash
# drivers/hook.sh — install driver for the `hook` archetype (in-band, live
# per-prompt injection). Two registration styles, chosen by the manifest:
#   - hooks_dir  (Claude): symlink the harness's hook scripts into a runtime dir;
#                 registration into settings.json is a manual note.
#   - hooks_json (Antigravity): register a namespaced PreInvocation entry that runs
#                 hook_script into the harness's JSON hooks file.
# Codex is a sanctioned hybrid: file archetype plus a Codex-shaped hooks_json
# registration branch called directly by install.sh after the file driver.
# Sourced by install.sh, which provides HARNESS, HARNESS_DIR, MANIFEST, MEMORY_DIR
# and the helpers step/info/link plus manifest_get. Exposes driver_install +
# driver_notes.

# driver_install — dispatch on which registration style the manifest declares.
driver_install() {
    local hooks_dir hooks_json sl_settings
    hooks_dir="$(manifest_get "$MANIFEST" hooks_dir)"
    hooks_json="$(manifest_get "$MANIFEST" hooks_json)"

    if [ -n "$hooks_dir" ]; then
        _hook_install_scripts "$hooks_dir"
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

# _hook_install_scripts <hooks_dir> — Claude style: symlink the harness's hook
# scripts (and statusline, if any) into the runtime dirs named by the manifest.
_hook_install_scripts() {
    local hooks_dir="$1" statusline h
    step "Hooks -> $hooks_dir"
    mkdir -p "$hooks_dir"
    for h in "$HARNESS_DIR"/hooks/*.sh; do
        [ -e "$h" ] || continue
        chmod +x "$h"
        link "$h" "$hooks_dir/$(basename "$h")"
    done

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

# _hook_register_codex_json <hooks_json> — Codex hybrid style: register shared
# Claude/Codex-contract hook scripts into Codex's top-level {"hooks": ...}
# schema. This is intentionally separate from _hook_register_json: Antigravity's
# hooks.json shape is namespaced and not compatible with Codex's event arrays.
_hook_register_codex_json() {
    local hooks_json="$1" hs gs fmt role spec event matcher
    local inject_event="" guard_event="" guard_matcher="" hook_count=0
    local inject_cmd="" guard_cmd=""
    hs="$(manifest_get "$MANIFEST" hook_script)"; hs="${hs//\$MEMORY_DIR/$MEMORY_DIR}"
    gs="$(manifest_get "$MANIFEST" guard_script)"; gs="${gs//\$MEMORY_DIR/$MEMORY_DIR}"
    fmt="$(manifest_get "$MANIFEST" format)"
    [ -n "$fmt" ] || fmt=md
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
                hook_count=$((hook_count + 1))
                ;;
            infra_guard)
                [ -n "$gs" ] || continue
                guard_event="$event"
                guard_matcher="$matcher"
                hook_count=$((hook_count + 1))
                ;;
            *)
                info "hook role '$role' has no codex hooks_json script association — skipping"
                ;;
        esac
    done < <(manifest_hooks "$MANIFEST")

    if [ "$hook_count" -eq 0 ]; then
        info "hooks_json set but [hooks] has no registerable Codex roles — nothing to register"
        return
    fi

    if [ -n "$inject_event" ]; then
        inject_cmd="env MEMORY_DIR=$MEMORY_DIR AI_MEMORY_HOOK_FORMAT=$fmt AI_MEMORY_HOOK_EVENT=$inject_event bash $hs"
    fi
    if [ -n "$guard_event" ]; then
        guard_cmd="env MEMORY_DIR=$MEMORY_DIR bash $gs"
    fi

    step "Codex hooks -> $hooks_json"
    mkdir -p "$(dirname "$hooks_json")"
    if command -v python3 >/dev/null 2>&1; then
        local rc=0 bak
        bak="$hooks_json.bak-$(_hook_ts)"
        AIM_HOOKS_JSON="$hooks_json" AIM_INJECT_CMD="$inject_cmd" AIM_GUARD_CMD="$guard_cmd" \
            AIM_INJECT_EVENT="$inject_event" AIM_GUARD_EVENT="$guard_event" \
            AIM_GUARD_MATCHER="$guard_matcher" AIM_BAK="$bak" python3 - <<'PY' || rc=$?
import json, os, shutil, sys
path = os.environ["AIM_HOOKS_JSON"]
inject = os.environ.get("AIM_INJECT_CMD", "")
guard = os.environ.get("AIM_GUARD_CMD", "")
inject_event = os.environ.get("AIM_INJECT_EVENT", "")
guard_event = os.environ.get("AIM_GUARD_EVENT", "")
guard_matcher = os.environ.get("AIM_GUARD_MATCHER", "")
bak = os.environ["AIM_BAK"]
ours = ("scripts/hooks/inject.sh", "scripts/hooks/guard.sh")
data = {}
if os.path.exists(path):
    with open(path) as f:
        raw = f.read()
    # Empty/whitespace-only is equivalent to an absent hooks file.
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

def clean_event(event):
    if not event:
        return
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
            entries = [
                h for h in entries
                if not (isinstance(h, dict) and is_ours(str(h.get("command", ""))))
            ]
            if entries:
                new_group = dict(group)
                new_group["hooks"] = entries
                cleaned.append(new_group)
            elif "hooks" not in group:
                cleaned.append(group)
        else:
            cmd = str(group.get("command", ""))
            if not is_ours(cmd):
                cleaned.append(group)
    hooks[event] = cleaned

clean_event(inject_event)
clean_event(guard_event)

if inject_event and inject:
    hooks.setdefault(inject_event, []).append({
        "hooks": [{"type": "command", "command": inject}]
    })
if guard_event and guard:
    hooks.setdefault(guard_event, []).append({
        "matcher": guard_matcher,
        "hooks": [{"type": "command", "command": guard}]
    })

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
        if [ -n "$inject_event" ]; then
            info "registered Codex $inject_event -> $inject_cmd"
        fi
        if [ -n "$guard_event" ]; then
            info "registered Codex $guard_event -> $guard_cmd"
        fi
    elif [ ! -e "$hooks_json" ]; then
        {
            printf '{\n  "hooks": {'
            if [ -n "$inject_event" ]; then
                printf '\n    "%s": [\n      { "hooks": [ { "type": "command", "command": "%s" } ] }\n    ]' "$inject_event" "$inject_cmd"
            fi
            if [ -n "$guard_event" ]; then
                [ -n "$inject_event" ] && printf ','
                printf '\n    "%s": [\n      { "matcher": "%s", "hooks": [ { "type": "command", "command": "%s" } ] }\n    ]' "$guard_event" "$guard_matcher" "$guard_cmd"
            fi
            printf '\n  }\n}\n'
        } > "$hooks_json"
        info "wrote $hooks_json (no python3 — new file)"
    else
        info "python3 absent and $hooks_json exists — merge the Codex hooks.UserPromptSubmit/PreToolUse entries by hand (see notes)"
    fi
}

# driver_notes — manual steps the installer cannot fully do (settings/JSON
# registration it won't clobber, global-rules placement). Printed at the end.
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

    local sd; sd="$(manifest_get "$MANIFEST" hooks_dir)"; sd="${sd%/hooks}"
    cat <<EOF
  1. Settings must be registered in $sd/settings.json. Merge the hook
     entries and the statusLine from $HARNESS_DIR/settings.hooks.json into it.

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
