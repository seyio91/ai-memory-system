#!/usr/bin/env bash
# scripts/hooks/lib.sh resolves MEMORY_DIR from its own (symlinked) location and
# then lets config.local.sh override it — the mechanism that makes the install dir
# the memory dir, and a re-run after a move repoint it.
#
# Each case stages a fake tree <root>/scripts/hooks/lib.sh (a real copy of the
# shared hook lib) and sources it through a symlink in a *separate* dir. Resolution
# must land on <root> — the lib self-locates its repo root two levels up.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
LIB="$REPO/scripts/hooks/lib.sh"

stage_tree() {
    # stage_tree <root> — real hook lib copy at <root>/scripts/hooks + a symlink
    # to it under <root>/link, plus the shared engine it sources, mirroring a real
    # install. Prints the symlink path to source.
    local root="$1"
    mkdir -p "$root/scripts/hooks" "$root/link" "$root/scripts/formatters"
    cp "$LIB" "$root/scripts/hooks/lib.sh"
    cp "$REPO/scripts/_lib.sh" "$root/scripts/_lib.sh"
    cp "$REPO/scripts/content-core.sh" "$root/scripts/content-core.sh"
    cp "$REPO/scripts/formatters/xml.sh" "$root/scripts/formatters/xml.sh"
    cp "$REPO/scripts/formatters/md.sh" "$root/scripts/formatters/md.sh"
    ln -s "$root/scripts/hooks/lib.sh" "$root/link/lib.sh"
    printf '%s/link/lib.sh' "$root"
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
