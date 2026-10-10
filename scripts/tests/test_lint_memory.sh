#!/usr/bin/env bash
# lint-memory.sh: clean tree exits 0; missing frontmatter -> ERROR exit 1;
# missing required section -> WARN exit 1; _template excluded.
. "$(dirname "$0")/_assert.sh"

run_lint() { # -> sets OUT, CODE
    set +e
    OUT=$(bash "$SCRIPTS_DIR/lint-memory.sh" 2>&1); CODE=$?
    set -e
}

build_clean() { # build_clean <memdir> : a fully valid tree + regenerated index
    local m="$1"
    seed_min_tree "$m"
    mkdir -p "$m/projects/good/plans" "$m/projects/good/archive/plans" \
             "$m/projects/good/archive/todos" "$m/projects/good/archive/working"
    : > "$m/projects/good/archive/plans/.gitkeep"
    : > "$m/projects/good/archive/todos/.gitkeep"
    : > "$m/projects/good/archive/working/.gitkeep"
    : > "$m/projects/good/working.md"
    printf '# Todo\n' > "$m/projects/good/todo.md"
    cat > "$m/projects/good/memory.md" <<'EOF'
---
topic: good
scope: project
summary: A good project
---
# Project: good

## What It Is
x

## Architecture Decisions
x

## Known Constraints / Gotchas
x

EOF
    write_clean_initiative "$m/initiatives/clean-initiative.md"
    MEMORY_DIR="$m" bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null
}

write_clean_initiative() { # write_clean_initiative <file>
    local f="$1"
    mkdir -p "$(dirname "$f")"
    cat > "$f" <<'EOF'
---
kind: initiative
slug: clean-initiative
status: active
created: 2026-08-14
---

# Clean initiative

## Targets

### good/prepare
- execution_mode: software_adw
- stages: plan, implement
- depends_on: none

### good/review
- execution_mode: interactive
- depends_on: good/prepare (stage: implement)
EOF
}

# --- clean tree ---
MEM="$(new_sandbox)"; trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"
build_clean "$MEM"
run_lint
assert_exit 0 "$CODE" "clean tree exits 0"
assert_contains "$OUT" "clean" "clean tree reports clean"

# --- missing frontmatter field -> ERROR + exit 1 ---
M2="$(new_sandbox)"; export MEMORY_DIR="$M2"; build_clean "$M2"
# strip the summary line from the domain file
grep -v '^summary:' "$M2/domain/terraform.md" > "$M2/domain/terraform.md.tmp"
mv "$M2/domain/terraform.md.tmp" "$M2/domain/terraform.md"
run_lint
assert_exit 1 "$CODE" "missing frontmatter exits 1"
assert_contains "$OUT" "ERROR" "missing frontmatter -> ERROR"
assert_contains "$OUT" "summary" "names the missing field"
rm -rf "$M2"

# --- missing required project section -> WARN + exit 1 ---
M3="$(new_sandbox)"; export MEMORY_DIR="$M3"; build_clean "$M3"
grep -v '^## Known Constraints / Gotchas$' "$M3/projects/good/memory.md" > "$M3/projects/good/memory.md.tmp"
mv "$M3/projects/good/memory.md.tmp" "$M3/projects/good/memory.md"
run_lint
assert_exit 1 "$CODE" "missing section exits 1"
assert_contains "$OUT" "Known Constraints / Gotchas" "names the missing section"
rm -rf "$M3"

# Insert a frontmatter key before the closing --- (test-local helper).
set_fm() { # set_fm <file> <key> <val>
    awk -v k="$2" -v v="$3" '
        NR==1 && /^---[[:space:]]*$/ { print; infm=1; next }
        infm && /^---[[:space:]]*$/ { print k": "v; print; infm=0; next }
        { print }
    ' "$1" > "$1.t" && mv "$1.t" "$1"
}

# --- orphan check is by identifier (name/topic), not path: a project absent
#     from the (lean, path-less) index warns. ---
MO="$(new_sandbox)"; export MEMORY_DIR="$MO"; build_clean "$MO"
mkdir -p "$MO/projects/ghost/plans" "$MO/projects/ghost/archive/plans" \
         "$MO/projects/ghost/archive/todos" "$MO/projects/ghost/archive/working"
: > "$MO/projects/ghost/archive/plans/.gitkeep"; : > "$MO/projects/ghost/archive/todos/.gitkeep"
: > "$MO/projects/ghost/archive/working/.gitkeep"; : > "$MO/projects/ghost/working.md"
printf '# Todo\n' > "$MO/projects/ghost/todo.md"
cat > "$MO/projects/ghost/memory.md" <<'EOF'
---
topic: ghost
scope: project
summary: not reindexed
---
# Project: ghost

## What It Is
x
## Architecture Decisions
x
## Known Constraints / Gotchas
x
EOF
# Deliberately do NOT reindex — ghost is absent from the index.
run_lint
assert_exit 1 "$CODE" "project absent from index warns (orphan-by-name)"
assert_contains "$OUT" "ghost" "orphan warning names the project"
rm -rf "$MO"

# --- optional category is accepted when present, never required (absent case is
#     the clean-tree run above) ---
MC="$(new_sandbox)"; export MEMORY_DIR="$MC"; build_clean "$MC"
set_fm "$MC/projects/good/memory.md" category acme-corp
run_lint
assert_exit 0 "$CODE" "present category keeps lint clean (exit 0)"
rm -rf "$MC"

# --- valid repo_path + matching back-pin -> exit 0 ---
M4="$(new_sandbox)"; export MEMORY_DIR="$M4"; build_clean "$M4"
R4="$(new_sandbox)"; export AI_MEMORY_PROJECTS_ROOT="$R4"
mkdir -p "$R4/good-co/.agents"; printf 'good\n' > "$R4/good-co/.agents/memory-project"
set_fm "$M4/projects/good/memory.md" repo_path good-co
run_lint
assert_exit 0 "$CODE" "valid repo_path + matching back-pin -> 0"
rm -rf "$M4" "$R4"

# --- legacy .claude back-pin still resolves but earns a migration WARN ---
ML="$(new_sandbox)"; export MEMORY_DIR="$ML"; build_clean "$ML"
RL="$(new_sandbox)"; export AI_MEMORY_PROJECTS_ROOT="$RL"
mkdir -p "$RL/good-co/.claude"; printf 'good\n' > "$RL/good-co/.claude/memory-project"
set_fm "$ML/projects/good/memory.md" repo_path good-co
run_lint
assert_contains "$OUT" "legacy .claude/memory-project" "legacy marker flagged for migration"
rm -rf "$ML" "$RL"

# --- repo_path target dir missing -> exit 1 ---
M5="$(new_sandbox)"; export MEMORY_DIR="$M5"; build_clean "$M5"
R5="$(new_sandbox)"; export AI_MEMORY_PROJECTS_ROOT="$R5"
set_fm "$M5/projects/good/memory.md" repo_path ghost-dir
run_lint
assert_exit 1 "$CODE" "missing repo_path dir exits 1"
assert_contains "$OUT" "repo_path" "names the repo_path drift"
rm -rf "$M5" "$R5"

# --- back-pin names a different project -> exit 1 ---
M6="$(new_sandbox)"; export MEMORY_DIR="$M6"; build_clean "$M6"
R6="$(new_sandbox)"; export AI_MEMORY_PROJECTS_ROOT="$R6"
mkdir -p "$R6/good-co/.agents"; printf 'WRONG\n' > "$R6/good-co/.agents/memory-project"
set_fm "$M6/projects/good/memory.md" repo_path good-co
run_lint
assert_exit 1 "$CODE" "wrong back-pin exits 1"
assert_contains "$OUT" "WRONG" "reports the wrong back-pin value"
rm -rf "$M6" "$R6"
unset AI_MEMORY_PROJECTS_ROOT

# --- canonical plan status: in_progress clean, in-progress warns ---
M7="$(new_sandbox)"; export MEMORY_DIR="$M7"; build_clean "$M7"
cat > "$M7/projects/good/plans/ok.md" <<'EOF'
---
plan: ok
status: in_progress
created: 2026-07-02
owner: seyi
task_ref: none
---
# ok
EOF
run_lint
assert_exit 0 "$CODE" "in_progress plan status keeps lint clean"
# flip to the hyphenated spelling
sed 's/^status: in_progress$/status: in-progress/' "$M7/projects/good/plans/ok.md" > "$M7/projects/good/plans/ok.md.t"
mv "$M7/projects/good/plans/ok.md.t" "$M7/projects/good/plans/ok.md"
run_lint
assert_exit 1 "$CODE" "hyphenated plan status exits 1"
assert_contains "$OUT" "in_progress" "warning recommends the underscore form"

# every allowed value is clean
for st in draft in_progress "done"; do
    cat > "$M7/projects/good/plans/ok.md" <<EOF
---
plan: ok
status: $st
created: 2026-07-02
owner: seyi
task_ref: none
---
# ok
EOF
    run_lint
    assert_exit 0 "$CODE" "plan status '$st' keeps lint clean"
done

# an off-vocabulary synonym warns — this is the case the old rule missed
cat > "$M7/projects/good/plans/ok.md" <<'EOF'
---
plan: ok
status: active
created: 2026-07-02
owner: seyi
task_ref: none
---
# ok
EOF
run_lint
assert_exit 1 "$CODE" "off-vocabulary plan status exits 1"
assert_contains "$OUT" "status 'active' is not a plan status" "warning names the offending value"

# a missing status warns — the other case the old rule missed
cat > "$M7/projects/good/plans/ok.md" <<'EOF'
---
plan: ok
created: 2026-07-02
owner: seyi
task_ref: none
---
# ok
EOF
run_lint
assert_exit 1 "$CODE" "plan with no status exits 1"
assert_contains "$OUT" "has no status" "warning names the missing status"
rm -rf "$M7"

# --- stale per-worktree overlay is flagged like a stale working.md ---
M8="$(new_sandbox)"; export MEMORY_DIR="$M8"; build_clean "$M8"
printf '# Working — good (overlay)\nstale scratch\n' > "$M8/projects/good/working.wt-old.md"
touch -t 202001010000 "$M8/projects/good/working.wt-old.md"
run_lint
assert_contains "$OUT" "working.wt-old.md stale" "lint flags a stale worktree overlay"
rm -rf "$M8"

# --- a working file holding only headings/placeholders is not "stale" ---
# Both halves matter: the skip must fire on the placeholder file AND must not
# swallow a genuinely stale one, or it silences the check it is narrowing.
M8B="$(new_sandbox)"; export MEMORY_DIR="$M8B"; build_clean "$M8B"
printf '# Working — good\n\n## Cross-project learnings (pending promotion)\n\n_(none yet)_\n\n## Checkpoints\n' \
    > "$M8B/projects/good/working.md"
touch -t 202001010000 "$M8B/projects/good/working.md"
run_lint
assert_not_contains "$OUT" "working.md stale" "placeholder-only working.md is not flagged stale"
printf '# Working — good\n\n## Checkpoints\n\n### old\nreal content\n' > "$M8B/projects/good/working.md"
touch -t 202001010000 "$M8B/projects/good/working.md"
run_lint
assert_contains "$OUT" "working.md stale" "working.md with real content is still flagged stale"
rm -rf "$M8B"

# --- the domain scaffold is excluded from the orphan check ---
M8C="$(new_sandbox)"; export MEMORY_DIR="$M8C"; build_clean "$M8C"
cat > "$M8C/domain/_template.md" <<'EOF'
---
topic: <topic>
triggers: [<trigger>]
summary: <one-line summary>
---

# Domain: <Name>

## Knowledge
EOF
run_lint
assert_not_contains "$OUT" "_template.md orphan" "domain scaffold is not reported as an orphan"
rm -rf "$M8C"

# --- investigations must carry a task_ref (lifecycle anchor) ---
M9="$(new_sandbox)"; export MEMORY_DIR="$M9"; build_clean "$M9"
mkdir -p "$M9/projects/good/investigations" "$M9/projects/good/archive/investigations"
cat > "$M9/projects/good/investigations/anchored.md" <<'EOF'
---
kind: investigation
task_ref: 12345678-abcd-4ef0-9012-34567890abcd
status: open
created: 2026-07-16
---
# anchored
EOF
run_lint
assert_exit 0 "$CODE" "investigation with task_ref keeps lint clean"
cat > "$M9/projects/good/investigations/plan-only.md" <<'EOF'
---
kind: investigation
task_ref: none
status: open
created: 2026-07-16
---
# plan-only
EOF
run_lint
assert_exit 1 "$CODE" "investigation with task_ref none exits 1"
assert_contains "$OUT" "plan-only.md has no task_ref" "task_ref none is not an investigation lifecycle anchor"
rm "$M9/projects/good/investigations/plan-only.md"
cat > "$M9/projects/good/investigations/orphan.md" <<'EOF'
---
kind: investigation
status: open
created: 2026-07-16
---
# orphan
EOF
run_lint
assert_exit 1 "$CODE" "investigation without task_ref exits 1"
assert_contains "$OUT" "orphan.md has no task_ref" "warning names the orphan investigation"
# archived investigations are never scanned
mv "$M9/projects/good/investigations/orphan.md" "$M9/projects/good/archive/investigations/orphan.md"
run_lint
assert_exit 0 "$CODE" "archived orphan investigation is not scanned"
rm -rf "$M9"

# --- stale investigation: task_ref matches a plan already in archive/plans/ ---
M10="$(new_sandbox)"; export MEMORY_DIR="$M10"; build_clean "$M10"
mkdir -p "$M10/projects/good/investigations"
cat > "$M10/projects/good/archive/plans/shipped.md" <<'EOF'
---
plan: shipped
status: done
created: 2026-07-01
completed: 2026-07-02
owner: seyi
task_ref: stale-task-ref-001
---
# shipped
EOF
cat > "$M10/projects/good/investigations/shipped.md" <<'EOF'
---
kind: investigation
task_ref: stale-task-ref-001
status: open
created: 2026-07-01
---
# shipped
EOF
run_lint
assert_exit 1 "$CODE" "stale investigation (task_ref matches archived plan) exits 1"
assert_contains "$OUT" "shipped.md stale" "warning names the stale investigation"
assert_contains "$OUT" "archived plan" "warning points at the archived plan"
rm -rf "$M10"

# --- live investigation: task_ref matches a plan still in plans/ (not archived) -> no stale warning ---
M11="$(new_sandbox)"; export MEMORY_DIR="$M11"; build_clean "$M11"
mkdir -p "$M11/projects/good/investigations"
cat > "$M11/projects/good/plans/inflight.md" <<'EOF'
---
plan: inflight
status: in_progress
created: 2026-07-01
owner: seyi
task_ref: live-task-ref-002
---
# inflight
EOF
cat > "$M11/projects/good/investigations/inflight.md" <<'EOF'
---
kind: investigation
task_ref: live-task-ref-002
status: open
created: 2026-07-01
---
# inflight
EOF
run_lint
assert_exit 0 "$CODE" "investigation whose plan is still live keeps lint clean (not stale)"
rm -rf "$M11"

# --- live plans must declare task linkage; `none` is the explicit plan-only marker ---
M12="$(new_sandbox)"; export MEMORY_DIR="$M12"; build_clean "$M12"
cat > "$M12/projects/good/plans/unlinked.md" <<'EOF'
---
plan: unlinked
status: draft
created: 2026-09-09
owner: seyi
---
# unlinked
EOF
run_lint
assert_exit 1 "$CODE" "live plan without task_ref exits 1"
assert_contains "$OUT" "unlinked.md has no task_ref" "unlinked live plan is flagged"
set_fm "$M12/projects/good/plans/unlinked.md" task_ref none
run_lint
assert_exit 0 "$CODE" "rule 12 accepts task_ref none on plans"
assert_not_contains "$OUT" "unlinked.md has no task_ref" "plan-only marker is silent"
sed 's/^task_ref: none$/task_ref: real-task-ref-003/' "$M12/projects/good/plans/unlinked.md" > "$M12/projects/good/plans/unlinked.md.t"
mv "$M12/projects/good/plans/unlinked.md.t" "$M12/projects/good/plans/unlinked.md"
run_lint
assert_exit 0 "$CODE" "real task_ref suppresses live-plan linkage warning"
assert_not_contains "$OUT" "unlinked.md has no task_ref" "real task_ref is silent"
mv "$M12/projects/good/plans/unlinked.md" "$M12/projects/good/archive/plans/unlinked.md"
run_lint
assert_exit 0 "$CODE" "archived plan without task_ref is exempt"
assert_not_contains "$OUT" "unlinked.md has no task_ref" "archived plan is never scanned"
rm -rf "$M12"

# --- `none` is plans-only: rule 9 rejects it while rule 10 skips it ---
M13="$(new_sandbox)"; export MEMORY_DIR="$M13"; build_clean "$M13"
mkdir -p "$M13/projects/good/investigations"
cat > "$M13/projects/good/archive/plans/plan-only.md" <<'EOF'
---
plan: plan-only
status: done
created: 2026-09-09
owner: seyi
task_ref: none
---
# plan-only
EOF
cat > "$M13/projects/good/investigations/plan-only.md" <<'EOF'
---
kind: investigation
task_ref: none
status: open
created: 2026-09-09
---
# plan-only
EOF
run_lint
assert_exit 1 "$CODE" "rule 9 rejects task_ref none on investigations"
assert_contains "$OUT" "plan-only.md has no task_ref" "none has no investigation lifecycle anchor"
assert_not_contains "$OUT" "plan-only.md stale" "none never matches an archived plan"
rm -rf "$M13"

# --- clean initiative modeled on initiatives/_template.md passes all rules ---
MI1="$(new_sandbox)"; export MEMORY_DIR="$MI1"; build_clean "$MI1"
run_lint
assert_exit 0 "$CODE" "clean initiative keeps lint clean"
assert_not_contains "$OUT" "clean-initiative.md" "clean initiative produces no findings"
rm -rf "$MI1"

# --- initiative frontmatter fields are required ---
MI2="$(new_sandbox)"; export MEMORY_DIR="$MI2"; build_clean "$MI2"
grep -v '^created:' "$MI2/initiatives/clean-initiative.md" > "$MI2/initiatives/clean-initiative.md.t"
mv "$MI2/initiatives/clean-initiative.md.t" "$MI2/initiatives/clean-initiative.md"
run_lint
assert_exit 1 "$CODE" "initiative missing frontmatter exits 1"
assert_contains "$OUT" "clean-initiative.md missing frontmatter fields: created" "initiative missing created -> ERROR"
rm -rf "$MI2"

# --- initiative kind must be initiative ---
MI3="$(new_sandbox)"; export MEMORY_DIR="$MI3"; build_clean "$MI3"
sed 's/^kind: initiative$/kind: project/' "$MI3/initiatives/clean-initiative.md" > "$MI3/initiatives/clean-initiative.md.t"
mv "$MI3/initiatives/clean-initiative.md.t" "$MI3/initiatives/clean-initiative.md"
run_lint
assert_contains "$OUT" "kind 'project' is not 'initiative'" "initiative kind mismatch warns"
rm -rf "$MI3"

# --- initiative slug must match its filename ---
MI4="$(new_sandbox)"; export MEMORY_DIR="$MI4"; build_clean "$MI4"
mv "$MI4/initiatives/clean-initiative.md" "$MI4/initiatives/different-filename.md"
run_lint
assert_contains "$OUT" "slug 'clean-initiative' does not match filename 'different-filename'" "initiative slug mismatch warns"
rm -rf "$MI4"

# --- initiative status vocabulary is active|closed ---
MI5="$(new_sandbox)"; export MEMORY_DIR="$MI5"; build_clean "$MI5"
sed 's/^status: active$/status: draft/' "$MI5/initiatives/clean-initiative.md" > "$MI5/initiatives/clean-initiative.md.t"
mv "$MI5/initiatives/clean-initiative.md.t" "$MI5/initiatives/clean-initiative.md"
run_lint
assert_contains "$OUT" "status 'draft' is not an initiative status" "invalid initiative status warns"
rm -rf "$MI5"

# --- Target ids must be unique within an initiative ---
MI6="$(new_sandbox)"; export MEMORY_DIR="$MI6"; build_clean "$MI6"
cat >> "$MI6/initiatives/clean-initiative.md" <<'EOF'

### good/prepare
- execution_mode: interactive
- depends_on: none
EOF
run_lint
assert_contains "$OUT" "duplicate Target id 'good/prepare'" "duplicate Target id warns"
rm -rf "$MI6"

# --- depends_on edges resolve to a Target in the same initiative ---
MI7="$(new_sandbox)"; export MEMORY_DIR="$MI7"; build_clean "$MI7"
awk '
    !replaced && /^- depends_on: none$/ {
        print "- depends_on: good/missing"
        replaced = 1
        next
    }
    { print }
' "$MI7/initiatives/clean-initiative.md" > "$MI7/initiatives/clean-initiative.md.t"
mv "$MI7/initiatives/clean-initiative.md.t" "$MI7/initiatives/clean-initiative.md"
run_lint
assert_contains "$OUT" "depends_on unresolved Target id 'good/missing'" "unresolved depends_on warns"
rm -rf "$MI7"

# --- software_adw Targets require stages ---
MI8="$(new_sandbox)"; export MEMORY_DIR="$MI8"; build_clean "$MI8"
grep -v '^\- stages:' "$MI8/initiatives/clean-initiative.md" > "$MI8/initiatives/clean-initiative.md.t"
mv "$MI8/initiatives/clean-initiative.md.t" "$MI8/initiatives/clean-initiative.md"
run_lint
assert_contains "$OUT" "execution_mode 'software_adw' has no stages" "software_adw without stages warns"
rm -rf "$MI8"

# --- non-software_adw Targets cannot carry stages ---
MI9="$(new_sandbox)"; export MEMORY_DIR="$MI9"; build_clean "$MI9"
sed '/^### good\/review$/a\
- stages: should-not-be-here
' "$MI9/initiatives/clean-initiative.md" > "$MI9/initiatives/clean-initiative.md.t"
mv "$MI9/initiatives/clean-initiative.md.t" "$MI9/initiatives/clean-initiative.md"
run_lint
assert_contains "$OUT" "Target 'good/review' has stages but execution_mode is 'interactive'" "stages on interactive Target warns"
rm -rf "$MI9"

# --- the initiative scaffold and closed archive are never scanned ---
MI10="$(new_sandbox)"; export MEMORY_DIR="$MI10"; build_clean "$MI10"
cat > "$MI10/initiatives/_template.md" <<'EOF'
---
kind: wrong
---
### duplicate/target
### duplicate/target
EOF
mkdir -p "$MI10/initiatives/archive"
cat > "$MI10/initiatives/archive/closed.md" <<'EOF'
---
kind: wrong
---
### duplicate/target
### duplicate/target
EOF
run_lint
assert_exit 0 "$CODE" "initiative scaffold and archive are not scanned"
assert_not_contains "$OUT" "initiatives/_template.md" "initiative scaffold is skipped"
assert_not_contains "$OUT" "initiatives/archive/closed.md" "initiative archive is skipped"
rm -rf "$MI10"

# --- a /new-initiative scaffold from the REAL tracked template lints clean ---
# Pins template <-> lint compatibility: the live-exercise of /new-initiative
# found the template's example Target block parsed as a real malformed Target.
MI11="$(new_sandbox)"; export MEMORY_DIR="$MI11"; build_clean "$MI11"
mkdir -p "$MI11/initiatives"
sed -e 's/^slug: <slug>$/slug: scaffold-check/' \
    -e 's/^created: YYYY-MM-DD$/created: 2026-08-14/' \
    "$SCRIPTS_DIR/../initiatives/_template.md" > "$MI11/initiatives/scaffold-check.md"
run_lint
assert_exit 0 "$CODE" "freshly scaffolded initiative keeps lint clean"
assert_not_contains "$OUT" "scaffold-check.md" "scaffolded initiative produces no findings"
rm -rf "$MI11"

# --- Target status tokens are optional, but valid when asserted ---
# Carries a task so rule 14 (open Target needs a task) does not also fire —
# this fixture is exercising rule 13's token grammar only.
MI12="$(new_sandbox)"; export MEMORY_DIR="$MI12"; build_clean "$MI12"
cat >> "$MI12/initiatives/clean-initiative.md" <<'EOF'
- task: 10000000-0000-4000-8000-000000000001
- status: open — awaiting review
EOF
run_lint
assert_exit 0 "$CODE" "valid Target status token passes"
assert_not_contains "$OUT" "status must begin" "valid Target status token does not warn"
rm -rf "$MI12"

# --- a status assertion needs a machine-readable first token ---
MI13="$(new_sandbox)"; export MEMORY_DIR="$MI13"; build_clean "$MI13"
cat >> "$MI13/initiatives/clean-initiative.md" <<'EOF'
- status: awaiting review
EOF
run_lint
assert_exit 1 "$CODE" "tokenless Target status exits 1"
assert_contains "$OUT" "clean-initiative.md Target 'good/review' status must begin" "tokenless Target status warns with Target id"
rm -rf "$MI13"

# --- markdown emphasis is not a machine-readable status token ---
MI14="$(new_sandbox)"; export MEMORY_DIR="$MI14"; build_clean "$MI14"
cat >> "$MI14/initiatives/clean-initiative.md" <<'EOF'
- status: **DONE — historical result**
EOF
run_lint
assert_exit 1 "$CODE" "emphasised Target status exits 1"
assert_contains "$OUT" "clean-initiative.md Target 'good/review' status must begin" "emphasised Target status warns"
rm -rf "$MI14"

# --- software_adw Targets may omit an asserted status entirely ---
MI15="$(new_sandbox)"; export MEMORY_DIR="$MI15"; build_clean "$MI15"
run_lint
assert_exit 0 "$CODE" "Target with no status line passes"
assert_not_contains "$OUT" "status must begin" "Target with no status line does not warn"
rm -rf "$MI15"

# --- historical status prose is outside the machine-readable grammar ---
MI16="$(new_sandbox)"; export MEMORY_DIR="$MI16"; build_clean "$MI16"
cat >> "$MI16/initiatives/clean-initiative.md" <<'EOF'
- status (historical): **DONE — historical result**
EOF
run_lint
assert_exit 0 "$CODE" "historical Target status passes"
assert_not_contains "$OUT" "status must begin" "historical Target status does not warn"
rm -rf "$MI16"

# --- rule 14: a live (open/blocked) Target must carry a task ---
MI17="$(new_sandbox)"; export MEMORY_DIR="$MI17"; build_clean "$MI17"
cat >> "$MI17/initiatives/clean-initiative.md" <<'EOF'

### good/no-task
- execution_mode: interactive
- depends_on: none
- status: open — needs decomposition
EOF
run_lint
assert_exit 1 "$CODE" "open Target without a task exits 1"
assert_contains "$OUT" "Target 'good/no-task' is open/blocked but has no task" "warning names the undecomposed Target"
rm -rf "$MI17"

# --- rule 14: an open Target with a task passes ---
MI18="$(new_sandbox)"; export MEMORY_DIR="$MI18"; build_clean "$MI18"
cat >> "$MI18/initiatives/clean-initiative.md" <<'EOF'

### good/has-task
- execution_mode: interactive
- task: 20000000-0000-4000-8000-000000000002
- depends_on: none
- status: open — decomposed
EOF
run_lint
assert_exit 0 "$CODE" "open Target with a task keeps lint clean"
assert_not_contains "$OUT" "has no task" "task-bearing open Target does not warn"
rm -rf "$MI18"

# --- rule 14: a terminal (done/closed) Target is exempt even without a task ---
MI19="$(new_sandbox)"; export MEMORY_DIR="$MI19"; build_clean "$MI19"
cat >> "$MI19/initiatives/clean-initiative.md" <<'EOF'

### good/finished
- execution_mode: interactive
- depends_on: none
- status: done — shipped
EOF
run_lint
assert_exit 0 "$CODE" "terminal Target without a task keeps lint clean"
assert_not_contains "$OUT" "has no task" "terminal Target does not warn"
rm -rf "$MI19"

# --- rule 14: a Target asserting no status line at all is undeclared, not
#     live — exempt. This is the shape of six real dispatch Targets today. ---
MI20="$(new_sandbox)"; export MEMORY_DIR="$MI20"; build_clean "$MI20"
run_lint
assert_exit 0 "$CODE" "Target with no status line and no task keeps lint clean"
assert_not_contains "$OUT" "has no task" "statusless Target does not warn"
rm -rf "$MI20"

# --- rule 15a: a task ref must appear on at most one Target, across ALL live
#     initiative files (a single file here is enough to exercise the check). ---
MI21="$(new_sandbox)"; export MEMORY_DIR="$MI21"; build_clean "$MI21"
sed '/^### good\/prepare$/a\
- task: 30000000-0000-4000-8000-000000000003
' "$MI21/initiatives/clean-initiative.md" > "$MI21/initiatives/clean-initiative.md.t"
mv "$MI21/initiatives/clean-initiative.md.t" "$MI21/initiatives/clean-initiative.md"
cat >> "$MI21/initiatives/clean-initiative.md" <<'EOF'

### good/duplicate-task
- execution_mode: interactive
- task: 30000000-0000-4000-8000-000000000003
- depends_on: none
EOF
run_lint
assert_exit 1 "$CODE" "one task on two Targets exits 1"
assert_contains "$OUT" "task '30000000-0000-4000-8000-000000000003'" "warning names the shared task"
assert_contains "$OUT" "good/prepare" "warning names the first Target"
assert_contains "$OUT" "good/duplicate-task" "warning names the second Target"
rm -rf "$MI21"

# --- rule 15b: at most one live plan may carry a given task_ref ---
MI22="$(new_sandbox)"; export MEMORY_DIR="$MI22"; build_clean "$MI22"
sed '/^### good\/prepare$/a\
- task: 40000000-0000-4000-8000-000000000004
' "$MI22/initiatives/clean-initiative.md" > "$MI22/initiatives/clean-initiative.md.t"
mv "$MI22/initiatives/clean-initiative.md.t" "$MI22/initiatives/clean-initiative.md"
cat > "$MI22/projects/good/plans/plan-a.md" <<'EOF'
---
plan: plan-a
status: draft
created: 2026-09-01
owner: seyi
task_ref: 40000000-0000-4000-8000-000000000004
---
# plan-a
EOF
cat > "$MI22/projects/good/plans/plan-b.md" <<'EOF'
---
plan: plan-b
status: draft
created: 2026-09-01
owner: seyi
task_ref: 40000000-0000-4000-8000-000000000004
---
# plan-b
EOF
run_lint
assert_exit 1 "$CODE" "one task_ref on two live plans exits 1"
assert_contains "$OUT" "task '40000000-0000-4000-8000-000000000004'" "warning names the shared task_ref"
assert_contains "$OUT" "plan-a.md" "warning names the first plan"
assert_contains "$OUT" "plan-b.md" "warning names the second plan"
rm -rf "$MI22"

# --- rule 15b: `task_ref: none` is plans-only vocabulary and is never
#     compared, even when a Target's task field is (degenerately) `none`. ---
MI23="$(new_sandbox)"; export MEMORY_DIR="$MI23"; build_clean "$MI23"
sed '/^### good\/prepare$/a\
- task: none
' "$MI23/initiatives/clean-initiative.md" > "$MI23/initiatives/clean-initiative.md.t"
mv "$MI23/initiatives/clean-initiative.md.t" "$MI23/initiatives/clean-initiative.md"
cat > "$MI23/projects/good/plans/plan-c.md" <<'EOF'
---
plan: plan-c
status: draft
created: 2026-09-01
owner: seyi
task_ref: none
---
# plan-c
EOF
cat > "$MI23/projects/good/plans/plan-d.md" <<'EOF'
---
plan: plan-d
status: draft
created: 2026-09-01
owner: seyi
task_ref: none
---
# plan-d
EOF
run_lint
assert_exit 0 "$CODE" "task_ref none on two live plans does not warn"
assert_not_contains "$OUT" "claimed by multiple live plans" "task_ref none is exempt from plan uniqueness"
rm -rf "$MI23"

# --- rule 16: an oversized memory.md is a budget WARN -----------------------
M24="$(new_sandbox)"; export MEMORY_DIR="$M24"; build_clean "$M24"
python3 - "$M24/projects/good/memory.md" <<'PY'
import sys
with open(sys.argv[1], "ab") as f:
    f.write(b"\n" + b"x" * 20000 + b"\n")
PY
run_lint
assert_exit 1 "$CODE" "oversized memory.md exits 1"
assert_contains "$OUT" "WARN:" "oversized memory.md is a WARN"
assert_contains "$OUT" "budget" "oversized memory.md names the budget rule"
assert_not_contains "$OUT" "WARN budget" "lint strips the checker's own WARN label (no doubled 'WARN budget')"
rm -rf "$M24"

# --- rule 16: a line over 400 bytes is a long-line WARN ---------------------
M25="$(new_sandbox)"; export MEMORY_DIR="$M25"; build_clean "$M25"
python3 - "$M25/projects/good/memory.md" <<'PY'
import sys
with open(sys.argv[1], "ab") as f:
    f.write(b"\n" + b"y" * 450 + b"\n")
PY
run_lint
assert_exit 1 "$CODE" "a 450-byte line exits 1"
assert_contains "$OUT" "WARN:" "long line is a WARN"
assert_contains "$OUT" "long-line" "long line names the long-line rule"
assert_not_contains "$OUT" "WARN long-line" "lint strips the checker's own WARN label (no doubled 'WARN long-line')"
rm -rf "$M25"

# --- rule 16: a rendered session payload over a harness's session_chunks cap
#     is an ERROR. AI_MEMORY_HARNESSES_DIR is the same test seam
#     test_check_memory_size.sh uses for the exact same reason: it reads
#     straight from the environment in check-memory-size.sh (invoked here as
#     lint's subprocess), so exporting it before run_lint reaches that
#     subprocess exactly like a direct check-memory-size.sh call would. ---
M26="$(new_sandbox)"; export MEMORY_DIR="$M26"; build_clean "$M26"
HARN26="$(new_sandbox)"
mkdir -p "$HARN26/capped"
cat > "$HARN26/capped/manifest" <<'EOF'
name = capped
format = xml
session_chunks = 1
EOF
python3 - "$M26/projects/good/working.md" <<'PY'
import sys
with open(sys.argv[1], "w") as f:
    for i in range(6):
        f.write(("w%d" % i) * 1000 + "\n")
PY
export AI_MEMORY_HARNESSES_DIR="$HARN26"
run_lint
unset AI_MEMORY_HARNESSES_DIR
assert_exit 1 "$CODE" "over-cap session payload exits 1"
assert_contains "$OUT" "ERROR:" "over-cap payload is an ERROR"
assert_contains "$OUT" "payload" "over-cap payload names the payload rule"
assert_not_contains "$OUT" "ERROR payload" "lint strips the checker's own ERROR label (no doubled 'ERROR payload')"
rm -rf "$M26" "$HARN26"

# --- rule 16: a MEMORY_DIR path that itself contains ":<digits>: ERROR "
#     must not misclassify a real WARN finding as ERROR. emit_size_finding's
#     case patterns test for that shape anywhere in the finding string; a
#     MEMORY_DIR carrying it ahead of the real <file>:<line>: WARN token used
#     to match the ERROR arm first. M28's directory name is deliberately
#     crafted to collide (mirrors the exact repro from the fix's spec).
#
#     Built by hand rather than via build_clean/seed_min_tree: those run
#     regenerate-index.sh, which has its own pre-existing (and separately
#     tracked, out of scope here) word-splitting bug on a MEMORY_DIR
#     containing a space — unrelated to emit_size_finding, but it would abort
#     this case before lint-memory.sh ever ran. A minimal projects/good/
#     memory.md is all rule 16's long-line check needs. --------------------
M28_BASE="$(new_sandbox)"
M28="$M28_BASE/v:1: ERROR x"
mkdir -p "$M28/projects/good"
export MEMORY_DIR="$M28"
cat > "$M28/projects/good/memory.md" <<'EOF'
---
topic: good
scope: project
summary: A good project
---
# Project: good
EOF
python3 - "$M28/projects/good/memory.md" <<'PY'
import sys
with open(sys.argv[1], "ab") as f:
    f.write(b"\n" + b"y" * 450 + b"\n")
PY
run_lint
assert_exit 1 "$CODE" "poisoned MEMORY_DIR: a 450-byte line still exits 1"
assert_contains "$OUT" "WARN:" "poisoned MEMORY_DIR: long-line finding is still classified as WARN"
assert_not_contains "$OUT" "ERROR:" "poisoned MEMORY_DIR: long-line finding is NOT misclassified as ERROR"
rm -rf "$M28_BASE"

# --- rule 16: _template is never scanned (parity with every other rule) ----
M27="$(new_sandbox)"; export MEMORY_DIR="$M27"; build_clean "$M27"
python3 - "$M27/projects/_template/memory.md" <<'PY'
import sys
with open(sys.argv[1], "ab") as f:
    f.write(b"\n" + b"x" * 20000 + b"\n")
PY
run_lint
assert_exit 0 "$CODE" "oversized _template/memory.md is never scanned"
rm -rf "$M27"

# --- rule 17: exact cross-file duplicate line ------------------------------
DUP='Always rotate the shared credential before reusing the bucket name.'
M29="$(new_sandbox)"; export MEMORY_DIR="$M29"; build_clean "$M29"
printf -- '- %s\n' "$DUP" >> "$M29/projects/good/memory.md"
printf '%s\n' "$DUP" >> "$M29/domain/terraform.md"
run_lint
assert_exit 1 "$CODE" "cross-file duplicate line exits 1"
assert_contains "$OUT" "duplicate line in 2 files" "cross-file duplicate is a WARN"
assert_contains "$OUT" "projects/good/memory.md:$(grep -nF "$DUP" "$M29/projects/good/memory.md" | cut -d: -f1)" "duplicate WARN names the project file:line"
assert_contains "$OUT" "domain/terraform.md:$(grep -nF "$DUP" "$M29/domain/terraform.md" | cut -d: -f1)" "duplicate WARN names the domain file:line"
rm -rf "$M29"

M30="$(new_sandbox)"; export MEMORY_DIR="$M30"; build_clean "$M30"
SHORT='_(none yet)_'
HEAD='## A heading that is long enough to pass the length floor'
for t in "$M30/projects/good/memory.md" "$M30/domain/terraform.md"; do
    printf '%s\n%s\n<!-- an html comment long enough to pass the length floor -->\n| col a long enough header | col b long enough header |\n|---|---|\n' "$SHORT" "$HEAD" >> "$t"
done
printf '%s\n' 'Same-file repeat that is long enough to pass the floor.' 'Same-file repeat that is long enough to pass the floor.' >> "$M30/projects/good/memory.md"
sed -i.bak 's/^summary:.*/summary: Frontmatter line that is long enough to pass the length floor/' "$M30/projects/good/memory.md" "$M30/domain/terraform.md"
rm -f "$M30"/projects/good/memory.md.bak "$M30"/domain/terraform.md.bak
run_lint
assert_not_contains "$OUT" "duplicate line" "short, heading, comment, table, frontmatter and same-file repeats never fire the duplicate rule"
rm -rf "$M30"

# --- rule 18: unresolved markers --------------------------------------------
M31="$(new_sandbox)"; export MEMORY_DIR="$M31"; build_clean "$M31"
printf 'Pending: TODO wire the alert.\nNEEDS REVIEW before relying on this.\n' >> "$M31/projects/good/memory.md"
GL="$(grep -n "TODO wire" "$M31/projects/good/memory.md" | cut -d: -f1)"
run_lint
assert_exit 1 "$CODE" "unresolved marker exits 1"
assert_contains "$OUT" "projects/good/memory.md:$GL unresolved marker TODO" "TODO WARN names file:line"
assert_contains "$OUT" "projects/good/memory.md:$((GL + 1)) unresolved marker NEEDS REVIEW" "NEEDS REVIEW WARN names file:line"
rm -rf "$M31"

M32="$(new_sandbox)"; export MEMORY_DIR="$M32"; build_clean "$M32"
cat >> "$M32/domain/terraform.md" <<'EOF'
See todo.md and the TODOs list, or `TODO` in backticks.
```
TODO inside a fence
NEEDS REVIEW inside a fence
```
EOF
sed -i.bak 's/^summary:.*/summary: TODO in frontmatter/' "$M32/domain/terraform.md"; rm -f "$M32/domain/terraform.md.bak"
run_lint
assert_not_contains "$OUT" "unresolved marker" "todo.md, TODOs, backticked and fenced markers and frontmatter never fire the marker rule"
rm -rf "$M32"

# --- rules 17/18: every _template is exempt --------------------------------
M33="$(new_sandbox)"; export MEMORY_DIR="$M33"; build_clean "$M33"
printf '%s\nTODO fill this in\n' "$DUP" > "$M33/domain/_template.md"
printf '%s\nTODO fill this in\n' "$DUP" >> "$M33/projects/good/memory.md"
printf '%s\nTODO fill this in\n' "$DUP" >> "$M33/projects/_template/memory.md"
run_lint
assert_not_contains "$OUT" "_template.md:" "domain/_template.md never appears in rule 17/18 findings"
assert_not_contains "$OUT" "_template/memory.md:" "projects/_template/memory.md never appears in rule 17/18 findings"
assert_not_contains "$OUT" "duplicate line" "a duplicate shared only with _template does not fire"
assert_contains "$OUT" "projects/good/memory.md:" "the non-template file is still scanned"
rm -rf "$M33"

# --- rule 17: fenced lines are never duplicates; fence close needs same char and length ---
M34="$(new_sandbox)"; export MEMORY_DIR="$M34"; build_clean "$M34"
for t in "$M34/projects/good/memory.md" "$M34/domain/terraform.md"; do
    printf '%s\n' '```' "$DUP" '# a shell comment that is long enough to pass the floor' '```' >> "$t"
done
run_lint
assert_not_contains "$OUT" "duplicate line" "fenced duplicate lines and # comments are ignored"
printf '%s\n' '````' '```' 'TODO inside nested fence' '````' 'TODO after nested fence' >> "$M34/projects/good/memory.md"
NL="$(grep -n 'TODO after nested' "$M34/projects/good/memory.md" | cut -d: -f1)"
run_lint
assert_contains "$OUT" "memory.md:$NL unresolved marker TODO" "a longer fence stays open across an inner shorter fence and closes properly"
assert_not_contains "$OUT" "memory.md:$((NL - 2)) unresolved" "marker inside the nested fence does not fire"
rm -rf "$M34"

# --- rules 17/18: HTML comments (mid-line, inline, unclosed, per-file reset) ---
M35="$(new_sandbox)"; export MEMORY_DIR="$M35"; build_clean "$M35"
printf '%s\n' 'visible text <!-- hidden start' 'TODO in commented line' 'NEEDS REVIEW in commented line' 'end --> after' 'fact <!-- TODO: x --> kept' >> "$M35/projects/good/memory.md"
run_lint
assert_not_contains "$OUT" "unresolved marker" "markers inside mid-line and inline HTML comments never fire"
rm -rf "$M35"
M36="$(new_sandbox)"; export MEMORY_DIR="$M36"; build_clean "$M36"
printf '%s\n' 'opened <!-- never closed' >> "$M36/projects/good/memory.md"
printf 'TODO in the next file\n' >> "$M36/domain/terraform.md"
TL="$(grep -n 'TODO in the next' "$M36/domain/terraform.md" | cut -d: -f1)"
run_lint
assert_contains "$OUT" "domain/terraform.md:$TL unresolved marker TODO" "an unclosed comment does not leak into the next file"
rm -rf "$M36"

# --- rule 17: awk failure is an ERROR, never a silent clean ----------------
M37="$(new_sandbox)"; export MEMORY_DIR="$M37"; build_clean "$M37"
chmod 000 "$M37/domain/terraform.md"
if [ ! -r "$M37/domain/terraform.md" ]; then
    run_lint
    assert_contains "$OUT" "ERROR: $M37 lint rules 17/18 could not scan" "unreadable file makes rules 17/18 ERROR"
fi
chmod 644 "$M37/domain/terraform.md"
rm -rf "$M37"

# --- rule 18: TODO boundaries ------------------------------------------------
M38="$(new_sandbox)"; export MEMORY_DIR="$M38"; build_clean "$M38"
printf '%s\n' 'See TODO.md here' 'See TODO/ here' 'A TODO-list item' 'TODOLIST item' > "$M38/domain/terraform.md.add"
cat "$M38/domain/terraform.md.add" >> "$M38/domain/terraform.md"; rm "$M38/domain/terraform.md.add"
run_lint
assert_not_contains "$OUT" "unresolved marker" "TODO.md, TODO/, TODO-list and TODOLIST do not fire"
printf '%s\n' 'TODO: start of line' 'TODO start of line' 'wrapped (TODO) here' 'trailing TODO.' >> "$M38/domain/terraform.md"
TB="$(grep -n 'TODO: start' "$M38/domain/terraform.md" | cut -d: -f1)"
run_lint
assert_contains "$OUT" "terraform.md:$TB unresolved marker TODO" "TODO: at line start fires"
assert_contains "$OUT" "terraform.md:$((TB + 1)) unresolved marker TODO" "TODO followed by space at line start fires"
assert_contains "$OUT" "terraform.md:$((TB + 2)) unresolved marker TODO" "(TODO) fires"
assert_contains "$OUT" "terraform.md:$((TB + 3)) unresolved marker TODO" "TODO. at sentence end fires"
rm -rf "$M38"

# --- rule 17: ordered, plus and blockquote markers are stripped ---------------
M39="$(new_sandbox)"; export MEMORY_DIR="$M39"; build_clean "$M39"
printf '12) %s\n' "$DUP" >> "$M39/projects/good/memory.md"
printf '> + %s\n' "$DUP" >> "$M39/domain/terraform.md"
run_lint
assert_contains "$OUT" "duplicate line in 2 files" "ordered-list and blockquote markers normalise away"
rm -rf "$M39"

# --- rules 17/18: CRLF files --------------------------------------------------
M40="$(new_sandbox)"; export MEMORY_DIR="$M40"; build_clean "$M40"
printf '%s\r\n' '---' 'topic: terraform' 'triggers: [terraform]' 'summary: TODO in crlf frontmatter that is long enough' '---' "$DUP" 'TODO crlf marker' > "$M40/domain/terraform.md"
printf '%s\n' "$DUP" >> "$M40/projects/good/memory.md"
run_lint
assert_contains "$OUT" "duplicate line in 2 files" "a CRLF line matches its LF twin"
assert_contains "$OUT" "terraform.md:7 unresolved marker TODO" "CRLF body line is scanned"
assert_not_contains "$OUT" "terraform.md:4" "CRLF frontmatter is still recognised and skipped"
rm -rf "$M40"

# --- rule 17: WARN text is truncated at a word boundary ----------------------
M41="$(new_sandbox)"; export MEMORY_DIR="$M41"; build_clean "$M41"
LONG='\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9\xc3\xa9 alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu nu xi omicron pi rho sigma tau'
printf "$LONG\n" >> "$M41/projects/good/memory.md"
printf "$LONG\n" >> "$M41/domain/terraform.md"
run_lint
assert_contains "$OUT" "kappa lambda..." "long duplicate is clipped at a word boundary with an ellipsis"
assert_not_contains "$OUT" " mu" "clip does not run past the 80-byte boundary"
rm -rf "$M41"

# --- rules 17/18: a backticked comment opener does not open a comment -------
M42="$(new_sandbox)"; export MEMORY_DIR="$M42"; build_clean "$M42"
printf '%s\n' 'Write comments as `<!--` then text, or ``<!-- x`` too' 'TODO after the backticked opener' "$DUP" >> "$M42/projects/good/memory.md"
printf '%s\n' "$DUP" >> "$M42/domain/terraform.md"
TC="$(grep -n 'TODO after the backticked' "$M42/projects/good/memory.md" | cut -d: -f1)"
run_lint
assert_contains "$OUT" "memory.md:$TC unresolved marker TODO" "marker after a backticked <!-- still fires"
assert_contains "$OUT" "duplicate line in 2 files" "duplicate after a backticked <!-- still fires"
rm -rf "$M42"

# --- rule 17: only the same fence character closes a fence ------------------
M43="$(new_sandbox)"; export MEMORY_DIR="$M43"; build_clean "$M43"
printf '%s\n' '```' '~~~' 'TODO still fenced after a tilde line' '```' 'TODO after the real close' >> "$M43/projects/good/memory.md"
FL="$(grep -n 'TODO after the real' "$M43/projects/good/memory.md" | cut -d: -f1)"
run_lint
assert_contains "$OUT" "memory.md:$FL unresolved marker TODO" "marker after the real close fires"
assert_not_contains "$OUT" "memory.md:$((FL - 2)) unresolved" "a ~~~ line does not close a backtick fence"
rm -rf "$M43"

# --- rule 18: NEEDS REVIEW needs a trailing word boundary --------------------
M44="$(new_sandbox)"; export MEMORY_DIR="$M44"; build_clean "$M44"
printf '%s\n' 'Ask the NEEDS REVIEWER about it' 'NEEDS REVIEW: confirm' >> "$M44/domain/terraform.md"
RL="$(grep -n 'NEEDS REVIEW:' "$M44/domain/terraform.md" | cut -d: -f1)"
run_lint
assert_contains "$OUT" "terraform.md:$RL unresolved marker NEEDS REVIEW" "NEEDS REVIEW followed by punctuation fires"
assert_not_contains "$OUT" "terraform.md:$((RL - 1)) unresolved" "NEEDS REVIEWER does not fire"
rm -rf "$M44"

# --- rule 17/18: inline triple backticks are not a fence opener -------------
M45="$(new_sandbox)"; export MEMORY_DIR="$M45"; build_clean "$M45"
printf '%s\n' '```bash foo``` is the entrypoint' 'TODO after the inline triple backticks' "$DUP" >> "$M45/projects/good/memory.md"
printf '%s\n' "$DUP" >> "$M45/domain/terraform.md"
IL="$(grep -n 'TODO after the inline' "$M45/projects/good/memory.md" | cut -d: -f1)"
run_lint
assert_contains "$OUT" "memory.md:$IL unresolved marker TODO" "marker after an inline-triple-backtick line fires"
assert_contains "$OUT" "duplicate line in 2 files" "duplicate after an inline-triple-backtick line fires"
rm -rf "$M45"

# --- rule 18: double-backtick spans, TODO. punctuation -----------------------
M46="$(new_sandbox)"; export MEMORY_DIR="$M46"; build_clean "$M46"
printf '%s\n' 'Mention ``TODO`` and ``a `TODO` b`` in code' 'See TODO.md and TODO.x here' '(TODO.) one' 'say "TODO." two' 'list TODO., three' 'end TODO.' >> "$M46/domain/terraform.md"
DL="$(grep -n '(TODO.) one' "$M46/domain/terraform.md" | cut -d: -f1)"
run_lint
assert_not_contains "$OUT" "terraform.md:$((DL - 2)) unresolved" "double-backtick spans do not fire"
assert_not_contains "$OUT" "terraform.md:$((DL - 1)) unresolved" "TODO.md and TODO.x do not fire"
assert_contains "$OUT" "terraform.md:$DL unresolved marker TODO" "(TODO.) fires"
assert_contains "$OUT" "terraform.md:$((DL + 1)) unresolved marker TODO" "TODO. before a quote fires"
assert_contains "$OUT" "terraform.md:$((DL + 2)) unresolved marker TODO" "TODO., fires"
assert_contains "$OUT" "terraform.md:$((DL + 3)) unresolved marker TODO" "TODO. at end of line fires"
rm -rf "$M46"

# --- rule 17: finding starts with a file:line, not a fake file ---------------
M47="$(new_sandbox)"; export MEMORY_DIR="$M47"; build_clean "$M47"
printf '%s\n' "$DUP" >> "$M47/projects/good/memory.md"
printf '%s\n' "$DUP" >> "$M47/domain/terraform.md"
run_lint
assert_contains "$OUT" "WARN:  $M47/projects/good/memory.md:" "duplicate WARN leads with the first file:line"
assert_contains "$OUT" "duplicate line in 2 files (also $M47/domain/terraform.md:" "duplicate WARN lists the other locations"
rm -rf "$M47"

finish
