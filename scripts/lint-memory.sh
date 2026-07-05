#!/usr/bin/env bash
# Mechanical lint checks for the memory tree. Prints one finding per line:
#   ERROR: <file> <reason>
#   WARN:  <file> <reason>
# Exit 0 if clean, 1 if any ERROR or WARN was emitted.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
. "$SCRIPT_DIR/_lib.sh"

INDEX="$MEMORY_DIR/index.md"
STALE_DAYS="${MEMORY_STALE_DAYS:-30}"
FOUND=0

emit() {
    printf '%s\n' "$*"
    FOUND=1
}

require_fm() {
    local file="$1"; shift
    local missing=""
    for field in "$@"; do
        if [ -z "$(extract_fm_field "$file" "$field")" ]; then
            missing="$missing $field"
        fi
    done
    if [ -n "$missing" ]; then
        emit "ERROR: $file missing frontmatter fields:$missing"
    fi
}

# 1. Frontmatter required on every domain + project memory file.
for f in "$MEMORY_DIR"/domain/*.md; do
    [ -e "$f" ] || continue
    require_fm "$f" topic triggers summary
done

for f in "$MEMORY_DIR"/projects/*/memory.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    require_fm "$f" topic scope summary
done

# 2. Orphan check — every domain/project memory file must be catalogued in
#    index.md. The index is path-less (a roster), so match by identifier:
#    project → its dir name; domain → its frontmatter topic. Catches a stale
#    index (file added without /reindex).
if [ -f "$INDEX" ]; then
    for f in "$MEMORY_DIR"/projects/*/memory.md; do
        [ -e "$f" ] || continue
        case "$f" in *"/_template/"*) continue;; esac
        name=$(basename "$(dirname "$f")")
        if ! grep -qF "| $name |" "$INDEX"; then
            emit "WARN:  $f orphan — project '$name' not in index.md (run /reindex)"
        fi
    done
    for f in "$MEMORY_DIR"/domain/*.md; do
        [ -e "$f" ] || continue
        topic=$(extract_fm_field "$f" "topic")
        [ -z "$topic" ] && topic="$(basename "$f" .md)"
        if ! grep -qF "| $topic |" "$INDEX"; then
            emit "WARN:  $f orphan — domain '$topic' not in index.md (run /reindex)"
        fi
    done
else
    emit "WARN:  $INDEX missing — run /reindex to create it"
fi

# 3. Project memory section coverage.
REQUIRED_PROJECT_SECTIONS=(
    "## What It Is"
    "## Current State"
    "## Architecture Decisions"
    "## Known Constraints / Gotchas"
    "## Current Goal"
)
for f in "$MEMORY_DIR"/projects/*/memory.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    for section in "${REQUIRED_PROJECT_SECTIONS[@]}"; do
        if ! grep -qxF "$section" "$f"; then
            emit "WARN:  $f missing section: $section"
        fi
    done
done

for f in "$MEMORY_DIR"/domain/*.md; do
    [ -e "$f" ] || continue
    if ! grep -qxF "## Knowledge" "$f"; then
        emit "WARN:  $f missing section: ## Knowledge"
    fi
done

# 4. Orchestrator workflow scaffold — every project must have todo.md, plans/, archive/{plans,todos}.
for d in "$MEMORY_DIR"/projects/*/; do
    [ -d "$d" ] || continue
    case "$d" in *"/_template/"*) continue;; esac
    project=$(basename "$d")
    [ -f "${d}todo.md" ]            || emit "WARN:  ${d}todo.md missing — run scaffold or create the file"
    [ -d "${d}plans" ]              || emit "WARN:  ${d}plans/ missing — orchestrator plans dir not scaffolded"
    [ -d "${d}archive/plans" ]      || emit "WARN:  ${d}archive/plans/ missing — completed-plan archive not scaffolded"
    [ -d "${d}archive/todos" ]      || emit "WARN:  ${d}archive/todos/ missing — rolled-todo archive not scaffolded"
    [ -d "${d}archive/working" ]    || emit "WARN:  ${d}archive/working/ missing — promoted-working-memory archive not scaffolded"
done

# 5. Reverse-map drift — repo_path is optional, but when present it must resolve
#    to a real checkout that back-pins to this same project. Never error on the
#    absence of repo/repo_path/tags.
for f in "$MEMORY_DIR"/projects/*/memory.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    rp=$(extract_fm_field "$f" repo_path)
    [ -n "$rp" ] || continue
    project=$(basename "$(dirname "$f")")
    case "$rp" in
        '$MEMORY_DIR')    cand="$MEMORY_DIR" ;;
        '$MEMORY_DIR/'*)  cand="$MEMORY_DIR/${rp#\$MEMORY_DIR/}" ;;
        /*) cand="$rp" ;;
        *)  cand="$(projects_root)/$rp" ;;
    esac
    if [ ! -d "$cand" ]; then
        emit "WARN:  $f repo_path resolves to missing dir: $cand"
        continue
    fi
    # Prefer the harness-neutral marker; a legacy .claude one still counts but
    # gets a migration nudge (the deprecation warning lives here, off the hot path).
    pin="$cand/.agents/memory-project"
    if [ ! -f "$pin" ] && [ -f "$cand/.claude/memory-project" ]; then
        emit "WARN:  $cand still uses legacy .claude/memory-project — migrate with memory-pin.sh $project"
        pin="$cand/.claude/memory-project"
    fi
    if [ ! -f "$pin" ]; then
        emit "WARN:  $cand missing .agents/memory-project back-pin (run memory-pin.sh $project)"
        continue
    fi
    backpin=$(head -n1 "$pin" | tr -d '[:space:]')
    if [ "$backpin" != "$project" ]; then
        emit "WARN:  $cand back-pin names '$backpin', expected '$project'"
    fi
done

# 6. Stale working memory.
NOW=$(date +%s)
SECONDS_THRESHOLD=$((STALE_DAYS * 86400))
for f in "$MEMORY_DIR"/projects/*/working.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    [ -s "$f" ] || continue
    MTIME=$(stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null)
    [ -z "$MTIME" ] && continue
    AGE=$(( NOW - MTIME ))
    if [ "$AGE" -gt "$SECONDS_THRESHOLD" ]; then
        DAYS=$(( AGE / 86400 ))
        emit "WARN:  $f stale ($DAYS days, threshold $STALE_DAYS) — consider /promote-memory or /checkpoint"
    fi
done

# 7. Changelog drift — memory records DECISIONS and CONSTRAINTS, not events.
#    Flag high-precision "work landed" phrasings in project/domain memory so they
#    get rewritten present-tense or dropped (git already has the event). Patterns
#    are deliberately narrow to spare legit single-anchor gotchas like
#    "fixed in PR #83 via ..." or "restored in <hash>" — only multi-PR / "X merged" /
#    "complete as of" framings, which are unambiguously changelog.
CHANGELOG_RE='merged via PR|PRs #[0-9]|PR #[0-9]+ merged|complete as of'
for f in "$MEMORY_DIR"/projects/*/memory.md "$MEMORY_DIR"/domain/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    while IFS=: read -r lineno _; do
        [ -n "$lineno" ] || continue
        emit "WARN:  $f:$lineno changelog drift — reads as an event, not a decision (rewrite present-tense or drop)"
    done < <(grep -nE "$CHANGELOG_RE" "$f" 2>/dev/null)
done

# 8. Plan status spelling — the canonical in-flight status is `in_progress`
#    (underscore). Flag the hyphenated `in-progress` so status stays uniform
#    (the /activity + /state reports pass `status:` through verbatim). Live
#    plans only; archive is not scanned.
for f in "$MEMORY_DIR"/projects/*/plans/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    if [ "$(extract_fm_field "$f" status)" = "in-progress" ]; then
        emit "WARN:  $f status 'in-progress' — use 'in_progress' (underscore) for uniformity"
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "lint-memory: clean (no warnings or errors)"
    exit 0
fi
exit 1
