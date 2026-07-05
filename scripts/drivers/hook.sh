#!/usr/bin/env bash
# drivers/hook.sh — install driver for the `hook` archetype (in-band, live
# per-prompt injection; Claude Code is the reference). Sourced by install.sh,
# which provides: HARNESS, HARNESS_DIR, MANIFEST, and the helpers step/info/link
# plus manifest_get (from manifest.sh). Exposes driver_install + driver_notes.

# driver_install — symlink the harness's hook scripts (and statusline, if any)
# into the runtime dirs named by the manifest.
driver_install() {
    local hooks_dir statusline h
    hooks_dir="$(manifest_get "$MANIFEST" hooks_dir)"

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

# driver_notes — manual steps the installer cannot do (settings registration,
# global-rules placement). Printed at the end of install.
driver_notes() {
    local sd; sd="$(manifest_get "$MANIFEST" hooks_dir)"; sd="${sd%/hooks}"
    cat <<EOF
  1. Settings must be registered in $sd/settings.json. Merge the hook
     entries and the statusLine from $HARNESS_DIR/settings.hooks.json into it.

  2. Workflow rules: review $HARNESS_DIR/CLAUDE.md, then either symlink or merge it:
       ln -s "$HARNESS_DIR/CLAUDE.md" "$sd/CLAUDE.md"   # if you have none
     (If you already have one, merge by hand.)
EOF
}
