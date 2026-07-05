#!/usr/bin/env bash
# drivers/file.sh — install driver for the `file` archetype (materialize a
# markdown context file the harness auto-reads at launch; Codex AGENTS.md is the
# reference). Sourced by install.sh, which provides HARNESS, HARNESS_DIR,
# MANIFEST and the helpers step/info/link plus manifest_get.
#
# There is nothing to symlink: the context file is REBUILT on each launch by the
# harness's wrapper (refresh=launch — e.g. harnesses/codex/scripts/codex-mem.sh
# rebuilds ~/.codex/AGENTS.md then exec's codex). The driver just prepares the
# target directory and reports the mechanism, so a fresh machine is ready for the
# first wrapped launch.

driver_install() {
    local ctx refresh
    ctx="$(manifest_get "$MANIFEST" context_target)"
    refresh="$(manifest_get "$MANIFEST" refresh)"

    step "Context target -> $ctx"
    mkdir -p "$(dirname "$ctx")"
    if [ "$refresh" = launch ]; then
        info "file archetype: '$ctx' is rebuilt on each launch by the wrapper in"
        info "$HARNESS_DIR/scripts/ (refresh=launch). No symlink placed; nothing to relink."
    else
        info "file archetype: '$ctx' refreshed in-band (refresh=$refresh)."
    fi
}

driver_notes() {
    local ctx; ctx="$(manifest_get "$MANIFEST" context_target)"
    cat <<EOF
  1. Launch this harness through its wrapper so $ctx is rebuilt from memory
     each session (e.g. alias it: see docs/harnesses/$HARNESS.md).
  2. A local overlay (e.g. ~/.codex/AGENTS.local.md) is never overwritten —
     put permanent per-harness instructions there.
EOF
}
