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
    "## Architecture Decisions"
    "## Known Constraints / Gotchas"
)
# Retired sections: each invites frequently-changing status, which the content
# contract keeps out of memory.md. The WARN names where the content goes.
OBSOLETE_PROJECT_SECTIONS=(
    "## Current State|move standing facts to What It Is or Known Constraints / Gotchas, session history to working.md"
    "## Current Goal|the active goal lives in todo.md (/state reads it from there)"
)
for f in "$MEMORY_DIR"/projects/*/memory.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    for section in "${REQUIRED_PROJECT_SECTIONS[@]}"; do
        if ! grep -qxF "$section" "$f"; then
            emit "WARN:  $f missing section: $section"
        fi
    done
    for entry in "${OBSOLETE_PROJECT_SECTIONS[@]}"; do
        section="${entry%%|*}"
        if grep -qxF "$section" "$f"; then
            emit "WARN:  $f obsolete section: $section — ${entry#*|}"
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
#    The patterns live in check-changelog-drift.sh so that this sweep and the
#    memory-write hook share one definition — a rule enforced in two places
#    with two copies of the regex is a rule that will disagree with itself.
for f in "$MEMORY_DIR"/projects/*/memory.md "$MEMORY_DIR"/domain/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    while IFS= read -r finding; do
        [ -n "$finding" ] || continue
        emit "WARN:  changelog drift — ${finding#"$MEMORY_DIR"/}"
    done < <("$SCRIPT_DIR/check-changelog-drift.sh" "$f" 2>/dev/null)
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
#    carries a frontmatter `task_ref` (the task it seeds or serves); `none` is
#    plans-only vocabulary: a plan may be plan-only, an investigation never is.
#    When that task closes, the file moves to archive/investigations/. An orphan
#    has no lifecycle anchor and never gets archived. Live dir only; archive not scanned.
for f in "$MEMORY_DIR"/projects/*/investigations/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    ref=$(extract_fm_field "$f" task_ref)
    if [ -z "$ref" ] || [ "$ref" = "none" ]; then
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
        if [ "$plan_ref" = "$ref" ]; then
            emit "WARN:  $f stale — task_ref matches archived plan $p (work shipped; archive this investigation too)"
            break
        fi
    done
done

# 11. Initiatives are live, cross-project work state rather than catalogued
#     knowledge. Check only top-level instances: the scaffold and closed archive
#     are deliberately excluded.

# Cross-file accumulator for rule 15a — populated per-Target inside the loop
# below, compared once after every initiative file has been scanned.
ALL_TASK_REFS=()
ALL_TASK_TARGET_IDS=()
ALL_TASK_TARGET_FILES=()

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

    # 13. A Target status is an optional assertion. When present, its first
    #     machine-readable token must use the shared status vocabulary.
    while IFS='|' read -r target_id target_status; do
        case "$target_status" in
            open|"open "*|blocked|"blocked "*|done|"done "*|closed|"closed "*) ;;
            *) emit "WARN:  $f Target '$target_id' status must begin with open, blocked, done, or closed" ;;
        esac
    done < <(
        awk '
            /^## Targets[[:space:]]*$/ { in_targets = 1; next }
            in_targets && /^## / { exit }
            in_targets && /^### / {
                target = substr($0, 5)
                next
            }
            in_targets && target != "" && /^- status: / {
                status = $0
                sub(/^- status: /, "", status)
                print target "|" status
            }
        ' "$f"
    )

    # 14. A live Target must be decomposed into a task. Non-terminal (open or
    #     blocked) status is a live assertion and needs a `- task:` pointer;
    #     done/closed are terminal and exempt; a Target with NO `- status:`
    #     line at all is undeclared, not live — lint checks what is asserted,
    #     it does not derive. `status (historical):` is not a status line
    #     (matched by rule 13's `^- status: ` above, same exclusion here).
    #
    #     Also feeds rule 15a: every Target|task pair with a non-empty task is
    #     appended to the cross-file accumulator declared before this loop.
    while IFS='|' read -r target_id target_status target_task; do
        [ -n "$target_id" ] || continue
        case "$target_status" in
            open|"open "*|blocked|"blocked "*)
                if [ -z "$target_task" ]; then
                    emit "WARN:  $f Target '$target_id' is open/blocked but has no task"
                fi
                ;;
        esac
        if [ -n "$target_task" ]; then
            ALL_TASK_REFS[${#ALL_TASK_REFS[@]}]="$target_task"
            ALL_TASK_TARGET_IDS[${#ALL_TASK_TARGET_IDS[@]}]="$target_id"
            ALL_TASK_TARGET_FILES[${#ALL_TASK_TARGET_FILES[@]}]="$f"
        fi
    done < <(
        awk '
            /^## Targets[[:space:]]*$/ { in_targets = 1; next }
            in_targets && /^## / { exit }
            in_targets && /^### / {
                if (have_target) {
                    print target "|" status "|" task
                }
                target = substr($0, 5)
                status = ""
                task = ""
                have_target = 1
                next
            }
            in_targets && have_target && /^- status: / {
                status = $0
                sub(/^- status: /, "", status)
                next
            }
            in_targets && have_target && /^- task: / {
                task = $0
                sub(/^- task: /, "", task)
                next
            }
            END {
                if (in_targets && have_target) {
                    print target "|" status "|" task
                }
            }
        ' "$f"
    )
done

# 15. Task/plan uniqueness, joined on the task ref.
#
#     (a) A task ref must appear on at most one Target across ALL live
#         initiative files — the accumulator above was filled per-Target while
#         scanning them; compare it pairwise once, here, after every file has
#         contributed.
for i in "${!ALL_TASK_REFS[@]}"; do
    for j in "${!ALL_TASK_REFS[@]}"; do
        [ "$i" -ge "$j" ] && continue
        if [ "${ALL_TASK_REFS[$i]}" = "${ALL_TASK_REFS[$j]}" ]; then
            emit "WARN:  ${ALL_TASK_TARGET_FILES[$j]} task '${ALL_TASK_REFS[$i]}' on Target '${ALL_TASK_TARGET_IDS[$j]}' is already used by Target '${ALL_TASK_TARGET_IDS[$i]}' in ${ALL_TASK_TARGET_FILES[$i]}"
        fi
    done
done

#     (b) At most one live plan may carry a given task ref. `none` is
#         plans-only vocabulary meaning deliberately plan-only and is never
#         compared. Matching is full-string equality, never a prefix — the
#         same rule Phase 2's derivation relies on. Archive is not scanned:
#         only live plans can collide with a live Target.
SEEN_TASK_REFS=""
for i in "${!ALL_TASK_REFS[@]}"; do
    ref="${ALL_TASK_REFS[$i]}"
    [ "$ref" = "none" ] && continue
    case "$SEEN_TASK_REFS" in
        *"|$ref|"*) continue ;;
    esac
    SEEN_TASK_REFS="${SEEN_TASK_REFS}|$ref|"

    matching_plans=()
    for p in "$MEMORY_DIR"/projects/*/plans/*.md; do
        [ -e "$p" ] || continue
        case "$p" in *"/_template/"*) continue;; esac
        plan_ref=$(extract_fm_field "$p" task_ref)
        [ "$plan_ref" = "$ref" ] || continue
        matching_plans[${#matching_plans[@]}]="$p"
    done
    if [ "${#matching_plans[@]}" -gt 1 ]; then
        joined=""
        for p in "${matching_plans[@]}"; do
            joined="${joined:+$joined, }$p"
        done
        emit "WARN:  task '$ref' is claimed by multiple live plans: $joined"
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

# 16. Size budgets — a project `memory.md` over 16 KB or carrying lines over
#     400 B reads more slowly every session; a rendered session payload that
#     needs more chunks than a harness's manifest declares gets truncated
#     silently past the cap. Both checks live in check-memory-size.sh so that
#     this sweep and the memory-write hook share one definition — same reuse
#     pattern as rule 7's check-changelog-drift.sh. Budget and long-line
#     findings are WARN (style); payload overflow is ERROR (the harness
#     actually drops content).
#
#     check-memory-size.sh's own finding text already carries a "WARN "/
#     "ERROR " label (it needs one when run by hand — see that script's
#     header) immediately after the "<file>:<line>: " prefix. Re-prepending
#     this sweep's own "WARN:  "/"ERROR: " on top of that unstripped would
#     double the label ("WARN:  ...:1: WARN budget — ..."). emit_size_finding
#     classifies AND strips that inner label in one step.
#
#     The $MEMORY_DIR/ prefix is stripped FIRST, before classification, not
#     after: the case patterns below test for the "<file>:<N>: (ERROR|WARN) "
#     shape anywhere in the string, not anchored to its actual fixed
#     position right after check-memory-size.sh's own "<file>:<line>: "
#     prefix (a plain case glob can't express "only at this offset"). A
#     $MEMORY_DIR path that itself happens to contain ":<digits>: ERROR "
#     (an unusual but legal directory name) would otherwise match the ERROR
#     arm before the classifier ever reaches the real, correctly-WARN,
#     severity token — misclassifying it. Stripping the known $MEMORY_DIR/
#     prefix first removes that false match from the string the case
#     patterns see, leaving only the path lint-memory.sh itself controls
#     (projects/*/memory.md, projects/*/working*.md) where such a collision
#     is not expected.
emit_size_finding() {
    local finding="$1" rel stripped
    rel="${finding#"$MEMORY_DIR"/}"
    case "$rel" in
        *:[0-9]*': ERROR '*)
            stripped="$(printf '%s\n' "$rel" | sed -E 's/^(.*:[0-9]+): ERROR /\1: /')"
            emit "ERROR: $stripped"
            ;;
        *:[0-9]*': WARN '*)
            stripped="$(printf '%s\n' "$rel" | sed -E 's/^(.*:[0-9]+): WARN /\1: /')"
            emit "WARN:  $stripped"
            ;;
        *)
            emit "WARN:  $rel"
            ;;
    esac
}

for f in "$MEMORY_DIR"/projects/*/memory.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*) continue;; esac
    while IFS= read -r finding; do
        [ -n "$finding" ] || continue
        emit_size_finding "$finding"
    done < <("$SCRIPT_DIR/check-memory-size.sh" --file "$f" 2>/dev/null)
done

# One --payload call for every project, not one per project: the domain-index
# render and the initiative alert are the same across projects, and a batched
# run computes each once (see check-memory-size.sh's _cms_get_alert).
payload_projects=()
for d in "$MEMORY_DIR"/projects/*/; do
    [ -d "$d" ] || continue
    case "$d" in *"/_template/"*) continue;; esac
    payload_projects[${#payload_projects[@]}]="$(basename "$d")"
done
if [ "${#payload_projects[@]}" -gt 0 ]; then
    while IFS= read -r finding; do
        [ -n "$finding" ] || continue
        emit_size_finding "$finding"
    done < <("$SCRIPT_DIR/check-memory-size.sh" --payload "${payload_projects[@]}" 2>/dev/null)
fi

# 17. Exact cross-file duplicate lines — a content line that appears verbatim
#     (list, ordered-list and blockquote markers stripped, whitespace
#     collapsed) in two or more different project `memory.md` / `domain/*.md`
#     files is a fact stated twice, which drifts. Frontmatter, fenced code,
#     HTML comments, headings, table separator and header rows, and lines
#     under 40 bytes (boilerplate like `_(none yet)_`) are ignored; repeats
#     inside one file are not this rule's concern. Every `_template` is
#     skipped. Inline: only a whole-tree sweep can see cross-file repeats, so
#     the memory-write hook has nothing to reuse (contrast rules 7 and 16).
#
# 18. Unresolved markers — `NEEDS REVIEW` or a case-sensitive whole-word `TODO`
#     in the same file set. Frontmatter, fenced code, HTML comments and inline
#     code spans are skipped, so `todo.md`, `TODOs`, `TODO.md`, `TODO/`,
#     `TODO-list` and a backticked mention of the marker do not fire.
#
#     Both run in one awk under LC_ALL=C (byte lengths, same on BSD awk and
#     gawk); a non-zero awk exit is an ERROR, never a silent pass.
dup_files=()
for f in "$MEMORY_DIR"/projects/*/memory.md "$MEMORY_DIR"/domain/*.md; do
    [ -e "$f" ] || continue
    case "$f" in *"/_template/"*|*"/_template.md") continue;; esac
    dup_files[${#dup_files[@]}]="$f"
done
if [ "${#dup_files[@]}" -gt 0 ]; then
    dup_out="$(LC_ALL=C awk '
        function flush() {
            if (pk == "") return
            if (!(pk in files)) { order[++n] = pk; files[pk] = pf; first[pk] = pl; locs[pk] = ""; cnt[pk] = 1 }
            else {
                locs[pk] = (locs[pk] == "" ? pl : locs[pk] ", " pl)
                if (index(files[pk] "\n", pf "\n") == 0) { files[pk] = files[pk] "\n" pf; cnt[pk]++ }
            }
            pk = ""
        }
        function mask(s,    out, sp) {
            out = ""
            while (match(s, /``[^`]*(`[^`]+)*``|`[^`]*`/)) {
                sp = substr(s, RSTART, RLENGTH)
                gsub(/<!--/, "<\001!--", sp); gsub(/-->/, "-\001->", sp)
                out = out substr(s, 1, RSTART - 1) sp
                s = substr(s, RSTART + RLENGTH)
            }
            return out s
        }
        function clip(t,    i) {
            if (length(t) <= 80) return t
            for (i = 81; i > 1; i--) if (substr(t, i, 1) == " ") return substr(t, 1, i - 1) "..."
            return t
        }
        FNR == 1 { flush(); fm = 0; cm = 0; fence = 0; fch = ""; flen = 0 }
        {
            raw = $0
            sub(/\r$/, "", raw)
            if (FNR == 1 && raw == "---") { fm = 1; next }
            if (fm) { if (raw == "---") fm = 0; next }
            if (cm) {
                e = index(raw, "-->")
                if (e == 0) { flush(); next }
                raw = substr(raw, e + 3); cm = 0
            } else if (fence) {
                flush()
                t = raw; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t)
                if (substr(t, 1, 1) == fch && t ~ /^(`+|~+)$/ && length(t) >= flen) fence = 0
                next
            } else if (raw ~ /^[ \t]*```+[^`]*$/ || raw ~ /^[ \t]*~~~+/) {
                flush()
                t = raw; sub(/^[ \t]+/, "", t)
                fch = substr(t, 1, 1); flen = 0
                while (substr(t, flen + 1, 1) == fch) flen++
                fence = 1
                next
            }
            raw = mask(raw)
            while ((st = index(raw, "<!--")) > 0) {
                rest = substr(raw, st + 4); e = index(rest, "-->")
                if (e == 0) { raw = substr(raw, 1, st - 1); cm = 1; break }
                raw = substr(raw, 1, st - 1) " " substr(rest, e + 3)
            }
            gsub(/\001/, "", raw)
            if (raw ~ /^[ \t]*$/) { flush(); next }
            if (raw ~ /^[ \t]*\|?[ \t:|-]+\|?[ \t]*$/ && raw ~ /-/) { pk = ""; next }
            flush()
            line = raw
            sub(/^[ \t]*(>[ \t]*)*/, "", line)
            sub(/^([-*+]|[0-9]+[.)])[ \t]+/, "", line)
            gsub(/[ \t]+/, " ", line)
            sub(/^ /, "", line); sub(/ $/, "", line)
            if (line !~ /^#/ && length(line) >= 40) { pk = line; pf = FILENAME; pl = FILENAME ":" FNR }
            code = raw
            gsub(/``[^`]*(`[^`]+)*``|`[^`]*`/, "", code)
            if (code ~ /NEEDS REVIEW($|[^A-Za-z0-9_])/) mk[++m] = "WARN:  " FILENAME ":" FNR " unresolved marker NEEDS REVIEW"
            else if (code ~ /(^|[^A-Za-z0-9_.\/-])TODO($|[^A-Za-z0-9_.\/-]|\.($|[])} \t"\047,;:]))/) mk[++m] = "WARN:  " FILENAME ":" FNR " unresolved marker TODO"
        }
        END {
            flush()
            for (i = 1; i <= n; i++) {
                k = order[i]
                if (cnt[k] >= 2) print "WARN:  " first[k] " duplicate line in " cnt[k] " files (also " locs[k] "): " clip(k)
            }
            for (i = 1; i <= m; i++) print mk[i]
        }
    ' "${dup_files[@]}" 2>/dev/null)"
    dup_rc=$?
    if [ "$dup_rc" -ne 0 ]; then
        emit "ERROR: $MEMORY_DIR lint rules 17/18 could not scan memory files (awk exit $dup_rc)"
    elif [ -n "$dup_out" ]; then
        while IFS= read -r finding; do
            emit "$finding"
        done <<EOF
$dup_out
EOF
    fi
fi

if [ "$FOUND" -eq 0 ]; then
    echo "lint-memory: clean (no warnings or errors)"
    exit 0
fi
exit 1
