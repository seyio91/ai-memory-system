#!/usr/bin/env bash
# initiative-status.sh derives only from sandbox-local memory/checkouts.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"; ROOT="$(new_sandbox)"
trap 'rm -rf "$MEM" "$ROOT"' EXIT
export MEMORY_DIR="$MEM" AI_MEMORY_PROJECTS_ROOT="$ROOT"
SCRIPT="$SCRIPTS_DIR/initiative-status.sh"

mkdir -p "$MEM/initiatives" "$MEM/projects/alpha/plans" "$MEM/projects/alpha/archive/plans" "$MEM/projects/beta/plans" "$MEM/projects/beta/archive/plans" "$MEM/projects/ghost" "$ROOT/alpha-co/.agents" "$ROOT/beta-co/.agents"
printf 'alpha\n' > "$ROOT/alpha-co/.agents/memory-project"
printf 'beta\n' > "$ROOT/beta-co/.agents/memory-project"
cat > "$MEM/projects/alpha/memory.md" <<'EOF'
---
topic: alpha
scope: project
summary: alpha
repo_path: alpha-co
---
EOF
cat > "$MEM/projects/beta/memory.md" <<'EOF'
---
topic: beta
scope: project
summary: beta
repo_path: beta-co
---
EOF
cat > "$MEM/projects/ghost/memory.md" <<'EOF'
---
topic: ghost
scope: project
summary: ghost
repo_path: absent-checkout
---
EOF
cat > "$MEM/projects/alpha/todo.md" <<'EOF'
### work → [plan](plans/draft.md)
- [ ] pending
- [x] done
EOF
printf '# Todo\n' > "$MEM/projects/beta/todo.md"

# plan_tr <status> <slug> <task_ref> <path> — a plan carrying a task_ref, for
# the task-keyed join (find_task_plans matches this field, never the filename).
plan_tr() { printf '%s\n' '---' "plan: $2" "status: $1" "task_ref: $3" '---' > "$4"; }
plan_tr draft draft t-draft-001 "$MEM/projects/alpha/plans/draft.md"
plan_tr in_progress progress t-progress-001 "$MEM/projects/alpha/plans/progress.md"
plan_tr "done" "done" t-done-001 "$MEM/projects/alpha/plans/done.md"
plan_tr draft archived t-archived-001 "$MEM/projects/alpha/archive/plans/archived.md"
plan_tr in_progress task-live-plan task-live-001 "$MEM/projects/alpha/plans/task-live-plan.md"
# Archived under a name unrelated to its task_ref — proves the join resolves
# by task_ref even when the archived plan was renamed on disk.
plan_tr draft renamed-on-disk task-archived-001 "$MEM/projects/alpha/archive/plans/renamed-on-disk.md"
plan_tr draft dup-a task-dup-001 "$MEM/projects/alpha/plans/dup-a.md"
plan_tr draft dup-b task-dup-001 "$MEM/projects/alpha/plans/dup-b.md"

cat > "$MEM/initiatives/ready.md" <<'EOF'
---
kind: initiative
slug: ready
status: active
created: 2026-08-14
---
# Ready
## Targets
### alpha/no-plan
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: none
- next_actor: human
### alpha/draft
- execution_mode: software_adw
- task: t-draft-001
- stages: discover -> plan -> implement -> validate
- depends_on: none
### alpha/progress
- execution_mode: software_adw
- task: t-progress-001
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/draft (stage: plan)
### alpha/done
- execution_mode: software_adw
- task: t-done-001
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/progress (stage: implement)
### alpha/archived
- execution_mode: software_adw
- task: t-archived-001
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/done (stage: validate)
### beta/interactive
- execution_mode: interactive
- depends_on: none
- status: done (asserted by test)
### beta/by-complete
- execution_mode: software_adw
- task: t-missing-001
- stages: discover -> plan -> implement
- depends_on: alpha/done (stage: not-real)
### beta/by-interactive
- execution_mode: software_adw
- task: t-missing-001
- stages: discover -> plan -> implement
- depends_on: beta/interactive
### beta/unknown-dependent
- execution_mode: software_adw
- task: t-missing-001
- stages: discover -> plan -> implement
- depends_on: beta/by-complete (stage: implement)
### ghost/missing-checkout
- execution_mode: software_adw
- task: t-ghost-001
- stages: discover -> plan
- depends_on: none
### alpha/bad-stage
- execution_mode: software_adw
- task: t-draft-001
- stages: discover -> plan -> implement
- depends_on: alpha/progress (stage: release)
### beta/behind
- execution_mode: software_adw
- task: t-missing-001
- stages: discover -> plan -> implement
- depends_on: alpha/draft (stage: implement)
### alpha/task-live
- execution_mode: software_adw
- task: task-live-001
- stages: discover -> plan -> implement -> validate
- depends_on: none
### alpha/task-archived
- execution_mode: software_adw
- task: task-archived-001
- stages: discover -> plan -> implement -> validate
- depends_on: none
### alpha/task-not-started
- execution_mode: software_adw
- task: task-missing-001
- stages: discover -> plan -> implement -> validate
- depends_on: none
### alpha/task-duplicate
- execution_mode: software_adw
- task: task-dup-001
- stages: discover -> plan -> implement
- depends_on: none
### ghost/task-missing-checkout
- execution_mode: software_adw
- task: task-ghost-001
- stages: discover -> plan
- depends_on: none
### alpha/frozen-done
- execution_mode: software_adw
- task: task-should-be-ignored
- stages: discover -> plan -> implement -> validate
- depends_on: none
- status: done (frozen; lookup must not run)
### alpha/frozen-closed
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: none
- status: closed (frozen; lookup must not run)
### alpha/dep-on-frozen-done-stage
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/frozen-done (stage: implement)
- next_actor: human
### alpha/dep-on-frozen-done-plain
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/frozen-done
- next_actor: human
### alpha/dep-on-frozen-closed-stage
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/frozen-closed (stage: implement)
- next_actor: human
### alpha/dep-on-live-task-stage
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/task-live (stage: implement)
- next_actor: human
## Closure
Open.
EOF

out="$(bash "$SCRIPT" ready 2>&1)"; rc=$?
assert_exit 0 "$rc" "ready initiative exits 0"
assert_contains "$out" "| alpha/no-plan | software_adw | not-started | no task pointer" "no task and no plan maps to not-started"
assert_contains "$out" "| alpha/draft | software_adw | plan | plan: projects/alpha/plans/draft.md; plan status: draft; todo: 1 open, 1 done" "draft maps to plan with todo counts"
assert_contains "$out" "| alpha/progress | software_adw | implement | plan: projects/alpha/plans/progress.md; plan status: in_progress" "in_progress maps to implement"
assert_contains "$out" "| alpha/done | software_adw | complete | plan: projects/alpha/plans/done.md; plan status: done" "done maps to complete"
assert_contains "$out" "| alpha/archived | software_adw | complete | archived plan:" "archived plan maps to complete"
assert_contains "$out" "| beta/interactive | interactive | done (asserted by test) | asserted in initiative" "interactive echoes asserted status"
assert_contains "$out" "| alpha/task-live | software_adw | implement | plan: projects/alpha/plans/task-live-plan.md; plan status: in_progress" "task join finds live plan and maps its status"
assert_contains "$out" "| alpha/task-archived | software_adw | complete | archived plan: projects/alpha/archive/plans/renamed-on-disk.md" "task join finds an archived plan renamed on disk (filename matching would lose this)"
assert_contains "$out" "| alpha/task-not-started | software_adw | not-started | task task-missing-001: no plan carries it" "task with no plan anywhere is not-started"
assert_contains "$out" "| alpha/task-duplicate | software_adw | unknown |" "duplicate task match fails closed to unknown"
assert_contains "$out" "multiple live plans carry it: projects/alpha/plans/dup-a.md, projects/alpha/plans/dup-b.md" "duplicate-match evidence names every matching path"
assert_contains "$out" "| ghost/task-missing-checkout | software_adw | unknown | checkout missing:" "missing checkout via the task path is unknown with reason, same as the plan path"
assert_contains "$out" "| alpha/frozen-done | software_adw | done (frozen; lookup must not run) | asserted in initiative" "terminal 'done' short-circuits software_adw even with a task present"
assert_contains "$out" "| alpha/frozen-closed | software_adw | closed (frozen; lookup must not run) | asserted in initiative" "terminal 'closed' short-circuits software_adw with no lookup"
assert_contains "$out" "alpha/draft (stage: plan) — satisfied" "dependency satisfied by stage position"
assert_contains "$out" "alpha/done (stage: not-real) — satisfied" "complete dependency is satisfied"
assert_contains "$out" "beta/interactive — satisfied" "asserted-done interactive dependency is satisfied"
assert_contains "$out" "beta/by-complete (stage: implement) — unsatisfied (unknown)" "unknown dependency fails closed"
assert_contains "$out" "alpha/draft (stage: implement) — unsatisfied (at plan, needs implement)" "determinate shortfall labeled, not conflated with unknown"
assert_contains "$out" "checkout missing:" "missing project checkout is unknown with reason"
assert_contains "$out" "WARNING: Target 'alpha/bad-stage' depends on undeclared stage 'release'" "undeclared stage emits warning"

# REGRESSION (dependency-satisfaction fix): a terminal `done` assertion on a
# software_adw Target must satisfy a dependent's dependency mode-agnostically —
# a frozen Target has no derivable stage, so this must not be gated on
# execution_mode being interactive. Freezing a software_adw Target used to
# break exactly the stage-qualified case below.
assert_contains "$out" "alpha/frozen-done (stage: implement) — satisfied" "(a) frozen software_adw done satisfies a STAGE-QUALIFIED dependency"
assert_contains "$out" "alpha/frozen-done — satisfied" "(b) frozen software_adw done satisfies an unqualified dependency"
# (c) `closed` deliberately never satisfies, frozen or not — an abandoned
# prerequisite must not unblock its dependents.
assert_contains "$out" "alpha/frozen-closed (stage: implement) — unsatisfied (unknown)" "(c) frozen software_adw closed does NOT satisfy a dependency"
# (d) a non-frozen software_adw Target (task-joined, not asserted) still
# resolves a stage-qualified dependency through ordinary stage comparison —
# proving the mode-agnostic fix did not shortcut this existing path.
assert_contains "$out" "alpha/task-live (stage: implement) — satisfied" "(d) non-frozen software_adw dependency still resolves via normal stage comparison"

missing="$(bash "$SCRIPT" absent 2>&1)"; rc=$?
assert_exit 1 "$rc" "missing initiative exits nonzero"
assert_contains "$missing" "initiative not found" "missing initiative names reason"

sed -e 's/^slug: ready$/slug: invalid/' -e 's/^status: active$/status: invalid/' "$MEM/initiatives/ready.md" > "$MEM/initiatives/invalid.md"
invalid="$(bash "$SCRIPT" invalid 2>&1)"; rc=$?
assert_exit 1 "$rc" "invalid initiative exits nonzero"
assert_contains "$invalid" "status must be active or closed" "invalid initiative names status contract"

# Snapshot staleness must persist until a decision-stream append or explicit ack.
snapshot="$MEM/initiatives/.state/ready.snapshot"
assert_file "$snapshot" "first run writes a snapshot"
assert_not_contains "$out" "## Stale targets" "first run reports no stale Targets"

plan_tr in_progress draft t-draft-001 "$MEM/projects/alpha/plans/draft.md"
stale="$(bash "$SCRIPT" ready 2>&1)"; rc=$?
assert_exit 0 "$rc" "advanced Target exits 0 with warning"
assert_contains "$stale" "WARN: alpha/draft advanced (plan -> implement) with no new decision-stream entry" "advanced Target is stale without a stream entry"
# The remedy names a DECISION id, not the Target id — the vocabulary the doctrine, docs and
# breadcrumb rows all use. Pinned because this line is read at session start, not just on the CLI.
assert_contains "$stale" "append the missing D<n>-proposed entry or ack" "stale warning names the decision-id remedy"
assert_not_contains "$stale" "alpha/draft-proposed" "stale warning does not glue -proposed onto the Target id"

stale_again="$(bash "$SCRIPT" ready 2>&1)"; rc=$?
assert_exit 0 "$rc" "repeated stale run exits 0"
assert_contains "$stale_again" "WARN: alpha/draft advanced (plan -> implement) with no new decision-stream entry" "stale warning persists without snapshot rewrite"

cat >> "$MEM/initiatives/ready.md" <<'EOF'
## Decision stream
- D9-proposed: alpha/draft advanced for this seeded test.
EOF
after_stream="$(bash "$SCRIPT" ready 2>&1)"; rc=$?
assert_exit 0 "$rc" "stream append exits 0"
assert_not_contains "$after_stream" "## Stale targets" "stream append silences stale warning"
snapshot_after_stream="$(cat "$snapshot")"
assert_contains "$snapshot_after_stream" "alpha/draft implement" "stream append refreshes Target snapshot"
assert_contains "$snapshot_after_stream" "stream-entries 1" "stream append refreshes stream count"

plan_tr "done" draft t-draft-001 "$MEM/projects/alpha/plans/draft.md"
before_ack="$(bash "$SCRIPT" ready 2>&1)"; rc=$?
assert_exit 0 "$rc" "stale Target before ack exits 0"
assert_contains "$before_ack" "WARN: alpha/draft advanced (implement -> complete) with no new decision-stream entry" "second advance is stale before ack"
acked="$(bash "$SCRIPT" --ack ready 2>&1)"; rc=$?
assert_exit 0 "$rc" "ack exits 0"
assert_contains "$acked" "## Snapshot acknowledged" "ack reports what it acknowledged"
assert_not_contains "$acked" "## Stale targets" "ack silences stale warning"

fresh="$(bash "$SCRIPT" ready 2>&1)"; rc=$?
assert_exit 0 "$rc" "unchanged stages exit 0"
assert_not_contains "$fresh" "advanced" "unchanged Target is never stale"

plan_tr "done" progress t-progress-001 "$MEM/projects/alpha/plans/progress.md"
interactive_guard="$(bash "$SCRIPT" ready 2>&1)"; rc=$?
assert_exit 0 "$rc" "interactive guard run exits 0"
assert_contains "$interactive_guard" "WARN: alpha/progress advanced (implement -> complete) with no new decision-stream entry" "software Target still reports stale"
assert_not_contains "$interactive_guard" "beta/interactive advanced" "interactive Target never appears stale"

finish
