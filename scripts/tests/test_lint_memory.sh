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

## Current State
x

## Architecture Decisions
x

## Known Constraints / Gotchas
x

## Current Goal
x
EOF
    MEMORY_DIR="$m" bash "$SCRIPTS_DIR/regenerate-index.sh" >/dev/null
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
grep -v '^## Current Goal$' "$M3/projects/good/memory.md" > "$M3/projects/good/memory.md.tmp"
mv "$M3/projects/good/memory.md.tmp" "$M3/projects/good/memory.md"
run_lint
assert_exit 1 "$CODE" "missing section exits 1"
assert_contains "$OUT" "Current Goal" "names the missing section"
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
## Current State
x
## Architecture Decisions
x
## Known Constraints / Gotchas
x
## Current Goal
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

finish
