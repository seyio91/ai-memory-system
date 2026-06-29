#!/usr/bin/env bash
# _lib.sh: detect_active_project (pin / fallback / none) + extract_fm_field.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
trap 'rm -rf "$MEM"' EXIT
export MEMORY_DIR="$MEM"

. "$SCRIPTS_DIR/_lib.sh"

# --- extract_fm_field ---
mkdir -p "$MEM/domain"
cat > "$MEM/d.md" <<'EOF'
---
topic: terraform
triggers: [tf, hcl]
summary: A one line summary
---
body
EOF
assert_eq "terraform" "$(extract_fm_field "$MEM/d.md" topic)" "extract_fm_field topic"
assert_eq "A one line summary" "$(extract_fm_field "$MEM/d.md" summary)" "extract_fm_field summary"
assert_eq "" "$(extract_fm_field "$MEM/d.md" nope)" "extract_fm_field missing -> empty"

printf 'no frontmatter here\n' > "$MEM/plain.md"
assert_eq "" "$(extract_fm_field "$MEM/plain.md" topic)" "extract_fm_field no-fm -> empty"

# --- detect_active_project: .active_project global is NOT a fallback ---
printf 'stale-global\n' > "$MEM/.active_project"
assert_eq "" "$(detect_active_project "$MEM/projects")" "global .active_project ignored (no fallback)"

# --- detect_active_project: in-repo marker resolved by walking up ---
REPO="$MEM/repo/sub"
mkdir -p "$REPO/.git" "$MEM/repo/.claude"
printf 'pinned-proj\n' > "$MEM/repo/.claude/memory-project"
assert_eq "pinned-proj" "$(detect_active_project "$REPO")" "marker resolved (walks up)"

# --- detect_active_project: none ---
rm -f "$MEM/.active_project"
EMPTY="$(new_sandbox)"
assert_eq "" "$(detect_active_project "$EMPTY")" "no marker -> empty"
rm -rf "$EMPTY"

# --- projects_root: default + env override ---
unset AI_MEMORY_PROJECTS_ROOT
assert_eq "$HOME/Projects" "$(projects_root)" "projects_root default"
export AI_MEMORY_PROJECTS_ROOT="/tmp/some-root"
assert_eq "/tmp/some-root" "$(projects_root)" "projects_root env override"

# --- resolve_repo_path: primary hit (relative repo_path) ---
ROOT="$(new_sandbox)"
export AI_MEMORY_PROJECTS_ROOT="$ROOT"
mkdir -p "$ROOT/myrepo"
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: s
repo_path: myrepo
---
# body
EOF
out=$(resolve_repo_path proj); code=$?
assert_exit 0 "$code" "resolve_repo_path primary hit returns 0"
assert_eq "$ROOT/myrepo" "$out" "resolve_repo_path primary hit -> root/repo_path"

# --- resolve_repo_path: absolute repo_path ---
ABS="$(new_sandbox)"
mkdir -p "$MEM/projects/absproj"
cat > "$MEM/projects/absproj/memory.md" <<EOF
---
topic: absproj
scope: project
summary: s
repo_path: $ABS
---
EOF
assert_eq "$ABS" "$(resolve_repo_path absproj)" "resolve_repo_path absolute repo_path"
rm -rf "$ABS"

# --- resolve_repo_path: git-remote fallback when repo_path dir is gone ---
URL="git@github.com:org/sibling.git"
SIB="$ROOT/sibling-checkout"
mkdir -p "$SIB"
( cd "$SIB" && git init -q && git remote add origin "$URL" )
mkdir -p "$MEM/projects/fbproj"
cat > "$MEM/projects/fbproj/memory.md" <<EOF
---
topic: fbproj
scope: project
summary: s
repo: $URL
repo_path: does-not-exist-here
---
EOF
out=$(resolve_repo_path fbproj); code=$?
assert_exit 0 "$code" "resolve_repo_path remote fallback returns 0"
assert_eq "$SIB" "$out" "resolve_repo_path remote fallback -> matching sibling"

# --- resolve_repo_path: miss -> empty + exit 1 ---
mkdir -p "$MEM/projects/missproj"
cat > "$MEM/projects/missproj/memory.md" <<'EOF'
---
topic: missproj
scope: project
summary: s
---
EOF
out=$(resolve_repo_path missproj); code=$?
assert_exit 1 "$code" "resolve_repo_path miss returns 1"
assert_eq "" "$out" "resolve_repo_path miss -> empty"
rm -rf "$ROOT"

# --- MEMORY_DIR self-locating default (no MEMORY_DIR set) ---
# With MEMORY_DIR unset, sourcing scripts/_lib.sh must resolve MEMORY_DIR to the
# memory root (parent of scripts/) via BASH_SOURCE. Computed from SCRIPTS_DIR so
# the test is independent of the install's absolute path. Runs under bash, where
# BASH_SOURCE is populated (it is empty under zsh).
EXPECTED_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
got=$( unset MEMORY_DIR; . "$SCRIPTS_DIR/_lib.sh"; printf '%s' "$MEMORY_DIR" )
assert_eq "$EXPECTED_ROOT" "$got" "MEMORY_DIR default self-locates to memory root"

finish
