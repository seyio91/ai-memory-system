#!/usr/bin/env bash
# Changelog-drift check for wiki-tier memory (projects/*/memory.md, domain/*.md).
#
# Those files hold DECISIONS and CONSTRAINTS — things that stay true. A record
# of what shipped and when is scratchpad-tier: it belongs in working.md, and
# git already holds the events. Left unchecked, memory.md silently becomes an
# append-only log that costs context on every session start and buries the
# durable entries underneath it.
#
# Usage:  check-changelog-drift.sh <file> [<file>...]
# Prints  <file>:<lineno>: <reason>   one per finding.
# Exit    0 clean, 1 findings, 2 usage error.
#
# Two-Path: this is also the hand-runnable form of the rule. lint-memory.sh
# calls it across the tree; the memory-write hook calls it on one file at the
# moment it is edited. One definition, so the two can never disagree.
set -uo pipefail

if [ "$#" -eq 0 ]; then
    printf 'usage: %s <file> [<file>...]\n' "$(basename "$0")" >&2
    exit 2
fi

# Two patterns, deliberately narrow. A false positive here trains the reader to
# ignore the check, which is worse than missing one.
#
# EVENT_RE — "work landed" phrasings. Spares a legit single-anchor gotcha like
# "fixed in PR #83 via ..." or "restored in <hash>"; only multi-PR, "X merged"
# and "complete as of" framings are unambiguously changelog.
#
# DATED_RE — a paragraph opening with a bold date. This is the shape a log
# actually takes, and it is what the event patterns miss: "**2026-08-13:** both
# open PRs merged" names no PR number and slipped through for weeks. Anchored
# to the line start so the common inline dateline of a durable entry —
# "**Config = TOML** ... (2026-08-13)" or "(measured 2026-09-23, go1.26.2)" —
# is untouched. Measured across 19 projects and 12 domain files: every hit was
# a genuine log paragraph.
#
# PROJECT_DATED_RE — same shape, widened for `projects/*/memory.md` only, to
# also catch a bracketed date (`**[2026-08-13]**`) and either form prefixed by
# a list bullet (`- **2026-08-13`, `- **[2026-08-13]**`). This is deliberately
# NOT applied to `domain/*.md`: `/promote-memory` writes `**[YYYY-MM-DD]**`
# entries into a domain file's `## Knowledge` section by design — that section
# IS the dated log, a project `## Decisions Log` is not. Still anchored to the
# line start, so an inline dateline stays untouched.
EVENT_RE='merged via PR|PRs #[0-9]|PR #[0-9]+ merged|complete as of'
DATED_RE='^\*\*[0-9]{4}-[0-9]{2}-[0-9]{2}'
PROJECT_DATED_RE='^(- )?\*\*(\[)?[0-9]{4}-[0-9]{2}-[0-9]{2}'

# is_project_memory <path> — true for a `projects/*/memory.md`, absolute or
# relative, which is the only tier PROJECT_DATED_RE applies to.
is_project_memory() {
    case "$1" in
        */projects/*/memory.md|projects/*/memory.md) return 0 ;;
        *) return 1 ;;
    esac
}

found=0

for f in "$@"; do
    [ -f "$f" ] || continue

    while IFS=: read -r lineno _; do
        [ -n "$lineno" ] || continue
        printf '%s:%s: reads as an event, not a decision — rewrite present-tense or drop (git has the event)\n' "$f" "$lineno"
        found=1
    done < <(grep -nE "$EVENT_RE" "$f" 2>/dev/null)

    if is_project_memory "$f"; then
        dated_re="$PROJECT_DATED_RE"
    else
        dated_re="$DATED_RE"
    fi

    while IFS=: read -r lineno _; do
        [ -n "$lineno" ] || continue
        printf '%s:%s: dated log entry — this tier holds standing state, so move the history to working.md\n' "$f" "$lineno"
        found=1
    done < <(grep -nE "$dated_re" "$f" 2>/dev/null)
done

exit "$found"
