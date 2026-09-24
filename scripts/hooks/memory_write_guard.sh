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
# Fires after a Write/Edit whose target is projects/*/memory.md or domain/*.md,
# runs the shared drift check on that one file, and reports on stderr with
# exit 2 — the PostToolUse code that feeds output back to the model, so the
# drift is corrected in the same turn it was introduced rather than at some
# later audit. The write itself already happened and is never reverted: this
# reports, it does not block.
#
# Fails open. A guard that breaks editing when jq is missing or the payload
# shape changes is worse than the drift it catches.
set -uo pipefail

hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MEMORY_DIR="${MEMORY_DIR:-$(cd "$hook_dir/../.." && pwd)}"

# Resolved from this script's own location, not from MEMORY_DIR: the two are
# the same in a normal install, but MEMORY_DIR is the tree being *inspected*
# and the checker is part of the install. Tying them together made the guard
# fail open the moment MEMORY_DIR pointed anywhere else, which is exactly how
# a guard dies quietly.
checker="$hook_dir/../check-changelog-drift.sh"

[ -x "$checker" ] || exit 0

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

# Wiki tier only. working.md, todo.md, plans/ and investigations/ are where a
# log is *supposed* to go, so they are deliberately out of scope.
case "$file" in
    "$MEMORY_DIR"/projects/*/memory.md) ;;
    "$MEMORY_DIR"/domain/*.md) ;;
    *) exit 0 ;;
esac
case "$file" in *"/_template/"*|*/_template.md) exit 0 ;; esac

findings="$("$checker" "$file" 2>/dev/null)"
[ -n "$findings" ] || exit 0

{
    printf 'Changelog drift in %s:\n\n' "${file#"$MEMORY_DIR"/}"
    printf '%s\n' "$findings"
    printf '\n%s\n' "This tier holds what stays true. Move the dated/event lines to the project's working.md (or drop them — git already records what shipped), and leave behind only the standing state or the durable decision."
} >&2

exit 2
