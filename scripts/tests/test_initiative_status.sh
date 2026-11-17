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
- status: open · next: exec — start planning · blocked_by: none
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
- status: done
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
- status: done
### alpha/frozen-closed
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: none
- status: closed
### alpha/dep-on-frozen-done-stage
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/frozen-done (stage: implement)
### alpha/dep-on-frozen-done-plain
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/frozen-done
### alpha/dep-on-frozen-closed-stage
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/frozen-closed (stage: implement)
### alpha/dep-on-live-task-stage
- execution_mode: software_adw
- stages: discover -> plan -> implement -> validate
- depends_on: alpha/task-live (stage: implement)
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
assert_contains "$out" "| beta/interactive | interactive | done | asserted in initiative" "interactive echoes asserted status"
assert_contains "$out" "| alpha/task-live | software_adw | implement | plan: projects/alpha/plans/task-live-plan.md; plan status: in_progress" "task join finds live plan and maps its status"
assert_contains "$out" "| alpha/task-archived | software_adw | complete | archived plan: projects/alpha/archive/plans/renamed-on-disk.md" "task join finds an archived plan renamed on disk (filename matching would lose this)"
assert_contains "$out" "| alpha/task-not-started | software_adw | not-started | task task-missing-001: no plan carries it" "task with no plan anywhere is not-started"
assert_contains "$out" "| alpha/task-duplicate | software_adw | unknown |" "duplicate task match fails closed to unknown"
assert_contains "$out" "multiple live plans carry it: projects/alpha/plans/dup-a.md, projects/alpha/plans/dup-b.md" "duplicate-match evidence names every matching path"
assert_contains "$out" "| ghost/task-missing-checkout | software_adw | unknown | checkout missing:" "missing checkout via the task path is unknown with reason, same as the plan path"
assert_contains "$out" "| alpha/frozen-done | software_adw | done | asserted in initiative" "terminal 'done' short-circuits software_adw even with a task present"
assert_contains "$out" "| alpha/frozen-closed | software_adw | closed | asserted in initiative" "terminal 'closed' short-circuits software_adw with no lookup"
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
assert_contains "$stale" "append the missing D<n> proposed <date> entry with an unconfirmed: line, or ack" "stale warning names the decision-id remedy"
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

# Derived proposed-decision count: `Decisions: N proposed (K legacy), oldest M days`.
# mk_dec <slug> <frontmatter-extra> <stream-body> — minimal initiative with a stream.
mk_dec() {
    {
        printf '%s\n' '---' 'kind: initiative' "slug: $1" 'status: active' 'created: 2026-01-01'
        [ -n "$2" ] && printf '%s\n' "$2"
        printf '%s\n' '---' '# Dec' '## Targets' '### beta/x' '- execution_mode: interactive' '- depends_on: none' '- status: open · next: s — go · blocked_by: none' '## Decision stream'
        printf '%s\n' "$3"
        printf '%s\n' '## Closure' 'Open.'
    } > "$MEM/initiatives/$1.md"
}
dec_line() { INITIATIVE_STATUS_TODAY=2026-10-18 bash "$SCRIPT" "$1" 2>&1 | grep '^Decisions:'; }

mk_dec d-new '' '- D1 proposed 2026-10-08 — a
  unconfirmed: x
- D2 confirmed 2026-10-01 — b
  evidence: y
- D3b proposed 2026-10-13 — c
  unconfirmed: z'
assert_eq "Decisions: 2 proposed (0 legacy), oldest 10 days" "$(dec_line d-new)" "new shape: counts field-shape proposed, oldest age from fixed TODAY"

mk_dec d-old '' '- D1-proposed: a
- D2-proposed [2026-10-01]: b
- D3: c'
assert_eq "Decisions: 0 proposed (0 legacy)" "$(dec_line d-old)" "old shape: -proposed heads are not counted"

mk_dec d-mixed '' '- D1-proposed: old
- D2 proposed 2026-10-17 — new
  unconfirmed: x
- D3 rejected 2026-10-01 — r'
assert_eq "Decisions: 1 proposed (0 legacy), oldest 1 days" "$(dec_line d-mixed)" "mixed shapes: only field-shape proposed counted"

mk_dec d-leg 'legacy_through: D3' '- D1 proposed — undated legacy
- D3 proposed 2026-01-01 — dated legacy
- D3b proposed 2026-10-16 — lettered is never legacy
  unconfirmed: x
- D4 proposed 2026-10-14 — above the mark
  unconfirmed: x'
assert_eq "Decisions: 4 proposed (2 legacy), oldest 4 days" "$(dec_line d-leg)" "legacy_through: legacy counted in K, excluded from age, lettered id never legacy"

mk_dec d-badmark 'legacy_through: nope' '- D1 proposed 2026-10-08 — a
  unconfirmed: x'
assert_eq "Decisions: 1 proposed (0 legacy), oldest 10 days" "$(dec_line d-badmark)" "malformed legacy_through: K=0"

mk_dec d-undated 'legacy_through: D1' '- D1 proposed — legacy undated
- D2 proposed — undated non-legacy
  unconfirmed: x'
assert_eq "Decisions: 2 proposed (1 legacy)" "$(dec_line d-undated)" "no dated non-legacy proposed: oldest clause omitted"

mk_dec d-fence '' '```
- D1 proposed 2026-10-01 — fenced
## Not a heading
```
- D2 proposed 2026-10-17 — real
  unconfirmed: x'
assert_eq "Decisions: 1 proposed (0 legacy), oldest 1 days" "$(dec_line d-fence)" "fenced entries skipped, fenced ## does not end the stream"

mk_dec d-empty '' ''
assert_eq "Decisions: 0 proposed (0 legacy)" "$(dec_line d-empty)" "empty stream: zero"

# C1/H1: malformed heads (incl. impossible dates) are not counted and give no age
mk_dec d-bad '' '- D1 proposed 2026-02-31 — impossible date
  unconfirmed: x
- D2 proposed 2026-10-01 missing dash
- D3 proposed 2026-10-08 — real
  unconfirmed: x'
assert_eq "Decisions: 1 proposed (0 legacy), oldest 10 days" "$(dec_line d-bad)" "malformed heads are neither counted nor aged"

mk_dec d-feb '' '- D1 proposed 2026-02-31 — impossible date
  unconfirmed: x'
assert_eq "Decisions: 0 proposed (0 legacy)" "$(dec_line d-feb)" "an impossible date is not counted"
mk_dec d-leap '' '- D1 proposed 2028-02-29 — leap day
  unconfirmed: x'
assert_eq "Decisions: 1 proposed (0 legacy), oldest 7 days" "$(INITIATIVE_STATUS_TODAY=2028-03-07 bash "$SCRIPT" d-leap 2>&1 | grep '^Decisions:')" "a leap day counts and ages"

mk_dec d-tilde '' '~~~
- D1 proposed 2026-10-01 — fenced
## Not a heading
~~~
````
```
- D2 proposed 2026-10-01 — nested fenced
```
````
- D3 proposed 2026-10-17 — real
  unconfirmed: x'
assert_eq "Decisions: 1 proposed (0 legacy), oldest 1 days" "$(dec_line d-tilde)" "tilde and four-backtick fences are skipped"

# H1: --list-proposed is read-only and uses the shared grammar
mk_dec d-list 'legacy_through: D1' '- D1 proposed — legacy undated
- D2 confirmed 2026-10-01 — done
  evidence: x
- D3 proposed 2026-10-08 — open, wrapped
  second line of the decision
  unconfirmed: x

- D4 proposed 2026-02-31 — impossible date
- D5 proposed 2026-10-01 no dash
~~~
- D6 proposed 2026-10-01 — fenced
~~~
- D7-proposed: old shape
- D8a proposed 2026-10-09 — lettered
  unconfirmed: x'
rm -rf "$MEM/initiatives/.state"
set +e
list_out="$(bash "$SCRIPT" d-list --list-proposed 2>&1)"; list_rc=$?
set -e
assert_exit 0 "$list_rc" "--list-proposed exits 0"
assert_eq "- D1 proposed — legacy undated

- D3 proposed 2026-10-08 — open, wrapped
  second line of the decision
  unconfirmed: x

- D8a proposed 2026-10-09 — lettered
  unconfirmed: x" "$list_out" "--list-proposed prints valid proposed entries in full (continuations, one blank separator), legacy included, fences, malformed and other statuses excluded"
assert_not_file "$MEM/initiatives/.state" "--list-proposed writes no .state directory"
assert_eq "$list_out" "$(bash "$SCRIPT" --list-proposed d-list 2>&1)" "--list-proposed accepts the flag before the slug"
mkdir -p "$MEM/initiatives/.state"; printf 'stream-entries 99\n' > "$MEM/initiatives/.state/d-list.snapshot"
bash "$SCRIPT" d-list --list-proposed >/dev/null 2>&1
assert_eq "stream-entries 99" "$(cat "$MEM/initiatives/.state/d-list.snapshot")" "--list-proposed leaves an existing snapshot untouched"
rm -rf "$MEM/initiatives/.state"
mk_dec d-listempty '' '- D1 confirmed 2026-10-01 — x
  evidence: y'
set +e
empty_out="$(bash "$SCRIPT" d-listempty --list-proposed 2>&1)"; empty_rc=$?
set -e
assert_exit 0 "$empty_rc" "--list-proposed with none exits 0"
assert_eq "" "$empty_out" "--list-proposed with none prints nothing"
set +e
bash "$SCRIPT" --ack d-list --list-proposed >/dev/null 2>&1; both_rc=$?
set -e
assert_exit 2 "$both_rc" "--ack with --list-proposed is a usage error"

# R1: an awk failure is a non-zero exit with stderr kept, never "no proposals"
BAD_HERE="$(new_sandbox)"
cp -R "$SCRIPTS_DIR/." "$BAD_HERE/"
printf 'function ds_broken( {\n' >> "$BAD_HERE/lib/decision-stream.awk"
set +e
bad_out="$(bash "$BAD_HERE/initiative-status.sh" d-list --list-proposed 2>&1 >/dev/null)"; bad_rc=$?
set -e
assert_eq "nonzero" "$([ "$bad_rc" -ne 0 ] && echo nonzero || echo "rc=$bad_rc")" "--list-proposed exits non-zero when awk fails"
assert_eq "kept" "$([ -n "$bad_out" ] && echo kept || echo empty)" "--list-proposed keeps awk's stderr on failure"
rm -rf "$BAD_HERE"

set +e

# @env edges: Target ids are plain strings, so an edge resolves to the Target
# carrying that exact id. X waits on y/thing@staging; y/thing@non-prod is open.
cat > "$MEM/initiatives/envs.md" <<'EOF'
---
kind: initiative
slug: envs
status: active
created: 2026-11-17
---
# Envs
## Targets
### beta/thing@non-prod
- execution_mode: interactive
- scope: non-prod rollout
- depends_on: none
- status: open · next: exec — roll out · blocked_by: none
### beta/thing@staging
- execution_mode: interactive
- depends_on: none
- status: done
### beta/x
- execution_mode: interactive
- depends_on: beta/thing@staging
- status: open · next: exec — consume staging · blocked_by: none
### beta/y
- execution_mode: interactive
- depends_on: beta/thing@non-prod
- status: open · next: exec — consume non-prod · blocked_by: decision D3
### beta/z
- execution_mode: interactive
- depends_on: beta/thing@prod
- status: blocked · next: human — open prod · blocked_by: none
### Closed
| id | closed | jira | outcome |
|---|---|---|---|
| beta/old | 2026-10-01 | ABC-1 | shipped |
| beta/by-closed | 2026-10-02 | ABC-2 | see log |
### beta/after-closed
- execution_mode: interactive
- depends_on: beta/old, beta/thing@staging
- status: open · next: exec — continue · blocked_by: none
## Closure
Open.
EOF
env_out="$(bash "$SCRIPT" envs 2>&1)"; rc=$?
assert_exit 0 "$rc" "@env initiative exits 0"
assert_contains "$env_out" "beta/thing@staging — satisfied" "R2: edge to Y@staging is satisfied when Y@staging is done"
assert_contains "$env_out" "beta/thing@non-prod — unsatisfied (unknown)" "R2: edge to Y@non-prod stays unsatisfied while it is open"
assert_contains "$env_out" "beta/thing@prod — unsatisfied (unknown)" "an edge to an unopened @env id is unsatisfied"
assert_contains "$env_out" "| beta/x | interactive | open |" "interactive state reported as derived status"
assert_contains "$env_out" "| exec — consume staging | none |" "next and blocked_by columns"
assert_contains "$env_out" "| exec — consume non-prod | decision D3 |" "authored blocked_by is shown"

# Closed rows are terminal done Targets and edges resolve to them.
assert_contains "$env_out" "| beta/old |  | done | closed row in initiative | none — n/a | none | none |" "Closed row is a terminal done Target"
assert_contains "$env_out" "| beta/by-closed |  | done | closed row in initiative" "every Closed row is a Target"
assert_contains "$env_out" "beta/old — satisfied; beta/thing@staging — satisfied" "edge to a Closed row is satisfied"
assert_not_contains "$env_out" "| id | closed |" "Closed table header row is not a Target"
assert_not_contains "$env_out" "| --- |" "Closed table separator row is not a Target"

tsv="$(bash "$SCRIPT" --tsv envs 2>&1)"; rc=$?
assert_exit 0 "$rc" "--tsv exits 0"
tab="$(printf '\t')"
assert_eq "beta/thing@non-prod${tab}open${tab}yes${tab}exec — roll out${tab}none${tab}-${tab}open" "$(printf '%s\n' "$tsv" | sed -n 1p)" "--tsv: id, stage, deps-satisfied, next, blocked_by"
assert_eq "beta/x${tab}open${tab}yes${tab}exec — consume staging${tab}none${tab}-${tab}open" "$(printf '%s\n' "$tsv" | grep '^beta/x	')" "--tsv: satisfied edge gives yes"
assert_eq "beta/y${tab}open${tab}no${tab}exec — consume non-prod${tab}decision D3${tab}beta/thing@non-prod (at open)${tab}open" "$(printf '%s\n' "$tsv" | grep '^beta/y	')" "--tsv: unsatisfied edge gives no, blocked_by kept"
assert_eq "beta/old${tab}done${tab}yes${tab}-${tab}-${tab}-${tab}done" "$(printf '%s\n' "$tsv" | grep '^beta/old	')" "--tsv: Closed row is done with no next"
assert_eq "beta/after-closed${tab}open${tab}yes${tab}exec — continue${tab}none${tab}-${tab}open" "$(printf '%s\n' "$tsv" | grep '^beta/after-closed	')" "--tsv: edges to Closed rows count as satisfied"
assert_eq "8" "$(printf '%s\n' "$tsv" | wc -l | tr -d '[:space:]')" "--tsv: one line per Target, nothing else"
assert_eq "7" "$(printf '%s\n' "$tsv" | awk -F'\t' '{ print NF }' | sort -u | tr -d '[:space:]')" "--tsv: seven tab-separated fields on every line"
assert_eq "beta/thing@prod (not found)" "$(printf '%s\n' "$tsv" | grep '^beta/z	' | cut -f6)" "--tsv: an unopened @env edge is reported not found"
assert_eq "blocked" "$(printf '%s\n' "$tsv" | grep '^beta/z	' | cut -f7)" "--tsv: state column carries the asserted state"
sw_tsv="$(bash "$SCRIPT" --tsv ready 2>/dev/null | grep '^alpha/progress	')"
assert_eq "alpha/progress${tab}complete${tab}yes${tab}-${tab}-${tab}-${tab}-" "$sw_tsv" "--tsv: software_adw Target reports its derived stage"
cat > "$MEM/initiatives/qual.md" <<'EOF'
---
kind: initiative
slug: qual
status: active
created: 2026-11-17
---
# Qual
## Targets
### beta/up
- execution_mode: interactive
- stages: plan -> implement -> validate
- depends_on: none
- status: open · next: exec — build · blocked_by: none
### beta/down
- execution_mode: interactive
- depends_on: beta/up (stage: validate), beta/gone
- status: open · next: exec — follow · blocked_by: none
## Closure
Open.
EOF
assert_eq "beta/up (stage: validate) (at open), beta/gone (not found)" "$(bash "$SCRIPT" --tsv qual 2>/dev/null | grep '^beta/down	' | cut -f6)" "--tsv: stage-qualified and missing edges list in order with reasons"
rm -rf "$MEM/initiatives/.state"
bash "$SCRIPT" --tsv envs >/dev/null 2>&1
assert_not_file "$MEM/initiatives/.state" "--tsv writes no snapshot"
set +e
bash "$SCRIPT" --tsv --ack envs >/dev/null 2>&1; rc=$?
assert_exit 2 "$rc" "--tsv with --ack is a usage error"

# Old-format files are refused with a pointer to the 3.0.0 migration.
mk_old() { # slug <target-body-lines...>
    local slug="$1"; shift
    {
        printf '%s\n' '---' 'kind: initiative' "slug: $slug" 'status: active' 'created: 2026-01-01' '---' '# Old' '## Targets' '### beta/x' '- execution_mode: interactive' '- depends_on: none'
        printf '%s\n' "$@"
        printf '%s\n' '## Closure' 'Open.'
    } > "$MEM/initiatives/$slug.md"
}
mk_old old-actor '- status: open · next: s — go · blocked_by: none' '- next_actor: human'
old_out="$(bash "$SCRIPT" old-actor 2>&1)"; rc=$?
assert_exit 1 "$rc" "next_actor: line is refused"
assert_contains "$old_out" "3.0.0-initiative-format.sh" "next_actor refusal names the 3.0.0 migration"
assert_contains "$old_out" "next_actor" "next_actor refusal names the offending line"
mk_old old-prose '- status: open — waiting on review'
old_out="$(bash "$SCRIPT" old-prose 2>&1)"; rc=$?
assert_exit 1 "$rc" "old '<state> — prose' status is refused"
assert_contains "$old_out" "3.0.0-initiative-format.sh" "old status refusal names the 3.0.0 migration"
assert_contains "$old_out" "waiting on review" "old status refusal names the offending status"
mk_old old-partial '- status: open · next: s — go'
bash "$SCRIPT" old-partial >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "status missing blocked_by is refused"
mk_old old-done '- status: done (asserted by test)'
bash "$SCRIPT" old-done >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "old 'done (prose)' status is refused"
mk_old old-none
bash "$SCRIPT" old-none >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "interactive Target with no status is refused"
mk_old new-done '- status: done'
bash "$SCRIPT" new-done >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "terminal status needs no next/blocked_by"
bash "$SCRIPT" --list-proposed old-actor >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "--list-proposed does not parse Targets, so it still works on an old file"


# Closed-table header: the row before the separator is the header, whatever its text.
mk_closed() { # slug <header-row>
    cat > "$MEM/initiatives/$1.md" <<EOF
---
kind: initiative
slug: $1
status: active
created: 2026-11-17
---
# C
## Targets
### beta/open
- execution_mode: interactive
- depends_on: beta/old (stage: implement)
- status: open · next: exec — go · blocked_by: none
### Closed
$2
|---|---|---|---|
| beta/old | 2026-10-01 | ABC-1 | a | b |
| beta/two | 2026-10-02 | ABC-2 | x \| y |
## Closure
Open.
EOF
}
for hdr in '| id | closed | jira | outcome |' '| ID | Closed | Jira | Outcome |' '| Target | Closed on | Ticket | Result |'; do
    mk_closed hdrs "$hdr"
    hout="$(bash "$SCRIPT" --tsv hdrs 2>&1)"
    assert_eq "3" "$(printf '%s\n' "$hout" | wc -l | tr -d '[:space:]')" "Closed header '$hdr' is not a Target"
done
assert_contains "$hout" "beta/old${tab}done${tab}yes" "Closed row present after header spellings"
hout="$(bash "$SCRIPT" hdrs 2>&1)"
assert_not_contains "$hout" "warning" "stage-qualified edge to a Closed row raises no undeclared-stage warning"
assert_not_contains "$hout" "WARNING" "no undeclared-stage WARNING for a Closed row"
assert_contains "$hout" "beta/old (stage: implement) — satisfied" "stage-qualified edge to a Closed row is satisfied"
assert_eq "yes" "$(bash "$SCRIPT" --tsv hdrs 2>&1 | grep '^beta/open	' | cut -f3)" "--tsv: stage-qualified edge to a Closed row is yes"
assert_eq "-" "$(bash "$SCRIPT" --tsv hdrs 2>&1 | grep '^beta/open	' | cut -f6)" "--tsv: satisfied edge to a Closed row leaves unsatisfied empty"

# Closed outcome: cells past the 4th rejoin, and \| is a literal pipe.
assert_contains "$hout" "| beta/two |" "escaped pipe in outcome keeps the row a single Target"
assert_eq "3" "$(bash "$SCRIPT" --tsv hdrs 2>&1 | wc -l | tr -d '[:space:]')" "extra and escaped pipes create no extra Targets"

# State vocabulary is open|blocked|done|closed; terminal text must be a valid tail.
mk_old v-complete '- status: complete · next: s — go · blocked_by: none'
v_out="$(bash "$SCRIPT" v-complete 2>&1)"; rc=$?
assert_exit 1 "$rc" "state outside the vocabulary is refused"
assert_contains "$v_out" "Target 'beta/x'" "vocabulary error names the Target"
assert_contains "$v_out" "line 12" "vocabulary error names the line"
assert_contains "$v_out" "complete" "vocabulary error names the offending status"
mk_old v-done-garbage '- status: done · see log'
bash "$SCRIPT" v-done-garbage >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "done with a non-grammar tail is refused"
mk_old v-closed-garbage '- status: closed 2026-10-01'
bash "$SCRIPT" v-closed-garbage >/dev/null 2>&1; rc=$?
assert_exit 1 "$rc" "closed with trailing text is refused"
mk_old v-done-tail '- status: done · next: none — finished · blocked_by: none'
bash "$SCRIPT" v-done-tail >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "done with a valid tail is accepted"
mk_old v-blocked '- status: blocked · next: human — decide · blocked_by: D3'
bash "$SCRIPT" v-blocked >/dev/null 2>&1; rc=$?
assert_exit 0 "$rc" "blocked is in the vocabulary"

# An authored non-terminal status on a software_adw Target does not disable
# stage-qualified edge comparison.
plan_tr in_progress auth t-auth-001 "$MEM/projects/alpha/plans/auth.md"
cat > "$MEM/initiatives/auth.md" <<'EOF'
---
kind: initiative
slug: auth
status: active
created: 2026-11-17
---
# Auth
## Targets
### alpha/built
- execution_mode: software_adw
- task: t-auth-001
- stages: discover -> plan -> implement -> validate
- depends_on: none
- status: open · next: exec — keep building · blocked_by: none
### alpha/at-reached
- execution_mode: interactive
- depends_on: alpha/built (stage: implement)
- status: open · next: exec — go · blocked_by: none
### alpha/at-later
- execution_mode: interactive
- depends_on: alpha/built (stage: validate)
- status: open · next: exec — go · blocked_by: none
## Closure
Open.
EOF
a_out="$(bash "$SCRIPT" auth 2>&1)"
assert_contains "$a_out" "alpha/built (stage: implement) — satisfied" "authored status on software_adw: reached stage is satisfied"
assert_contains "$a_out" "alpha/built (stage: validate) — unsatisfied (at implement, needs validate)" "authored status on software_adw: later stage is unsatisfied"


finish
