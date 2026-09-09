#!/usr/bin/env bash
#
# initiative-status.sh — derive an initiative readiness table from local files.
#
# software_adw mapping: no plan pointer -> not-started; plan status draft ->
# plan; in_progress -> implement; done or an archived plan -> complete; a
# missing project memory, repo_path checkout, or resolvable plan -> unknown.
# The table is intentionally hand-derivable: it reads only the initiative,
# project memory, plan, and todo files; it makes no network or provider calls.
#
# Snapshot format: initiatives/.state/<slug>.snapshot has one comment header,
# then '<target-id> <derived-stage>' for every software_adw Target and one
# 'stream-entries <count>' line. It is hand-editable: update those lines to
# acknowledge the current state without running this script.
#
# Usage: initiative-status.sh [--ack] <slug>

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/_lib.sh"

usage() {
    echo "usage: initiative-status.sh [--ack] <slug>" >&2
    exit 2
}

ACK=0
case "$#" in
    1) SLUG="$1" ;;
    2)
        [ "$1" = "--ack" ] || usage
        ACK=1
        SLUG="$2"
        ;;
    *) usage ;;
esac
INITIATIVE="$MEMORY_DIR/initiatives/$SLUG.md"

[ -f "$INITIATIVE" ] || { echo "initiative-status: initiative not found: $INITIATIVE" >&2; exit 1; }
[ "$(extract_fm_field "$INITIATIVE" kind)" = "initiative" ] || {
    echo "initiative-status: invalid initiative file (kind must be initiative): $INITIATIVE" >&2
    exit 1
}
[ "$(extract_fm_field "$INITIATIVE" slug)" = "$SLUG" ] || {
    echo "initiative-status: invalid initiative file (slug does not match filename): $INITIATIVE" >&2
    exit 1
}
case "$(extract_fm_field "$INITIATIVE" status)" in
    active|closed) ;;
    *)
        echo "initiative-status: invalid initiative file (status must be active or closed): $INITIATIVE" >&2
        exit 1
        ;;
esac
[ -n "$(extract_fm_field "$INITIATIVE" created)" ] || {
    echo "initiative-status: invalid initiative file (created is required): $INITIATIVE" >&2
    exit 1
}

target_ids=()
target_modes=()
target_stages=()
target_depends=()
target_plans=()
target_actors=()
target_statuses=()
sep=$(printf '\034')

# Keep the Targets boundaries and headings aligned with lint-memory.sh rule 11.
while IFS="$sep" read -r target_id target_mode target_stages_value target_depends_on target_plan target_actor target_status; do
    [ -n "$target_id" ] || continue
    target_ids[${#target_ids[@]}]="$target_id"
    target_modes[${#target_modes[@]}]="$target_mode"
    target_stages[${#target_stages[@]}]="$target_stages_value"
    target_depends[${#target_depends[@]}]="$target_depends_on"
    target_plans[${#target_plans[@]}]="$target_plan"
    target_actors[${#target_actors[@]}]="$target_actor"
    target_statuses[${#target_statuses[@]}]="$target_status"
done < <(
    awk -v sep="$sep" '
        /^## Targets[[:space:]]*$/ { in_targets = 1; next }
        in_targets && /^## / { exit }
        in_targets && /^### / {
            if (have_target) print target sep mode sep stages sep depends sep plan sep actor sep status
            target = substr($0, 5); mode = ""; stages = ""; depends = ""; plan = ""; actor = ""; status = ""; have_target = 1; next
        }
        in_targets && have_target && /^- execution_mode: / { mode = $0; sub(/^- execution_mode: /, "", mode); next }
        in_targets && have_target && /^- stages: / { stages = $0; sub(/^- stages: /, "", stages); next }
        in_targets && have_target && /^- depends_on: / { depends = $0; sub(/^- depends_on: /, "", depends); next }
        in_targets && have_target && /^- plan: / { plan = $0; sub(/^- plan: /, "", plan); next }
        in_targets && have_target && /^- next_actor: / { actor = $0; sub(/^- next_actor: /, "", actor); next }
        in_targets && have_target && /^- status: / { status = $0; sub(/^- status: /, "", status) }
        END { if (in_targets && have_target) print target sep mode sep stages sep depends sep plan sep actor sep status }
    ' "$INITIATIVE"
)

[ "${#target_ids[@]}" -gt 0 ] || { echo "initiative-status: invalid initiative file (no Targets): $INITIATIVE" >&2; exit 1; }

trim() { printf '%s\n' "$1" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//'; }

target_index() {
    local wanted="$1" i=0
    while [ "$i" -lt "${#target_ids[@]}" ]; do
        [ "${target_ids[$i]}" = "$wanted" ] && { printf '%s\n' "$i"; return 0; }
        i=$((i + 1))
    done
    return 1
}

stage_position() {
    local stages="$1" wanted="$2" remaining stage pos=0
    remaining="$stages"
    while [ -n "$remaining" ]; do
        case "$remaining" in
            *'->'*) stage=${remaining%%'->'*}; remaining=${remaining#*'->'} ;;
            *) stage="$remaining"; remaining="" ;;
        esac
        stage="$(trim "$stage")"
        [ "$stage" = "$wanted" ] && { printf '%s\n' "$pos"; return 0; }
        pos=$((pos + 1))
    done
    return 1
}

resolve_checkout() {
    local project="$1" mf rp cand pin backpin
    mf="$MEMORY_DIR/projects/$project/memory.md"
    [ -f "$mf" ] || { RESOLVE_REASON="project memory missing"; return 1; }
    rp="$(extract_fm_field "$mf" repo_path)"
    [ -n "$rp" ] || { RESOLVE_REASON="repo_path missing"; return 1; }
    case "$rp" in
        '$MEMORY_DIR') cand="$MEMORY_DIR" ;;
        '$MEMORY_DIR/'*) cand="$MEMORY_DIR/${rp#\$MEMORY_DIR/}" ;;
        /*) cand="$rp" ;;
        *) cand="$(projects_root)/$rp" ;;
    esac
    [ -d "$cand" ] || { RESOLVE_REASON="checkout missing: $cand"; return 1; }
    pin="$cand/.agents/memory-project"
    [ -f "$pin" ] || pin="$cand/.claude/memory-project"
    [ -f "$pin" ] || { RESOLVE_REASON="checkout back-pin missing: $cand"; return 1; }
    backpin="$(head -n1 "$pin" | tr -d '[:space:]')"
    [ "$backpin" = "$project" ] || { RESOLVE_REASON="checkout back-pin is '$backpin', expected '$project'"; return 1; }
    RESOLVE_REASON=""
    return 0
}

todo_counts() {
    local todo="$1" plan_rel="$2"
    [ -f "$todo" ] || { printf 'todo missing'; return; }
    awk -v p="$plan_rel" '
        /^### / { if (active) exit }
        index($0, "(" p ")") { active = 1 }
        active && /^[[:space:]]*- \[ \]/ { open++ }
        active && /^[[:space:]]*- \[x\]/ { done++ }
        END { if (active) printf "todo: %d open, %d done", open + 0, done + 0; else printf "todo: no linked section" }
    ' "$todo"
}

derived=()
evidence=()
for i in "${!target_ids[@]}"; do
    mode="${target_modes[$i]}"
    if [ "$mode" != "software_adw" ]; then
        if [ -n "${target_statuses[$i]}" ]; then
            derived[${#derived[@]}]="${target_statuses[$i]}"
            evidence[${#evidence[@]}]="asserted in initiative"
        else
            derived[${#derived[@]}]="no status asserted"
            evidence[${#evidence[@]}]="no - status: line"
        fi
        continue
    fi

    plan_pointer="${target_plans[$i]}"
    if [ -z "$plan_pointer" ]; then
        derived[${#derived[@]}]="not-started"
        evidence[${#evidence[@]}]="no plan pointer"
        continue
    fi

    target_project="${target_ids[$i]%%/*}"
    if ! resolve_checkout "$target_project"; then
        derived[${#derived[@]}]="unknown"
        evidence[${#evidence[@]}]="$RESOLVE_REASON"
        continue
    fi

    expected="projects/$target_project/plans/"
    case "$plan_pointer" in
        "$expected"*.md) plan_name="${plan_pointer#"$expected"}" ;;
        *)
            derived[${#derived[@]}]="unknown"
            evidence[${#evidence[@]}]="plan pointer unresolvable: $plan_pointer"
            continue
            ;;
    esac
    plan_file="$MEMORY_DIR/$plan_pointer"
    archived="$MEMORY_DIR/projects/$target_project/archive/plans/$plan_name"
    if [ -f "$archived" ]; then
        derived[${#derived[@]}]="complete"
        evidence[${#evidence[@]}]="archived plan: projects/$target_project/archive/plans/$plan_name; $(todo_counts "$MEMORY_DIR/projects/$target_project/todo.md" "plans/$plan_name")"
        continue
    fi
    if [ ! -f "$plan_file" ]; then
        derived[${#derived[@]}]="unknown"
        evidence[${#evidence[@]}]="plan missing: $plan_pointer"
        continue
    fi
    plan_status="$(extract_fm_field "$plan_file" status)"
    todo_evidence="$(todo_counts "$MEMORY_DIR/projects/$target_project/todo.md" "plans/$plan_name")"
    case "$plan_status" in
        draft) derived[${#derived[@]}]="plan" ;;
        in_progress) derived[${#derived[@]}]="implement" ;;
        done) derived[${#derived[@]}]="complete" ;;
        *)
            derived[${#derived[@]}]="unknown"
            evidence[${#evidence[@]}]="plan status unparseable: ${plan_status:-missing}; $todo_evidence"
            continue
            ;;
    esac
    evidence[${#evidence[@]}]="plan status: $plan_status; $todo_evidence"
done

# Snapshot-based staleness is deliberately separate from derivation above so a
# caller can reuse this exact comparison and snapshot format without forking it.
stream_entry_count() {
    awk '
        /^## Decision stream[[:space:]]*$/ { in_stream = 1; next }
        in_stream && /^## / { exit }
        in_stream && /^- D[0-9A-Za-z]*/ { count++ }
        END { print count + 0 }
    ' "$INITIATIVE"
}

STATE_DIR="$MEMORY_DIR/initiatives/.state"
SNAPSHOT="$STATE_DIR/$SLUG.snapshot"
snapshot_ids=()
snapshot_stages=()
snapshot_stream_count=""

read_snapshot() {
    local line snapshot_id snapshot_stage
    [ -f "$SNAPSHOT" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            \#*|'') continue ;;
            'stream-entries '*) snapshot_stream_count=${line#stream-entries } ;;
            *' '*)
                snapshot_id=${line%% *}
                snapshot_stage=${line#* }
                [ -n "$snapshot_id" ] && [ -n "$snapshot_stage" ] || continue
                snapshot_ids[${#snapshot_ids[@]}]="$snapshot_id"
                snapshot_stages[${#snapshot_stages[@]}]="$snapshot_stage"
                ;;
        esac
    done < "$SNAPSHOT"
}

snapshot_stage_for() {
    local wanted="$1" j=0
    while [ "$j" -lt "${#snapshot_ids[@]}" ]; do
        if [ "${snapshot_ids[$j]}" = "$wanted" ]; then
            printf '%s\n' "${snapshot_stages[$j]}"
            return 0
        fi
        j=$((j + 1))
    done
    return 1
}

write_snapshot() {
    local tmp j
    mkdir -p "$STATE_DIR" || {
        echo "initiative-status: cannot create snapshot directory: $STATE_DIR" >&2
        exit 1
    }
    tmp="$SNAPSHOT.tmp.$$"
    {
        printf '%s\n' '# initiative-status snapshot: <target-id> <derived-stage> per software_adw Target; stream-entries <count>. Hand-edit these lines to acknowledge current state.'
        for j in "${!target_ids[@]}"; do
            [ "${target_modes[$j]}" = "software_adw" ] || continue
            printf '%s %s\n' "${target_ids[$j]}" "${derived[$j]}"
        done
        printf 'stream-entries %s\n' "$stream_entries"
    } > "$tmp" || {
        rm -f "$tmp"
        echo "initiative-status: cannot write snapshot: $SNAPSHOT" >&2
        exit 1
    }
    mv "$tmp" "$SNAPSHOT" || {
        rm -f "$tmp"
        echo "initiative-status: cannot update snapshot: $SNAPSHOT" >&2
        exit 1
    }
}

snapshot_exists=0
if read_snapshot; then
    snapshot_exists=1
fi
stream_entries="$(stream_entry_count)"
stale_ids=()
stale_old_stages=()
stale_new_stages=()

if [ "$snapshot_exists" -eq 1 ] && [ "$stream_entries" = "$snapshot_stream_count" ]; then
    for i in "${!target_ids[@]}"; do
        [ "${target_modes[$i]}" = "software_adw" ] || continue
        old_stage="$(snapshot_stage_for "${target_ids[$i]}")" || old_stage=""
        if [ -n "$old_stage" ] && [ "$old_stage" != "${derived[$i]}" ]; then
            stale_ids[${#stale_ids[@]}]="${target_ids[$i]}"
            stale_old_stages[${#stale_old_stages[@]}]="$old_stage"
            stale_new_stages[${#stale_new_stages[@]}]="${derived[$i]}"
        fi
    done
fi

if [ "$snapshot_exists" -eq 0 ] || [ "$stream_entries" != "$snapshot_stream_count" ] || [ "$ACK" -eq 1 ]; then
    write_snapshot
fi

dependency_cells=()
warnings=()
for i in "${!target_ids[@]}"; do
    remaining="${target_depends[$i]}"
    if [ -z "$remaining" ] || [ "$remaining" = "none" ]; then
        dependency_cells[${#dependency_cells[@]}]="none — n/a"
        continue
    fi
    cell=""
    while [ -n "$remaining" ]; do
        case "$remaining" in
            *,*) dependency=${remaining%%,*}; remaining=${remaining#*,} ;;
            *) dependency="$remaining"; remaining="" ;;
        esac
        dependency="$(trim "$dependency")"
        dependency_id="$(printf '%s\n' "$dependency" | sed 's/[[:space:]]*(stage: [^)]*)[[:space:]]*$//')"
        wanted_stage=""
        case "$dependency" in
            *'(stage: '*) wanted_stage=${dependency#*'(stage: '}; wanted_stage=${wanted_stage%')'} ;;
        esac
        dep_index="$(target_index "$dependency_id")" || dep_index=""
        result="unsatisfied (unknown)"
        if [ -n "$dep_index" ]; then
            if [ -n "$wanted_stage" ]; then
                wanted_position="$(stage_position "${target_stages[$dep_index]}" "$wanted_stage")" || wanted_position=""
                if [ -z "$wanted_position" ]; then
                    warnings[${#warnings[@]}]="Target '${target_ids[$i]}' depends on undeclared stage '$wanted_stage' of '$dependency_id'"
                fi
            fi
            if [ "${derived[$dep_index]}" = "complete" ]; then
                result="satisfied"
            elif [ "${target_modes[$dep_index]}" = "interactive" ]; then
                case "${target_statuses[$dep_index]}" in
                    done*) result="satisfied" ;;
                esac
            elif [ -n "$wanted_stage" ]; then
                derived_position="$(stage_position "${target_stages[$dep_index]}" "${derived[$dep_index]}")" || derived_position=""
                if [ -n "$wanted_position" ] && [ -n "$derived_position" ]; then
                    # Both positions known: this is a determinate verdict, not
                    # a fail-closed one — label it so unknown keeps meaning
                    # "underivable".
                    if [ "$derived_position" -ge "$wanted_position" ]; then
                        result="satisfied"
                    else
                        result="unsatisfied (at ${derived[$dep_index]}, needs $wanted_stage)"
                    fi
                fi
            fi
        fi
        [ -n "$cell" ] && cell="$cell; "
        cell="$cell$dependency — $result"
    done
    dependency_cells[${#dependency_cells[@]}]="$cell"
done

escape_cell() { printf '%s' "$1" | sed 's/|/\\|/g'; }

printf '# Initiative readiness — %s\n\n' "$SLUG"
printf '| id | execution_mode | derived stage/status | evidence | depends_on + satisfied? | next_actor |\n'
printf '|---|---|---|---|---|---|\n'
for i in "${!target_ids[@]}"; do
    printf '| %s | %s | %s | %s | %s | %s |\n' \
        "$(escape_cell "${target_ids[$i]}")" \
        "$(escape_cell "${target_modes[$i]}")" \
        "$(escape_cell "${derived[$i]}")" \
        "$(escape_cell "${evidence[$i]}")" \
        "$(escape_cell "${dependency_cells[$i]}")" \
        "$(escape_cell "${target_actors[$i]:-none}")"
done
if [ "${#warnings[@]}" -gt 0 ]; then
    printf '\n'
    for warning in "${warnings[@]}"; do
        printf '> WARNING: %s\n' "$warning"
    done
fi
if [ "$ACK" -eq 1 ]; then
    printf '\n## Snapshot acknowledged\n\n'
    printf 'Acknowledged %s at %s decision-stream entries.\n' "$SLUG" "$stream_entries"
elif [ "${#stale_ids[@]}" -gt 0 ]; then
    printf '\n## Stale targets\n\n'
    for i in "${!stale_ids[@]}"; do
        printf 'WARN: %s advanced (%s -> %s) with no new decision-stream entry — append the missing D<n>-proposed entry or ack\n' \
            "${stale_ids[$i]}" "${stale_old_stages[$i]}" "${stale_new_stages[$i]}"
    done
fi
