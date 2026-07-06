#!/usr/bin/env bash
# drivers/hook.sh — install driver for the `hook` archetype (in-band, live
# per-prompt injection). Two registration styles, chosen by the manifest:
#   - hooks_dir  (Claude): symlink the harness's hook scripts into a runtime dir;
#                 registration into settings.json is a manual note.
#   - hooks_json (Antigravity): register a namespaced PreInvocation entry that runs
#                 hook_script into the harness's JSON hooks file.
# Sourced by install.sh, which provides HARNESS, HARNESS_DIR, MANIFEST, MEMORY_DIR
# and the helpers step/info/link plus manifest_get. Exposes driver_install +
# driver_notes.

# driver_install — dispatch on which registration style the manifest declares.
driver_install() {
    local hooks_dir hooks_json
    hooks_dir="$(manifest_get "$MANIFEST" hooks_dir)"
    hooks_json="$(manifest_get "$MANIFEST" hooks_json)"

    if [ -n "$hooks_dir" ]; then
        _hook_install_scripts "$hooks_dir"
    elif [ -n "$hooks_json" ]; then
        _hook_register_json "$hooks_json"
    else
        info "hook archetype but neither hooks_dir nor hooks_json in manifest — nothing wired"
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

# _hook_register_json <hooks_json> — Antigravity style: register a namespaced
# PreInvocation entry running hook_script into the JSON hooks file. Idempotent
# merge via python3 (preserves any other hooks); if python3 is absent, write a new
# file wholesale, or (file already exists) defer to a manual merge note.
_hook_register_json() {
    local hooks_json="$1" hs cmd
    hs="$(manifest_get "$MANIFEST" hook_script)"
    hs="${hs//\$MEMORY_DIR/$MEMORY_DIR}"
    [ -n "$hs" ] || { info "hooks_json set but no hook_script in manifest — nothing to register"; return; }
    chmod +x "$hs" 2>/dev/null || true
    cmd="bash $hs"

    step "PreInvocation hook -> $hooks_json"
    mkdir -p "$(dirname "$hooks_json")"
    if command -v python3 >/dev/null 2>&1; then
        AIM_HOOKS_JSON="$hooks_json" AIM_HOOK_CMD="$cmd" python3 - <<'PY'
import json, os
path = os.environ["AIM_HOOKS_JSON"]
cmd  = os.environ["AIM_HOOK_CMD"]
try:
    with open(path) as f:
        data = json.load(f)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
data["ai-memory-inject"] = {"PreInvocation": [{"type": "command", "command": cmd}]}
with open(path, "w") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
        info "registered PreInvocation 'ai-memory-inject' -> $cmd"
    elif [ ! -e "$hooks_json" ]; then
        printf '{\n  "ai-memory-inject": {\n    "PreInvocation": [\n      { "type": "command", "command": "%s" }\n    ]\n  }\n}\n' "$cmd" > "$hooks_json"
        info "wrote $hooks_json (no python3 — new file)"
    else
        info "python3 absent and $hooks_json exists — merge the 'ai-memory-inject' entry by hand (see notes)"
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
EOF
        return
    fi

    local sd; sd="$(manifest_get "$MANIFEST" hooks_dir)"; sd="${sd%/hooks}"
    cat <<EOF
  1. Settings must be registered in $sd/settings.json. Merge the hook
     entries and the statusLine from $HARNESS_DIR/settings.hooks.json into it.

  2. Workflow rules: review $HARNESS_DIR/CLAUDE.md, then either symlink or merge it:
       ln -s "$HARNESS_DIR/CLAUDE.md" "$sd/CLAUDE.md"   # if you have none
     (If you already have one, merge by hand.)
EOF
}
