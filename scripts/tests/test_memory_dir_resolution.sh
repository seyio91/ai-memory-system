#!/usr/bin/env bash
# memory_common.sh resolves MEMORY_DIR from its own (symlinked) location and then
# lets config.local.sh override it — the mechanism that makes the install dir the
# memory dir, and a re-run after a move repoint it.
#
# Each case stages a fake tree <root>/claude/hooks/memory_common.sh (a real copy
# of the hook) and sources it through a symlink in a *separate* dir, mimicking the
# ~/.claude/hooks symlink install.sh creates. Resolution must land on <root>.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
COMMON="$REPO/claude/hooks/memory_common.sh"

stage_tree() {
    # stage_tree <root> — real hook copy at <root>/claude/hooks + a symlink to it
    # under <root>/link, plus the shared engine the hook sources (content-core +
    # xml formatter) under <root>/scripts, mirroring a real install. Prints the
    # symlink path to source.
    local root="$1"
    mkdir -p "$root/claude/hooks" "$root/link" "$root/scripts/formatters"
    cp "$COMMON" "$root/claude/hooks/memory_common.sh"
    cp "$REPO/scripts/content-core.sh" "$root/scripts/content-core.sh"
    cp "$REPO/scripts/formatters/xml.sh" "$root/scripts/formatters/xml.sh"
    ln -s "$root/claude/hooks/memory_common.sh" "$root/link/memory_common.sh"
    printf '%s/link/memory_common.sh' "$root"
}

# --- symlinked hook resolves MEMORY_DIR to the real tree root (no env, no config) ---
SB1="$(new_sandbox)"; LINK1="$(stage_tree "$SB1/root")"
got=$( unset MEMORY_DIR; . "$LINK1"; printf '%s' "$MEMORY_DIR" )
assert_eq "$SB1/root" "$got" "symlinked hook resolves MEMORY_DIR to its tree root"

# --- config.local.sh at the resolved tree overrides the bootstrap default ---
SB2="$(new_sandbox)"; LINK2="$(stage_tree "$SB2/root")"
printf 'export MEMORY_DIR="/tmp/from-config-md"\n' > "$SB2/root/config.local.sh"
got=$( unset MEMORY_DIR; . "$LINK2"; printf '%s' "$MEMORY_DIR" )
assert_eq "/tmp/from-config-md" "$got" "config.local.sh overrides resolved MEMORY_DIR"

# --- STATE_DIR derives from the final MEMORY_DIR ---
got=$( unset MEMORY_DIR; . "$LINK2"; printf '%s' "$STATE_DIR" )
assert_eq "/tmp/from-config-md/.sessions" "$got" "STATE_DIR follows config-overridden MEMORY_DIR"

rm -rf "$SB1" "$SB2"
finish
