#!/usr/bin/env bash
# content-core.sh — the single source of "what memory sections, in what order,
# and whether present". Sourced by every context consumer (the Claude hook via
# memory_common.sh, the Codex adapter via codex-mem.sh). It performs NO rendering:
# it emits a format-neutral, ordered list of the present sections as records, and
# the per-format serializers (formatters/xml.sh, formatters/md.sh) turn those into
# bytes. This replaces the duplicated selection walks that used to live in both
# memory_common.sh (assemble_full_memory/assemble_breadcrumb) and codex-mem.sh.
#
# Depends only on $MEMORY_DIR (set by the caller: memory_common.sh resolves it,
# _lib.sh defaults it). No dependency on _lib.sh helpers, so it is safe to source
# from the Claude hook context which does not load _lib.sh.

# Canonical section order. `content_sections` walks these and emits the ones that
# are present (and, if a filter is given, requested).
_CS_ORDER="identity project index domain working"
_CS_WANT=""

# _cs_want <kind> — true if <kind> is in the active filter (empty filter = all).
_cs_want() {
    [ -z "$_CS_WANT" ] && return 0
    case " $_CS_WANT " in *" $1 "*) return 0 ;; *) return 1 ;; esac
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
            project)
                [ -n "$project" ] && [ -f "$mdir/projects/$project/memory.md" ] \
                    && printf 'project\t%s\t%s\n' "$mdir/projects/$project/memory.md" "$project" ;;
            index)
                [ -f "$mdir/index.md" ] && printf 'index\t%s\t\n' "$mdir/index.md" ;;
            domain)
                [ -d "$mdir/domain" ] && printf 'domain\t%s\t\n' "$mdir/domain" ;;
            working)
                if [ -n "$project" ]; then
                    local w="$mdir/projects/$project/working.md"
                    [ -f "$w" ] && [ -s "$w" ] && printf 'working\t%s\t\n' "$w"
                fi ;;
        esac
    done
    return 0
}
