#!/usr/bin/env bash
# Internal helper for check-memory-size.sh --payload. Renders ONE session
# payload exactly the way session_start_memory.sh composes it (render_full +
# initiative-alert insertion) for a given project/format/working-file
# combination, then exits. Deliberately a separate PROCESS, never sourced:
# check-memory-size.sh shells out to this so a rendering crash (missing file,
# bad format, a wedged initiative-status.sh) fails open for that one harness
# instead of taking the whole checker down.
#
# Inputs, all via environment (set by the caller):
#   MEMORY_DIR                    the tree to render FROM (the project being checked)
#   AI_MEMORY_HOOK_FORMAT         xml | md
#   AI_MEMORY_WORKING_OVERRIDE    the one working file to include — see
#                                 content-core.sh's `working)` case
#   AI_MEMORY_PRECOMPUTED_ALERT_SET / AI_MEMORY_PRECOMPUTED_ALERT
#                                 when SET is non-empty, skip the per-call
#                                 initiative-status.sh scan and use ALERT
#                                 verbatim (see lib.sh's render_initiative_alert)
#
# Usage: render-session-payload.sh <project>
#        render-session-payload.sh --alert-lines <project>
# Default mode prints the composed payload to stdout; exit 0 on an
# empty/absent project, 2 on a usage error or an unsupported
# AI_MEMORY_HOOK_FORMAT.
#
# --alert-lines mode prints ONLY the raw, format-neutral alert lines (the
# expensive half of render_initiative_alert) followed by a sentinel marker,
# so a caller checking several harness/working combinations for the same
# project can pay the initiative-status.sh scan cost once and reuse the
# result via AI_MEMORY_PRECOMPUTED_ALERT. The sentinel is a non-newline
# suffix so command-substitution's trailing-newline stripping never touches
# the lines themselves; the caller strips the marker back off. Always exits
# 0 — a crashed scan degrades to "no alert", same fail-open behavior as the
# inline path.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/lib.sh"

ALERT_LINES_MARKER=$'\x01''AI_MEMORY_ALERT_END'$'\x01'

if [ "${1:-}" = "--alert-lines" ]; then
    [ "$#" -eq 2 ] || { printf 'usage: %s --alert-lines <project>\n' "$(basename "$0")" >&2; exit 2; }
    project="$2"
    [ -n "$project" ] || exit 0
    _compute_initiative_alert_lines "$project" || true
    printf '%s%s' "$_IA_LINES" "$ALERT_LINES_MARKER"
    exit 0
fi

[ "$#" -eq 1 ] || { printf 'usage: %s <project>\n' "$(basename "$0")" >&2; exit 2; }
project="$1"

OUTPUT="$(render_full "$project")"
[ -z "$OUTPUT" ] && exit 0

# Mirrors session_start_memory.sh's alert insertion verbatim (not factored into
# a shared function — out of scope for this phase; see the plan).
ALERT="$(render_initiative_alert "$project" || true)"
if [ -n "$ALERT" ]; then
    case "${AI_MEMORY_HOOK_FORMAT:-xml}" in
        xml)
            case "$OUTPUT" in
                *'<memory:working>'*) OUTPUT="${OUTPUT/<memory:working>/$ALERT$'\n'<memory:working>}" ;;
                *) OUTPUT="$OUTPUT"$'\n'"$ALERT" ;;
            esac
            ;;
        md)
            case "$OUTPUT" in
                *'# === WORKING MEMORY ==='*) OUTPUT="${OUTPUT/# === WORKING MEMORY ===/$ALERT$'\n\n'# === WORKING MEMORY ===}" ;;
                *) OUTPUT="$OUTPUT"$'\n'"$ALERT" ;;
            esac
            ;;
        *)   OUTPUT="$OUTPUT"$'\n'"$ALERT" ;;
    esac
fi

printf '%s' "$OUTPUT"
