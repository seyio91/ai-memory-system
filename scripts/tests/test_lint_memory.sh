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

# --- valid repo_path + matching back-pin -> exit 0 ---
M4="$(new_sandbox)"; export MEMORY_DIR="$M4"; build_clean "$M4"
R4="$(new_sandbox)"; export AI_MEMORY_PROJECTS_ROOT="$R4"
mkdir -p "$R4/good-co/.claude"; printf 'good\n' > "$R4/good-co/.claude/memory-project"
set_fm "$M4/projects/good/memory.md" repo_path good-co
run_lint
assert_exit 0 "$CODE" "valid repo_path + matching back-pin -> 0"
rm -rf "$M4" "$R4"

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
mkdir -p "$R6/good-co/.claude"; printf 'WRONG\n' > "$R6/good-co/.claude/memory-project"
set_fm "$M6/projects/good/memory.md" repo_path good-co
run_lint
assert_exit 1 "$CODE" "wrong back-pin exits 1"
assert_contains "$OUT" "WRONG" "reports the wrong back-pin value"
rm -rf "$M6" "$R6"
unset AI_MEMORY_PROJECTS_ROOT

finish
