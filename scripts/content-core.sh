#!/usr/bin/env bash
# content-core.sh — the single source of "what memory sections, in what order,
# and whether present". Sourced by every context consumer (the shared hook lib,
# the Codex adapter via codex-mem.sh). It performs NO rendering:
# it emits a format-neutral, ordered list of the present sections as records, and
# the per-format serializers (formatters/xml.sh, formatters/md.sh) turn those into
# bytes. This replaces the duplicated selection walks that used to live in both
# the old Claude hook helper and codex-mem.sh.
#
# Depends only on $MEMORY_DIR (set by the caller: scripts/hooks/lib.sh resolves it,
# _lib.sh defaults it). No dependency on _lib.sh helpers, so it is safe to source
# from the Claude hook context which does not load _lib.sh.

# Canonical section order. `content_sections` walks these and emits the ones that
# are present (and, if a filter is given, requested).
_CS_ORDER="identity orchestrator orchestrator-local project index domain working"
_CS_WANT=""

# _cs_want <kind> — true if <kind> is in the active filter (empty filter = all).
_cs_want() {
    [ -z "$_CS_WANT" ] && return 0
    case " $_CS_WANT " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# _cs_nonblank <file> — true if <file> exists and has at least one non-whitespace
# byte. Used to presence-gate orchestrator-local: an empty or whitespace-only
# overlay would inject a content-free <memory:orchestrator-local> block, which is
# pure noise, so it is treated the same as "absent" (decision: Phase 2 plan).
_cs_nonblank() {
    [ -r "$1" ] || return 1
    grep -q '[^[:space:]]' "$1" 2>/dev/null
}

# --- working.md overlay resolver (shared across every harness) ------------------
# The working scratchpad is per-session: two concurrent sessions on one repo run
# in two git worktrees, which must not clobber each other's working.md. The key
# (precedence: explicit marker > git worktree > none) selects working.<key>.md;
# no key -> the shared working.md, unchanged. Lives here (not _lib.sh) so the
# hook library — which sources content-core before most _lib helpers — gets it too; _lib.sh
# sources content-core so its callers (checkpoint writers) share this one copy.

# _sanitize_session_key — stdin -> filename-safe [a-z0-9-] token on stdout.
_sanitize_session_key() {
    tr '[:upper:]' '[:lower:]' \
        | sed 's/[^a-z0-9][^a-z0-9]*/-/g; s/^-*//; s/-*$//'
}

# _resolve_git_path <start-dir> <rev-parse-flag> — print the flag's directory as a
# fully resolved absolute path, or fail.
#
# Both rev-parse forms MUST be normalized before they can be compared. git returns
# --git-dir as an ABSOLUTE path from a subdirectory but --git-common-dir as a
# RELATIVE one whose depth varies with cwd:
#
#   cwd            --git-dir              --git-common-dir
#   repo root      .git                   .git              equal
#   projects/      /abs/repo/.git         ../.git           NOT equal
#   a/b/           /abs/repo/.git         ../../.git        NOT equal
#
# Comparing them raw therefore reported "linked worktree" from every non-root cwd
# of every main checkout. `pwd -P` also resolves symlinks, so a session reached
# through ~/.claude-memory compares equal to the same repo reached through its
# real path — a second way the raw comparison could diverge.
_resolve_git_path() {
    local start="$1" flag="$2" p
    p="$(git -C "$start" rev-parse "$flag" 2>/dev/null)" || return 1
    [ -n "$p" ] || return 1
    (cd "$start" 2>/dev/null && cd "$p" 2>/dev/null && pwd -P) || return 1
}

# resolve_session_key <cwd> — print the session key, or empty. Precedence:
#   1. explicit: nearest .agents/memory-session walking up from cwd (sanitized)
#   2. auto:     a LINKED git worktree (git-dir != git-common-dir) -> worktree name
#   3. none:     main checkout, or git absent/error -> empty (fail safe to shared)
resolve_session_key() {
    local start_dir="${1:-$PWD}"
    local dir="$start_dir"
    local marker git_dir git_common_dir key
    while [ -n "$dir" ] && [ "$dir" != "/" ]; do
        marker="$dir/.agents/memory-session"
        if [ -f "$marker" ]; then
            _sanitize_session_key < "$marker"
            return 0
        fi
        dir=$(dirname "$dir")
    done
    git_dir="$(_resolve_git_path "$start_dir" --git-dir)" || return 0
    git_common_dir="$(_resolve_git_path "$start_dir" --git-common-dir)" || return 0
    if [ "$git_dir" != "$git_common_dir" ]; then
        # Validated, not rewritten — deliberately NOT _sanitize_session_key.
        # That helper lowercases (right for hand-typed marker content, wrong
        # here): a worktree named wt-featureB would silently start resolving to
        # working.wt-featureb.md, orphaning the overlay a session was already
        # writing — the same silent divergence this fix exists to remove.
        #
        # A worktree name is a directory name, so it is already filesystem-safe;
        # the only real hazards are a leading dot (`.git`, the shipped bug) and a
        # separator. Reject rather than coerce, and fall back to the shared file:
        # a wrong-but-well-formed key is harder to notice than no key at all.
        key="$(basename "$git_dir")"
        case "$key" in
            ""|.*|*/*) key="" ;;
            *[!A-Za-z0-9._-]*) key="" ;;
        esac
        [ -n "$key" ] && printf '%s\n' "$key"
    fi
    return 0
}

# resolve_working_file <project> <cwd> — absolute path to the working scratchpad
# for this session: working.<key>.md when keyed, else the shared working.md.
resolve_working_file() {
    local project="$1" cwd="${2:-$PWD}" key
    key="$(resolve_session_key "$cwd")"
    if [ -n "$key" ]; then
        printf '%s\n' "$MEMORY_DIR/projects/$project/working.$key.md"
    else
        printf '%s\n' "$MEMORY_DIR/projects/$project/working.md"
    fi
}

# content_sections <project> [kind...] — emit present memory sections as
# tab-separated records `kind<TAB>path<TAB>name`, in canonical order. With no
# kinds, emits every present section; with kinds, restricts to those (still in
# canonical order, still presence-gated). `name` is the project slug for the
# project section (used in its heading) and `legacy` for an orchestrator-local
# record served from a pre-1.6.0 root orchestrator.md; empty otherwise. A
# section is "present" when its backing file exists (working.md and
# orchestrator-local must also be non-blank; domain must be a dir).
content_sections() {
    local project="$1"; shift
    _CS_WANT="$*"
    local mdir="${MEMORY_DIR}" kind
    for kind in $_CS_ORDER; do
        _cs_want "$kind" || continue
        case "$kind" in
            identity)
                [ -f "$mdir/identity.md" ] && printf 'identity\t%s\t\n' "$mdir/identity.md" ;;
            orchestrator)
                [ -f "$mdir/doctrine/orchestrator.md" ] && printf 'orchestrator\t%s\t\n' "$mdir/doctrine/orchestrator.md" ;;
            orchestrator-local)
                # Resolution: an overlay with content wins and the root file is
                # ignored. A blank overlay counts as absent (an empty block is
                # noise) and falls through to a non-blank legacy root
                # orchestrator.md — but ONLY when this instance has never run
                # the 1.6.0 migration (no orchestrator.md.pre-1.6.0 backup).
                # That backup's presence proves the migration already ran and
                # moved any real content out of the root file; a root file
                # found alongside it is a stale re-seed (e.g. a rollback to
                # pre-1.6.0 whose install.sh re-seeded the old template, or a
                # leftover from hand-restoring the backup), not a user's
                # un-migrated doctrine, so it must NOT be injected. Without the
                # backup, the fallback preserves the un-migrated instance's
                # edited doctrine: an install that seeds an empty overlay
                # without migrating never silently drops it. The legacy record
                # is tagged "legacy" via the name field so formatters can
                # append the deprecation notice. A skipped stale root file is
                # still emitted, tagged "ignored": full renderers drop it, but
                # the breadcrumb names it, because a root file edited after a
                # rollback would otherwise stop applying with no signal.
                local ol="$mdir/orchestrator.local.md" legacy="$mdir/orchestrator.md"
                local pre160="$mdir/orchestrator.md.pre-1.6.0"
                if _cs_nonblank "$ol"; then
                    printf 'orchestrator-local\t%s\t\n' "$ol"
                elif _cs_nonblank "$legacy"; then
                    if [ -e "$pre160" ]; then
                        printf 'orchestrator-local\t%s\tignored\n' "$legacy"
                    else
                        printf 'orchestrator-local\t%s\tlegacy\n' "$legacy"
                    fi
                fi ;;
            project)
                [ -n "$project" ] && [ -f "$mdir/projects/$project/memory.md" ] \
                    && printf 'project\t%s\t%s\n' "$mdir/projects/$project/memory.md" "$project" ;;
            index)
                [ -f "$mdir/index.md" ] && printf 'index\t%s\t\n' "$mdir/index.md" ;;
            domain)
                [ -d "$mdir/domain" ] && printf 'domain\t%s\t\n' "$mdir/domain" ;;
            working)
                if [ -n "$project" ]; then
                    local w
                    # AI_MEMORY_WORKING_OVERRIDE pins the exact working file to
                    # render, bypassing cwd/session-key resolution entirely.
                    # resolve_working_file only ever picks ONE overlay from a
                    # real cwd; check-memory-size.sh --payload needs to check
                    # EVERY existing working file for a project (shared
                    # working.md plus each working.<key>.md overlay) regardless
                    # of the checker's own cwd, so it sets this instead.
                    if [ -n "${AI_MEMORY_WORKING_OVERRIDE:-}" ]; then
                        w="$AI_MEMORY_WORKING_OVERRIDE"
                    else
                        w="$(resolve_working_file "$project" "${AI_MEMORY_CWD:-$PWD}")"
                    fi
                    [ -f "$w" ] && [ -s "$w" ] && printf 'working\t%s\t\n' "$w"
                fi ;;
        esac
    done
    return 0
}
