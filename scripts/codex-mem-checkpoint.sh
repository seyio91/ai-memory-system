#!/usr/bin/env bash
set -euo pipefail

# codex-mem-checkpoint — capture a Codex session into the active project's working.md.
#
# Two modes:
#   1. Interactive (TTY, no --for-codex): appends a scaffold to working.md and opens
#      $EDITOR on the file so the human fills it in.
#   2. --for-codex (or non-TTY stdout): prints metadata + a recent-history snippet +
#      a scaffold to stdout, so the Codex model can read it and write the checkpoint
#      itself using its file-edit tool.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

CODEX_HISTORY="${CODEX_HISTORY_FILE:-$HOME/.codex/history.jsonl}"
HISTORY_LINES="${CODEX_HISTORY_LINES:-20}"

FOR_CODEX=0
if [ "${1:-}" = "--for-codex" ]; then
    FOR_CODEX=1
    shift
elif [ ! -t 1 ]; then
    FOR_CODEX=1
fi

PROJECT=$(detect_active_project)

if [ -z "$PROJECT" ]; then
    echo "codex-mem-checkpoint: no active project (no .claude/memory-project marker found walking up from $PWD)" >&2
    exit 1
fi

WORKING="$MEMORY_DIR/projects/$PROJECT/working.md"
if [ ! -f "$WORKING" ]; then
    echo "codex-mem-checkpoint: working.md not found at $WORKING" >&2
    exit 1
fi

TODAY=$(date +%Y-%m-%d)

read_recent_history() {
    if [ ! -f "$CODEX_HISTORY" ]; then
        echo "(no $CODEX_HISTORY found)"
        return
    fi
    # history.jsonl: one JSON object per line. Extract the .text field if present,
    # falling back to the whole line. Last $HISTORY_LINES entries, oldest first.
    tail -n "$HISTORY_LINES" "$CODEX_HISTORY" | awk '
        {
            line = $0
            # Try to pull "text":"..." (handles escaped quotes naively).
            if (match(line, /"text"[[:space:]]*:[[:space:]]*"/)) {
                rest = substr(line, RSTART + RLENGTH)
                # Find the closing quote not preceded by backslash.
                out = ""
                i = 1
                n = length(rest)
                while (i <= n) {
                    c = substr(rest, i, 1)
                    if (c == "\\" && i < n) { out = out substr(rest, i, 2); i += 2; continue }
                    if (c == "\"") break
                    out = out c
                    i++
                }
                print "- " out
            } else {
                print "- " line
            }
        }
    '
}

# Avoid heredocs — they require a writable /tmp for their backing file, which
# fails under restrictive sandboxes (e.g. codex --sandbox read-only).
SCAFFOLD="### ${TODAY} — <fill in task summary>

**Task:** <one sentence>

**Done:**
- <bullet>

**Next:**
- <bullet>

**Blockers:**
- <bullet or None>"

if [ "$FOR_CODEX" -eq 1 ]; then
    printf 'ACTIVE_PROJECT: %s\n' "$PROJECT"
    printf 'WORKING_MD: %s\n' "$WORKING"
    printf 'TODAY: %s\n\n' "$TODAY"
    printf '# Recent Codex history (last %s entries, oldest first)\n' "$HISTORY_LINES"
    read_recent_history
    printf '\n# Checkpoint scaffold (fill in done/next/blockers from this session, then append to WORKING_MD)\n'
    printf '%s\n' "$SCAFFOLD"
    exit 0
fi

# Interactive mode: append scaffold to working.md and open $EDITOR.
printf '\n%s\n' "$SCAFFOLD" >> "$WORKING"

EDITOR_BIN="${EDITOR:-vi}"
exec "$EDITOR_BIN" "$WORKING"
