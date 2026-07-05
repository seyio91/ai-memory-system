#!/usr/bin/env bash
# formatters/xml.sh — serialize content-core section records into the Claude
# `<memory:*>` XML payload. Two renderers, matching the two shapes the Claude
# UserPromptSubmit/SessionStart hooks emit:
#   xml_render_full        — full payload: each section's content wrapped in tags.
#   xml_render_breadcrumb  — lightweight per-prompt pointer: file paths + directive.
# Records arrive on stdin as `kind<TAB>path<TAB>name` (see content-core.sh).
# Output carries no trailing newline, matching the pre-refactor assemble_* helpers.
#
# The xml payload intentionally covers identity/project/index/working only; a
# `domain` record (emitted by the core for the md formatter) is simply ignored
# here, preserving the historical Claude output byte-for-byte.

# xml_render_full — read records on stdin, print the full `<memory:*>` payload.
xml_render_full() {
    local kind path name out=""
    while IFS=$'\t' read -r kind path name; do
        case "$kind" in
            identity)
                out+="<memory:identity>"$'\n'
                out+=$(cat "$path")
                out+=$'\n'"</memory:identity>"$'\n' ;;
            project)
                out+="<memory:project name=\"$name\">"$'\n'
                out+=$(cat "$path")
                out+=$'\n'"</memory:project>"$'\n' ;;
            index)
                out+="<memory:index>"$'\n'
                out+=$(cat "$path")
                out+=$'\n'"</memory:index>"$'\n' ;;
            working)
                out+="<memory:working>"$'\n'
                out+=$(cat "$path")
                out+=$'\n'"</memory:working>"$'\n' ;;
        esac
    done
    printf '%s' "$out"
}

# xml_render_breadcrumb <project> <cwd> — read records on stdin, print the
# `<memory:active ...>` breadcrumb: a project pointer, absolute paths to the
# present memory files, and a re-read directive for compaction recovery.
xml_render_breadcrumb() {
    local project="$1" cwd="$2" kind path name out=""
    out+="<memory:active project=\"$project\" cwd=\"$cwd\">"$'\n'
    while IFS=$'\t' read -r kind path name; do
        case "$kind" in
            identity) out+="identity: $path"$'\n' ;;
            project)  out+="project: $path"$'\n' ;;
            index)    out+="index: $path"$'\n' ;;
            working)  out+="working: $path"$'\n' ;;
        esac
    done
    out+="If these are not already in context (e.g. after compaction), read them before proceeding."
    printf '%s' "$out"
}
