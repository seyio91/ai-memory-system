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
_CS_ORDER="identity orchestrator project index domain working"
_CS_WANT=""

# _cs_want <kind> — true if <kind> is in the active filter (empty filter = all).
_cs_want() {
    [ -z "$_CS_WANT" ] && return 0
    case " $_CS_WANT " in *" $1 "*) return 0 ;; *) return 1 ;; esac
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
# canonical order, still presence-gated). `name` is set for the project section
# only (the project slug, used in its heading). A section is "present" when its
# backing file exists (working.md must also be non-empty; domain must be a dir).
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
                [ -f "$mdir/orchestrator.md" ] && printf 'orchestrator\t%s\t\n' "$mdir/orchestrator.md" ;;
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
                    w="$(resolve_working_file "$project" "${AI_MEMORY_CWD:-$PWD}")"
                    [ -f "$w" ] && [ -s "$w" ] && printf 'working\t%s\t\n' "$w"
                fi ;;
        esac
    done
    return 0
}
