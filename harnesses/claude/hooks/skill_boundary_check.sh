#!/usr/bin/env bash
# Stop hook — run the skill write-boundary check (subsystem #11) for any
# target-read-only skill armed this session by skill_boundary_marker.sh.
#
# For each marker: compare the memory repo against the pre-work baseline
# (scope `others-only` — the orchestrator legitimately co-edits memory.md /
# todo.md / plans in the same turn, so only writes into *other* skills' dirs
# count there) and, if the skill registered a target (skills/<skill>/.boundary-target
# = "<repo-path>\n<baseline-file>"), assert that target repo is untouched.
#
# Detective + harness-agnostic; layers under the codex execpolicy. On a
# violation it exits 2 so the message is surfaced back to the session; markers
# are cleared first so the warning fires once, not in a loop.
#
# Marker lifecycle (v1): armed at skill invocation, checked + CLEARED at this
# Stop = single-turn coverage. A read-only skill that spans a user question
# (multi-turn) is only checked for its first turn — known limitation; a v2 can
# move to per-turn baselines (UserPromptSubmit) + persistent markers. Subagent
# fan-out (renovate-manager) is covered by the parent Stop, not SubagentStop yet.
#
# Stdin: Stop JSON (session_id). Targets bash 3.2.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/memory_common.sh"
# memory_common.sh enables `set -e`; this hook inspects the engine's non-zero
# exit codes itself (1 = violation, 2 = setup), so errexit must be off here.
set +e

INPUT=$(cat)
SESSION_ID=$(json_field "$INPUT" "session_id")
[ -n "$SESSION_ID" ] || exit 0
case "$SESSION_ID" in *[!A-Za-z0-9._-]*) exit 0 ;; esac

MDIR="$STATE_DIR/skill-boundary/$SESSION_ID"
[ -d "$MDIR" ] || exit 0

SBC="$MEMORY_DIR/scripts/skill-boundary-check.sh"
[ -x "$SBC" ] || SBC="bash $MEMORY_DIR/scripts/skill-boundary-check.sh"

violations=""
setup_warn=""
for marker in "$MDIR"/*.marker; do
    [ -e "$marker" ] || continue
    skill=$(cat "$marker" 2>/dev/null)
    membase="$MDIR/$skill.mem-base"
    # -s (not -f): a 0-byte baseline is a failed snapshot, not a usable one.
    [ -n "$skill" ] && [ -s "$membase" ] || { rm -f "$marker" "$membase"; continue; }

    set -- check --skill "$skill" --tier target-read-only \
        --memory "$MEMORY_DIR" --memory-baseline "$membase" --memory-scope others-only

    # Optional target half: the skill drops <skill-dir>/.boundary-target with the
    # resolved target repo path (line 1) + a baseline snapshot file (line 2). Resolve
    # the skill dir across all roots (it may be local/remote, not just skills/).
    sdir="$(skill_dir_for "$skill" 2>/dev/null)"
    tgtfile="${sdir:-$MEMORY_DIR/skills/$skill}/.boundary-target"
    if [ -f "$tgtfile" ]; then
        tpath=$(sed -n '1p' "$tgtfile" 2>/dev/null)
        tbase=$(sed -n '2p' "$tgtfile" 2>/dev/null)
        if [ -n "$tpath" ] && [ -n "$tbase" ] && [ -f "$tbase" ]; then
            set -- "$@" --target "$tpath" --target-baseline "$tbase"
        fi
    fi

    # Engine exit: 0 clean, 1 violation, 2 setup error (e.g. bad baseline).
    # Only 1 is a real boundary breach worth blocking on; 2 is a config problem
    # to surface without blocking the turn.
    out=$($SBC "$@" 2>&1); rc=$?
    case "$rc" in
        0) : ;;
        1) violations="$violations
$out" ;;
        *) setup_warn="$setup_warn
$out" ;;
    esac
    rm -f "$marker" "$membase"
done
rmdir "$MDIR" 2>/dev/null || true

if [ -n "$violations" ]; then
    printf 'skill write-boundary violation(s) — a target-read-only skill modified a protected path:%s\n' "$violations" >&2
    exit 2
fi
if [ -n "$setup_warn" ]; then
    printf 'skill-boundary-check: skipped (setup issue, not a violation):%s\n' "$setup_warn" >&2
fi
exit 0
