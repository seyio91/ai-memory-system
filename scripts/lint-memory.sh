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
        # The domain scaffold carries a placeholder `topic: <topic>` and can
        # never appear in the index — mirrors the */_template/* skip above.
        case "$f" in */_template.md) continue;; esac
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
for f in "$MEMORY_DIR"/projects/*/working.md "$MEMORY_DIR"/projects/*/working.*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    [ -s "$f" ] || continue
    # A working file holding only headings and `_(placeholder)_` lines has
    # nothing to promote or checkpoint, so its mtime is not evidence of
    # neglect — warning on it is noise that trains the reader to ignore the
    # check. `[ -s ]` above only catches a zero-BYTE file, not an empty one.
    if [ -z "$(grep -vE '^[[:space:]]*$|^#{1,6}[[:space:]]|^_\(.*\)_[[:space:]]*$' "$f")" ]; then
        continue
    fi
    # GNU form first: `stat -c` fails cleanly on BSD, but BSD's `stat -f` is a
    # valid *different* mode on GNU and pollutes the value. See regenerate-state.sh.
    MTIME=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null)
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

# 8. Plan status vocabulary — a live plan carries exactly one of `draft`,
#    `in_progress`, `done`. That is what the tooling itself produces: /new-plan
#    scaffolds `draft` and /plan-done writes `done`. Anything else (or a missing
#    `status:`) is drift, because /state and /activity render the value
#    verbatim — a synonym like `active` silently splits one column into two, and
#    an absent status renders blank. Documented in docs/file-formats.md; this
#    rule is the enforcement, not the source. Live plans only; archive not scanned.
#
#    Checked by value rather than by blacklisting one typo: the previous rule
#    flagged only the hyphenated `in-progress`, which nothing in the tree ever
#    used, while `active` and missing-status plans passed clean.
for f in "$MEMORY_DIR"/projects/*/plans/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    st=$(extract_fm_field "$f" status)
    case "$st" in
        draft|in_progress|done) ;;
        "")
            emit "WARN:  $f has no status — add one of: draft, in_progress, done (/state and /activity render it blank)"
            ;;
        in-progress)
            emit "WARN:  $f status 'in-progress' — use 'in_progress' (underscore)"
            ;;
        *)
            emit "WARN:  $f status '$st' is not a plan status — use one of: draft, in_progress, done"
            ;;
    esac
done

# 9. Investigations must be tied to a task lifecycle — a live investigation
#    carries a frontmatter `task_ref` (the task it seeds or serves); when that
#    task closes, the file moves to archive/investigations/. An orphan has no
#    lifecycle anchor and never gets archived. Live dir only; archive not scanned.
for f in "$MEMORY_DIR"/projects/*/investigations/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    if [ -z "$(extract_fm_field "$f" task_ref)" ]; then
        emit "WARN:  $f has no task_ref — attach the task it serves (or archive it to archive/investigations/)"
    fi
done

# 10. Stale investigation — a live investigation whose `task_ref` matches a plan
#     already sitting in archive/plans/ means that task's work has shipped and
#     the investigation was left behind by mistake (/plan-archive should have
#     moved it too). Purely local: compare `task_ref` frontmatter values within
#     the same project's investigations/ and archive/plans/ trees — never calls
#     the task provider. Live investigations dir only; archive not scanned.
for f in "$MEMORY_DIR"/projects/*/investigations/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    ref=$(extract_fm_field "$f" task_ref)
    if [ -z "$ref" ] || [ "$ref" = "none" ]; then
        continue
    fi
    project_dir=$(dirname "$(dirname "$f")")
    for p in "$project_dir"/archive/plans/*.md; do
        [ -e "$p" ] || continue
        plan_ref=$(extract_fm_field "$p" task_ref)
        if [ "$plan_ref" != "none" ] && [ "$plan_ref" = "$ref" ]; then
            emit "WARN:  $f stale — task_ref matches archived plan $p (work shipped; archive this investigation too)"
            break
        fi
    done
done

# 11. Initiatives are live, cross-project work state rather than catalogued
#     knowledge. Check only top-level instances: the scaffold and closed archive
#     are deliberately excluded.
for f in "$MEMORY_DIR"/initiatives/*.md; do
    [ -e "$f" ] || continue
    case "$f" in */_template.md) continue;; esac

    require_fm "$f" kind slug status created
    kind=$(extract_fm_field "$f" kind)
    initiative_slug=$(extract_fm_field "$f" slug)
    initiative_status=$(extract_fm_field "$f" status)
    filename_slug=$(basename "$f" .md)

    if [ -n "$kind" ] && [ "$kind" != "initiative" ]; then
        emit "WARN:  $f kind '$kind' is not 'initiative'"
    fi
    if [ -n "$initiative_slug" ] && [ "$initiative_slug" != "$filename_slug" ]; then
        emit "WARN:  $f slug '$initiative_slug' does not match filename '$filename_slug'"
    fi
    case "$initiative_status" in
        active|closed|"") ;;
        *) emit "WARN:  $f status '$initiative_status' is not an initiative status — use one of: active, closed" ;;
    esac

    target_ids=()
    target_modes=()
    target_stages=()
    target_depends=()
    while IFS='|' read -r target_id target_mode target_stages_present target_depends_on; do
        [ -n "$target_id" ] || continue
        target_ids[${#target_ids[@]}]="$target_id"
        target_modes[${#target_modes[@]}]="$target_mode"
        target_stages[${#target_stages[@]}]="$target_stages_present"
        target_depends[${#target_depends[@]}]="$target_depends_on"
    done < <(
        awk '
            /^## Targets[[:space:]]*$/ { in_targets = 1; next }
            in_targets && /^## / { exit }
            in_targets && /^### / {
                if (have_target) {
                    print target "|" mode "|" stages "|" depends
                }
                target = substr($0, 5)
                mode = ""
                stages = ""
                depends = ""
                have_target = 1
                next
            }
            in_targets && have_target && /^- execution_mode: / {
                mode = $0
                sub(/^- execution_mode: /, "", mode)
                next
            }
            in_targets && have_target && /^- stages: / {
                stages = "present"
                next
            }
            in_targets && have_target && /^- depends_on: / {
                depends = $0
                sub(/^- depends_on: /, "", depends)
            }
            END {
                if (in_targets && have_target) {
                    print target "|" mode "|" stages "|" depends
                }
            }
        ' "$f"
    )

    if [ ${#target_ids[@]} -gt 0 ]; then
        for i in "${!target_ids[@]}"; do
            for j in "${!target_ids[@]}"; do
                [ "$i" -ge "$j" ] && continue
                if [ "${target_ids[$i]}" = "${target_ids[$j]}" ]; then
                    emit "WARN:  $f duplicate Target id '${target_ids[$i]}'"
                fi
            done

            if [ "${target_modes[$i]}" = "software_adw" ] && [ -z "${target_stages[$i]}" ]; then
                emit "WARN:  $f Target '${target_ids[$i]}' execution_mode 'software_adw' has no stages"
            fi
            if [ "${target_modes[$i]}" != "software_adw" ] && [ -n "${target_stages[$i]}" ]; then
                emit "WARN:  $f Target '${target_ids[$i]}' has stages but execution_mode is '${target_modes[$i]}'"
            fi

            remaining_depends="${target_depends[$i]}"
            while [ -n "$remaining_depends" ]; do
                case "$remaining_depends" in
                    *,*) dependency=${remaining_depends%%,*}; remaining_depends=${remaining_depends#*,} ;;
                    *) dependency=$remaining_depends; remaining_depends="" ;;
                esac
                dependency=$(printf '%s\n' "$dependency" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
                [ "$dependency" = "none" ] && continue
                dependency_id=$(printf '%s\n' "$dependency" | sed 's/[[:space:]]*(stage: [^)]*)[[:space:]]*$//')
                resolved=0
                for known_target in "${target_ids[@]}"; do
                    if [ "$known_target" = "$dependency_id" ]; then
                        resolved=1
                        break
                    fi
                done
                if [ "$resolved" -eq 0 ]; then
                    emit "WARN:  $f Target '${target_ids[$i]}' depends_on unresolved Target id '$dependency_id'"
                fi
            done
        done
    fi
done

# 12. Task linkage — every live plan either serves a task or explicitly records
#     that it is deliberately plan-only. Archive/plans/ is historical and never
#     scanned; its task_ref belongs to the completed work, not a live decision.
for f in "$MEMORY_DIR"/projects/*/plans/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    if [ -z "$(extract_fm_field "$f" task_ref)" ]; then
        emit "WARN:  $f has no task_ref — link the task it serves, or set task_ref: none if deliberately plan-only"
    fi
done

if [ "$FOUND" -eq 0 ]; then
    echo "lint-memory: clean (no warnings or errors)"
    exit 0
fi
exit 1
