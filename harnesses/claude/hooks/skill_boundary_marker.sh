#!/usr/bin/env bash
# PostToolUse hook (matcher: Skill) — arm the boundary check for a read-only
# skill (subsystem #11). When a target-read-only skill is invoked, record a
# per-session marker plus a memory-repo baseline snapshot taken *before* the
# skill does its work. The Stop hook (skill_boundary_check.sh) checks against
# this baseline at turn end. No-op for target-write skills or non-Skill tools.
#
# Stdin: PostToolUse JSON (session_id, tool_name, tool_input). Targets bash 3.2.
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/memory_common.sh"

INPUT=$(cat)
TOOL=$(json_field "$INPUT" "tool_name")
[ "$TOOL" = "Skill" ] || exit 0

SESSION_ID=$(json_field "$INPUT" "session_id")
[ -n "$SESSION_ID" ] || exit 0
# Reject anything that isn't a plain id before it reaches a filesystem path.
case "$SESSION_ID" in *[!A-Za-z0-9._-]*) exit 0 ;; esac

# Skill name lives in tool_input (.skill, or .name). Parse the nested object.
SKILL=$(printf '%s' "$INPUT" | python3 -c "import json,sys
try:
    ti = json.load(sys.stdin).get('tool_input', {}) or {}
    print(ti.get('skill') or ti.get('name') or '')
except Exception:
    print('')" 2>/dev/null || echo "")
[ -n "$SKILL" ] || exit 0
# Reject path-traversal / odd skill names before building a filesystem path.
case "$SKILL" in *[!A-Za-z0-9._-]*) exit 0 ;; esac

# Resolve across ALL skill roots (authored / remote cache) — a read-only skill in
# .skill-cache/ must still have its tier read and armed.
SKILL_DIR="$(skill_dir_for "$SKILL")" || exit 0
SKILL_MD="$SKILL_DIR/SKILL.md"
[ -f "$SKILL_MD" ] || exit 0

# Read metadata.tier (nested under metadata:). Only read-only skills are armed.
TIER=$(awk '
    NR==1 && /^---[[:space:]]*$/ { f=1; next }
    f && /^---[[:space:]]*$/ { exit }
    f && /^metadata:[[:space:]]*$/ { m=1; next }
    f && m && /^  tier:[[:space:]]*/ { v=$0; sub(/^  tier:[[:space:]]*/,"",v); sub(/[[:space:]]+$/,"",v); print v; exit }
    f && /^[^[:space:]]/ { m=0 }
' "$SKILL_MD")
[ "$TIER" = "target-read-only" ] || exit 0

SBC="$MEMORY_DIR/scripts/skill-boundary-check.sh"
[ -x "$SBC" ] || SBC="bash $MEMORY_DIR/scripts/skill-boundary-check.sh"

MDIR="$STATE_DIR/skill-boundary/$SESSION_ID"
mkdir -p "$MDIR"
tmp="$MDIR/$SKILL.mem-base.tmp"
# Snapshot to a temp first; only arm (write the marker + baseline) if the
# snapshot actually produced content. Never arm with a 0-byte baseline — an
# empty baseline would make the Stop check flag everything.
if $SBC snapshot --repo "$MEMORY_DIR" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
    mv "$tmp" "$MDIR/$SKILL.mem-base"
    printf '%s\n' "$SKILL" > "$MDIR/$SKILL.marker"
else
    rm -f "$tmp"
fi

exit 0
