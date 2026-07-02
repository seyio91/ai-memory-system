#!/usr/bin/env bash
# memory-pin.sh: forward .claude/memory-project + reverse frontmatter (repo,
# repo_path), body preserved, idempotent, resolves after pin, arg/error codes.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
ROOT="$(new_sandbox)"
trap 'rm -rf "$MEM" "$ROOT"' EXIT
export MEMORY_DIR="$MEM"
export AI_MEMORY_PROJECTS_ROOT="$ROOT"
. "$SCRIPTS_DIR/_lib.sh"

# Project memory with a body sentinel to prove byte-intact preservation.
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: a project
---

# Project: proj

## What It Is
BODY-SENTINEL-LINE
EOF

# Real git checkout under the projects root.
CO="$ROOT/mycode"
URL="git@github.com:org/mycode.git"
mkdir -p "$CO"
( cd "$CO" && git init -q && git remote add origin "$URL" )

PIN="$SCRIPTS_DIR/memory-pin.sh"
MF="$MEM/projects/proj/memory.md"

# --- missing arg -> exit 2 ---
set +e
out=$(cd "$CO" && bash "$PIN" 2>&1); code=$?
set -e
assert_exit 2 "$code" "missing arg exits 2"

# --- unknown project -> exit 1 ---
set +e
out=$(cd "$CO" && bash "$PIN" nope 2>&1); code=$?
set -e
assert_exit 1 "$code" "unknown project exits 1"

# --- pin from inside checkout ---
set +e
out=$(cd "$CO" && bash "$PIN" proj 2>&1); code=$?
set -e
assert_exit 0 "$code" "pin exits 0"
assert_file "$CO/.claude/memory-project" "forward marker written"
assert_eq "proj" "$(cat "$CO/.claude/memory-project")" "forward marker names project"
assert_eq "$URL" "$(extract_fm_field "$MF" repo)" "frontmatter repo = origin url"
assert_eq "mycode" "$(extract_fm_field "$MF" repo_path)" "frontmatter repo_path = root-relative"
assert_contains "$(cat "$MF")" "BODY-SENTINEL-LINE" "body preserved"
assert_contains "$(cat "$MF")" "## What It Is" "body sections preserved"

# --- idempotent: re-run, no duplicate keys ---
set +e
out=$(cd "$CO" && bash "$PIN" proj 2>&1); code=$?
set -e
assert_exit 0 "$code" "re-pin exits 0"
assert_eq "1" "$(grep -c '^repo:' "$MF")" "single repo: line after re-pin"
assert_eq "1" "$(grep -c '^repo_path:' "$MF")" "single repo_path: line after re-pin"

# --- resolves via resolve_repo_path after pin ---
assert_eq "$ROOT/mycode" "$(resolve_repo_path proj)" "pinned project resolves to checkout"

# --- --category writes the category frontmatter, preserves body, single line ---
set +e
out=$(cd "$CO" && bash "$PIN" proj --category acme-corp 2>&1); code=$?
set -e
assert_exit 0 "$code" "pin --category exits 0"
assert_eq "acme-corp" "$(extract_fm_field "$MF" category)" "frontmatter category set"
assert_eq "1" "$(grep -c '^category:' "$MF")" "single category: line"
assert_contains "$(cat "$MF")" "BODY-SENTINEL-LINE" "body preserved after --category"
assert_eq "mycode" "$(extract_fm_field "$MF" repo_path)" "repo_path still intact after --category"

# --- --category=<v> form + update-in-place (no duplicate) ---
set +e
out=$(cd "$CO" && bash "$PIN" proj --category=beta-inc 2>&1); code=$?
set -e
assert_exit 0 "$code" "pin --category=<v> exits 0"
assert_eq "beta-inc" "$(extract_fm_field "$MF" category)" "category updated in place"
assert_eq "1" "$(grep -c '^category:' "$MF")" "still single category: line after update"

# --- omitting --category leaves an existing category untouched ---
set +e
out=$(cd "$CO" && bash "$PIN" proj 2>&1); code=$?
set -e
assert_exit 0 "$code" "re-pin without --category exits 0"
assert_eq "beta-inc" "$(extract_fm_field "$MF" category)" "category preserved when --category omitted"

# --- --category with no value -> exit 2 ---
set +e
out=$(cd "$CO" && bash "$PIN" proj --category 2>&1); code=$?
set -e
assert_exit 2 "$code" "--category without value exits 2"

finish
