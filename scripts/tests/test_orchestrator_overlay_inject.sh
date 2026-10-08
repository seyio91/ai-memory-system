#!/usr/bin/env bash
# orchestrator-local injection: the overlay/legacy resolution content-core.sh
# performs for the `orchestrator-local` kind (Phase 2 of
# projects/ai-memory/plans/dedupe-always-injected-base.md — Design -> Injection).
#
# Resolution under test:
#   overlay (orchestrator.local.md) present, non-blank -> injected, no deprecation
#   overlay absent, legacy root orchestrator.md present -> injected AS
#     orchestrator-local, breadcrumb carries a one-line deprecation notice
#   overlay present but empty/whitespace-only -> falls through to a non-blank
#     legacy root orchestrator.md (same as "overlay absent" above), else NO
#     block; but this fallback is skipped entirely — no block, regardless of
#     the legacy file's content — when orchestrator.md.pre-1.6.0 exists, since
#     that backup proves the instance already migrated and a root file found
#     alongside it is a stale re-seed, not un-migrated doctrine
#   both overlay and legacy present -> overlay content wins, legacy content
#     absent entirely
#   neither present -> NO block, no breadcrumb line
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"

seed_min_tree "$MEM"
mkdir -p "$MEM/doctrine" "$MEM/projects/p1"
printf '# Orchestrator\n\nCORE-MARKER\n' > "$MEM/doctrine/orchestrator.md"
cat > "$MEM/projects/p1/memory.md" <<'EOF'
---
topic: p1
scope: project
summary: p1 summary
---
# Project: p1
EOF

. "$REPO/scripts/hooks/lib.sh"

OVERLAY="$MEM/orchestrator.local.md"
LEGACY="$MEM/orchestrator.md"

xml_full()  { AI_MEMORY_HOOK_FORMAT=xml render_full p1; }
md_full()   { AI_MEMORY_HOOK_FORMAT=md  render_full p1; }
xml_crumb() { AI_MEMORY_HOOK_FORMAT=xml render_breadcrumb p1 "$MEM"; }
md_crumb()  { AI_MEMORY_HOOK_FORMAT=md  render_breadcrumb p1 "$MEM"; }

# --- (b) neither overlay nor legacy present -> no block, no breadcrumb line ---
rm -f "$OVERLAY" "$LEGACY"

x="$(xml_full)"; m="$(md_full)"
assert_not_contains "$x" "<memory:orchestrator-local>" "(b) xml full: no orchestrator-local block when both absent"
assert_not_contains "$m" "# === ORCHESTRATOR (LOCAL) ===" "(b) md full: no orchestrator-local heading when both absent"
assert_contains "$x" "<memory:orchestrator>" "(b) xml full: core orchestrator block still present"

xc="$(xml_crumb)"; mc="$(md_crumb)"
assert_not_contains "$xc" "orchestrator-local:" "(b) xml breadcrumb: no orchestrator-local line when both absent"
assert_not_contains "$mc" "orchestrator-local:" "(b) md breadcrumb: no orchestrator-local line when both absent"

# --- (a) overlay present, non-blank -> both blocks, orchestrator then orchestrator-local ---
printf '# Local\n\nOVERLAY-MARKER\n' > "$OVERLAY"

x="$(xml_full)"
case "$x" in
    *"<memory:orchestrator>"*"CORE-MARKER"*"</memory:orchestrator>"*"<memory:orchestrator-local>"*"OVERLAY-MARKER"*"</memory:orchestrator-local>"*)
        _ok "(a) xml full: orchestrator then orchestrator-local, overlay content present" ;;
    *) _bad "(a) xml full: orchestrator then orchestrator-local, overlay content present" ;;
esac

m="$(md_full)"
case "$m" in
    *"# === ORCHESTRATOR ==="*"CORE-MARKER"*"# === ORCHESTRATOR (LOCAL) ==="*"OVERLAY-MARKER"*)
        _ok "(a) md full: orchestrator then orchestrator-local, overlay content present" ;;
    *) _bad "(a) md full: orchestrator then orchestrator-local, overlay content present" ;;
esac

xc="$(xml_crumb)"; mc="$(md_crumb)"
assert_contains "$xc" "orchestrator: $MEM/doctrine/orchestrator.md" "(a) xml breadcrumb: core path listed"
assert_contains "$xc" "orchestrator-local: $OVERLAY" "(a) xml breadcrumb: overlay path listed"
assert_not_contains "$xc" "legacy orchestrator.md" "(a) xml breadcrumb: no deprecation notice for a real overlay"
assert_contains "$mc" "orchestrator: $MEM/doctrine/orchestrator.md" "(a) md breadcrumb: core path listed"
assert_contains "$mc" "orchestrator-local: $OVERLAY" "(a) md breadcrumb: overlay path listed"

# --- (c) overlay absent, legacy root orchestrator.md present -> injected as
#     orchestrator-local, breadcrumb carries the deprecation notice ---
rm -f "$OVERLAY"
printf '# Legacy\n\nLEGACY-MARKER\n' > "$LEGACY"

x="$(xml_full)"
assert_contains "$x" "<memory:orchestrator-local>" "(c) xml full: legacy root injected as orchestrator-local"
assert_contains "$x" "LEGACY-MARKER" "(c) xml full: legacy content present"

xc="$(xml_crumb)"
assert_contains "$xc" "orchestrator-local: $LEGACY (legacy orchestrator.md — move personal rules into orchestrator.local.md, then delete this file; /sync-system to 1.6.0+ does it for you)" \
    "(c) xml breadcrumb: deprecation notice present with legacy path"
mc="$(md_crumb)"
assert_contains "$mc" "orchestrator-local: $LEGACY (legacy orchestrator.md — move personal rules into orchestrator.local.md, then delete this file; /sync-system to 1.6.0+ does it for you)" \
    "(c) md breadcrumb: deprecation notice present with legacy path"

# --- (d) both present -> overlay wins, legacy content absent entirely ---
printf '# Local\n\nOVERLAY-MARKER-D\n' > "$OVERLAY"
# $LEGACY (LEGACY-MARKER) still present from the previous case.

x="$(xml_full)"
assert_contains "$x" "OVERLAY-MARKER-D" "(d) xml full: overlay content present when both exist"
assert_not_contains "$x" "LEGACY-MARKER" "(d) xml full: legacy content absent when overlay also exists"
cnt="$(printf '%s' "$x" | grep -o '<memory:orchestrator-local>' | wc -l | tr -d ' ')"
assert_eq "1" "$cnt" "(d) xml full: exactly one orchestrator-local block when both exist"

xc="$(xml_crumb)"
assert_contains "$xc" "orchestrator-local: $OVERLAY" "(d) xml breadcrumb: overlay path listed, not legacy"
assert_not_contains "$xc" "orchestrator-local: $LEGACY" "(d) xml breadcrumb: legacy path absent when overlay wins"

# --- (e) blank overlay counts as absent: it falls through to a non-blank legacy
# file (an install that seeds an empty overlay without migrating must not drop
# the user's edited doctrine), and emits nothing when there is no legacy file ---
: > "$OVERLAY"
x="$(xml_full)"
assert_contains "$x" "LEGACY-MARKER" "(e) xml full: empty overlay falls through to legacy"
xc="$(xml_crumb)"
assert_contains "$xc" "orchestrator-local: $LEGACY" "(e) xml breadcrumb: legacy path listed behind an empty overlay"
assert_contains "$xc" "legacy orchestrator.md" "(e) xml breadcrumb: deprecation notice behind an empty overlay"

printf '   \n\t\n' > "$OVERLAY"
x="$(xml_full)"
assert_contains "$x" "LEGACY-MARKER" "(e) xml full: whitespace-only overlay falls through to legacy"

mv "$LEGACY" "$LEGACY.aside"
x="$(xml_full)"
assert_not_contains "$x" "<memory:orchestrator-local>" "(e) xml full: blank overlay and no legacy emits no block"
xc="$(xml_crumb)"
assert_not_contains "$xc" "orchestrator-local:" "(e) xml breadcrumb: no line for a blank overlay and no legacy"

: > "$LEGACY"
x="$(xml_full)"
assert_not_contains "$x" "<memory:orchestrator-local>" "(e) xml full: blank overlay and blank legacy emits no block"
rm -f "$LEGACY"; mv "$LEGACY.aside" "$LEGACY"

# --- (f) blank overlay + non-blank legacy root file + orchestrator.md.pre-1.6.0
# backup present -> the backup proves this instance already migrated, so the
# legacy root file is a stale re-seed, not un-migrated doctrine: NO block and no
# orchestrator-local line, but the breadcrumb names it as ignored so a root file
# edited after a rollback never stops applying silently ---
# $OVERLAY is still blank (whitespace-only) and $LEGACY still carries
# LEGACY-MARKER from the setup above.
printf 'backup from a prior migration run\n' > "$MEM/orchestrator.md.pre-1.6.0"

x="$(xml_full)"
assert_not_contains "$x" "<memory:orchestrator-local>" "(f) xml full: no block when blank overlay + legacy + pre-1.6.0 backup all present"
m="$(md_full)"
assert_not_contains "$m" "# === ORCHESTRATOR (LOCAL) ===" "(f) md full: no heading when blank overlay + legacy + pre-1.6.0 backup all present"

xc="$(xml_crumb)"; mc="$(md_crumb)"
assert_not_contains "$xc" "orchestrator-local:" "(f) xml breadcrumb: no orchestrator-local line when backup exists"
assert_not_contains "$mc" "orchestrator-local:" "(f) md breadcrumb: no orchestrator-local line when backup exists"
assert_contains "$xc" "orchestrator-ignored: $LEGACY (NOT injected" "(f) xml breadcrumb: skipped root file is named, not silent"
assert_contains "$mc" "orchestrator-ignored: $LEGACY (NOT injected" "(f) md breadcrumb: skipped root file is named, not silent"
assert_not_contains "$x" "LEGACY-MARKER" "(f) xml full: ignored root file content not injected"
assert_not_contains "$m" "LEGACY-MARKER" "(f) md full: ignored root file content not injected"

rm -f "$MEM/orchestrator.md.pre-1.6.0"

finish
