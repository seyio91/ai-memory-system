#!/usr/bin/env bash
# PostToolUse guard for wiki-tier memory writes.
#
# Why this exists as a hook rather than an instruction: the rule ("memory.md
# holds decisions, working.md holds history") was already written down, and the
# detector already existed in lint-memory.sh. Neither prevented projects/git-cli
# /memory.md from accumulating five dated PR-by-PR paragraphs over three
# sessions, because nothing ran the lint and the instruction was one line in a
# long file. A prompt instruction is a hint; the control has to run.
#
# Scope (grew from changelog-drift-only to size/payload budgets too — see the
# memory-size-budgets plan):
#   - projects/*/memory.md         changelog drift, the byte/line budget on
#                                   that file (--file), AND the rendered
#                                   session-payload budget for every working
#                                   file the project has (--payload, no
#                                   --working) — a memory.md edit alone can
#                                   push the payload over a harness's cap even
#                                   though the edit never touched working.md.
#   - projects/*/working.md or
#     projects/*/working.<key>.md  session-payload budget ONLY, pinned to the
#     (incl. worktree overlays)    ONE file just written (--payload --working
#                                   <file>). No drift check here: working.md
#                                   IS the scratchpad/history tier — a dated
#                                   entry is the expected shape, not drift.
#   - domain/*.md                  changelog drift only, unchanged. No size
#                                   budget applies to domain/*.md (lazy-loaded,
#                                   never injected — see the plan's Decisions).
#
# Fires after a Write/Edit, runs whichever checks are in scope for the target,
# and reports on stderr with exit 2 — the PostToolUse code that feeds output
# back to the model, so the problem is corrected in the same turn it was
# introduced rather than at some later audit. The write itself already
# happened and is never reverted: this reports, it does not block.
#
# Fails open. A guard that breaks editing when jq is missing, a checker is
# absent, or a payload shape changes is worse than the drift/overflow it
# catches.
set -uo pipefail

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_DIR="${MEMORY_DIR:-$(cd "$hook_dir/../.." && pwd)}"

# Resolved from this script's own location, not from MEMORY_DIR: the two are
# the same in a normal install, but MEMORY_DIR is the tree being *inspected*
# and the checkers are part of the install. Tying them together made the
# guard fail open the moment MEMORY_DIR pointed anywhere else, which is
# exactly how a guard dies quietly. Each is used only where `-x` holds —
# a missing checker silently drops just its own half of the report.
drift_checker="$hook_dir/../check-changelog-drift.sh"
size_checker="$hook_dir/../check-memory-size.sh"

payload="$(cat 2>/dev/null)" || exit 0
[ -n "$payload" ] || exit 0

# file_path is where both Write and Edit carry the target. MultiEdit and any
# future tool with a different shape simply yield nothing and fall through.
file=""
if command -v jq >/dev/null 2>&1; then
    file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
else
    file="$(printf '%s' "$payload" | sed -n 's/.*"file_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
fi
[ -n "$file" ] || exit 0
[ -f "$file" ] || exit 0
case "$file" in *"/_template/"*|*/_template.md) exit 0 ;; esac

# report accumulates one labeled section per non-empty finding set; a missing
# checker or a clean run just contributes nothing, never a blank section.
report=""
add_report() { # add_report <label> <findings>
    [ -n "$2" ] || return 0
    report="${report}${report:+$'\n\n'}$1:
$2"
}

# advice is tier-specific: the memory.md/domain message tells the writer to
# move dated lines OUT to the project's working.md, which is correct advice
# there but nonsensical on a working.md/working.<key>.md write itself (it
# already IS that destination) — that mismatch is FIX4. Each branch below
# sets its own `advice` to the message appropriate for what was just written.
advice=""

case "$file" in
    "$MEMORY_DIR"/projects/*/memory.md)
        project="${file#"$MEMORY_DIR"/projects/}"
        project="${project%%/*}"

        if [ -x "$drift_checker" ]; then
            add_report "Changelog drift in ${file#"$MEMORY_DIR"/}" \
                "$("$drift_checker" "$file" 2>/dev/null)"
        fi
        if [ -x "$size_checker" ]; then
            add_report "Size budget in ${file#"$MEMORY_DIR"/}" \
                "$("$size_checker" --file "$file" 2>/dev/null)"
            add_report "Session payload for project '$project'" \
                "$("$size_checker" --payload "$project" 2>/dev/null)"
        fi
        advice="This tier holds what stays true. Move the dated/event lines to the project's working.md (or drop them — git already records what shipped), trim the file toward its size budget, or raise the harness's session_chunks cap if the payload growth is expected."
        ;;
    "$MEMORY_DIR"/projects/*/working.md|"$MEMORY_DIR"/projects/*/working.*.md)
        project="${file#"$MEMORY_DIR"/projects/}"
        project="${project%%/*}"

        if [ -x "$size_checker" ]; then
            add_report "Session payload for project '$project'" \
                "$("$size_checker" --payload "$project" --working "$file" 2>/dev/null)"
        fi
        # This IS the scratch/history tier already — a finding here is a
        # payload-size problem, never a drift problem, so the advice is
        # payload-appropriate only: shrink what gets delivered, don't move
        # content into the file that was just written.
        advice="This is the session-payload tier, not a drift problem — growth here is expected. Archive old checkpoints out with /checkpoint-archive, promote durable entries with /promote-memory (or drop stale notes — git already records what shipped), or raise the harness's session_chunks cap if the payload growth is expected."
        ;;
    "$MEMORY_DIR"/domain/*.md)
        if [ -x "$drift_checker" ]; then
            add_report "Changelog drift in ${file#"$MEMORY_DIR"/}" \
                "$("$drift_checker" "$file" 2>/dev/null)"
        fi
        # Drift-only, deliberately: domain/*.md never runs the size_checker
        # above (no --file, no --payload call in this branch), because
        # domain content is lazy-loaded and never injected into a session
        # payload (see this file's header). Advice that tells the writer to
        # "trim toward its size budget" or "raise the session_chunks cap"
        # would be pointing at a check this branch never ran.
        advice="This tier holds what stays true. Move the dated/event lines to the relevant project's working.md (or drop them — git already records what shipped)."
        ;;
    *) exit 0 ;;
esac

[ -n "$report" ] || exit 0

{
    printf '%s\n\n' "$report"
    printf '%s\n' "$advice"
} >&2

exit 2
