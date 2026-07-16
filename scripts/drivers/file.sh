#!/usr/bin/env bash
# drivers/file.sh — install driver for the `file` archetype (a markdown context
# file the harness auto-reads at launch; Codex AGENTS.md is the reference).
# Sourced by install.sh, which provides HARNESS, HARNESS_DIR, MANIFEST and the
# helpers step/info/link plus manifest_get.
#
# There is nothing to symlink. Two refresh models:
#   refresh=launch — the context file is REBUILT on each launch by the harness's
#     wrapper (e.g. an early Codex build path). Nothing to relink.
#   refresh=hook   — the context file is a HAND-OWNED static base the memory system
#     never writes; the dynamic memory tree injects live via native hooks (Codex
#     today, mirroring Antigravity). The driver just prepares the target directory.

driver_install() {
    local ctx refresh
    ctx="$(manifest_get "$MANIFEST" context_target)"
    refresh="$(manifest_get "$MANIFEST" refresh)"

    step "Context target -> $ctx"
    mkdir -p "$(dirname "$ctx")"
    case "$refresh" in
        launch)
            info "file archetype: '$ctx' is rebuilt on each launch by the wrapper in"
            info "$HARNESS_DIR/scripts/ (refresh=launch). No symlink placed; nothing to relink."
            ;;
        hook)
            info "file archetype: '$ctx' is a hand-owned static base (never written by"
            info "the memory system); the memory tree injects live via native hooks"
            info "(refresh=hook). No symlink placed; nothing to relink."
            ;;
        *)
            info "file archetype: '$ctx' refreshed in-band (refresh=$refresh)."
            ;;
    esac
}

driver_notes() {
    local ctx refresh hooks_json
    ctx="$(manifest_get "$MANIFEST" context_target)"
    refresh="$(manifest_get "$MANIFEST" refresh)"
    hooks_json="$(manifest_get "$MANIFEST" hooks_json)"
    if [ "$refresh" = hook ]; then
        cat <<EOF
  1. $ctx is a hand-owned static base (workflow rules + personal overlay).
     The memory system never writes it; the memory tree injects live via the
     native hooks below, so a plain launch gets full memory with no wrapper.
  2. Put permanent per-harness instructions directly in $ctx — it is yours to edit.
EOF
    else
        cat <<EOF
  1. Launch this harness through its wrapper so $ctx is rebuilt from memory
     each session (e.g. alias it: see docs/harnesses/$HARNESS.md).
  2. A local overlay (e.g. ~/.codex/AGENTS.local.md) is never overwritten —
     put permanent per-harness instructions there.
EOF
    fi
    if [ -n "$hooks_json" ]; then
        cat <<EOF
  3. Native hooks: Run /hooks in codex once and trust the ai-memory hooks.
     Headless executor runs bypass trust automatically. Codex will ask again if
     a hook command changes.
EOF
    fi
}
