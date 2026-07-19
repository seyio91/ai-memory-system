#!/usr/bin/env bash
# formatters/xml.sh — serialize content-core section records into the Claude
# `<memory:*>` XML payload. Two renderers, matching the two shapes the Claude
# UserPromptSubmit/SessionStart hooks emit:
#   xml_render_full        — full payload: each section's content wrapped in tags.
#   xml_render_breadcrumb  — lightweight per-prompt pointer: file paths + directive.
# Records arrive on stdin as `kind<TAB>path<TAB>name` (see content-core.sh).
# Output carries no trailing newline, matching the pre-refactor assemble_* helpers.
#
# The xml payload intentionally covers identity/orchestrator/project/index/working only; a
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
            orchestrator)
                out+="<memory:orchestrator>"$'\n'
                out+=$(cat "$path")
                out+=$'\n'"</memory:orchestrator>"$'\n' ;;
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

# xml_render_breadcrumb <project> <cwd> [session_id] [cwd_project] — read records
# on stdin, print the `<memory:active ...>` breadcrumb: a project pointer,
# absolute paths to the present memory files, and a re-read directive for
# compaction recovery.
#
# The trailing two args are optional and omitted by older callers, so the render
# is unchanged when they are absent. `session_id` is advertised so /pin can target
# THIS session's pin file — the agent cannot otherwise learn its own session id,
# since the hook stdin that carries it is consumed by a different process.
# `cwd_project` is what cwd alone would have resolved to; when it disagrees with
# the project actually in force, say so rather than silently ignoring the cd.
xml_render_breadcrumb() {
    local project="$1" cwd="$2" session="${3:-}" cwd_project="${4:-}" kind path name out=""
    out+="<memory:active project=\"$project\" cwd=\"$cwd\">"$'\n'
    [ -n "$session" ] && out+="session: $session"$'\n'
    if [ -n "$cwd_project" ] && [ "$cwd_project" != "$project" ]; then
        out+="pinned: $project (cwd resolves to '$cwd_project'; /pin to change)"$'\n'
    fi
    while IFS=$'\t' read -r kind path name; do
        case "$kind" in
            identity) out+="identity: $path"$'\n' ;;
            orchestrator) out+="orchestrator: $path"$'\n' ;;
            project)  out+="project: $path"$'\n' ;;
            index)    out+="index: $path"$'\n' ;;
            working)  ;;  # emitted below as the always-present write target
        esac
    done
    # working.md is the checkpoint WRITE target: advertise the resolved overlay
    # path unconditionally (even before the file exists — the first checkpoint in
    # a fresh worktree must land in working.<key>.md, not the base), so /checkpoint
    # writes to the right file. The read side (full payload) stays presence-gated.
    if command -v resolve_working_file >/dev/null 2>&1; then
        out+="working: $(resolve_working_file "$project" "$cwd")"$'\n'
    fi
    out+="If these are not already in context (e.g. after compaction), read them before proceeding."
    printf '%s' "$out"
}
