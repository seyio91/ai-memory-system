#!/usr/bin/env bash
# Tests for scripts/sync-project-skills.sh — project-scoped skill fan-out.
# Focus: repo_path resolution via the shared resolve_repo_path (relative to
# AI_MEMORY_PROJECTS_ROOT, the $MEMORY_DIR sentinel, unresolvable), plus link/
# copy/list/idempotency behavior. Pure bash 3.2; isolated MEMORY_DIR + root.
. "$(dirname "$0")/_assert.sh"

SYNC="$SCRIPTS_DIR/sync-project-skills.sh"

MEM="$(new_sandbox)"          # the memory tree (projects/<p>/skills/<s>/SKILL.md live here)
ROOT="$(new_sandbox)"         # where code checkouts live (AI_MEMORY_PROJECTS_ROOT)
export AI_MEMORY_PROJECTS_ROOT="$ROOT"
trap 'rm -rf "$MEM" "$ROOT"' EXIT

# mk_project <project> <repo_path-value> — scaffold a project + one skill.
mk_project() {
    local proj="$1" rpval="$2"
    mkdir -p "$MEM/projects/$proj/skills/$proj-skill"
    printf '# %s skill\n' "$proj" > "$MEM/projects/$proj/skills/$proj-skill/SKILL.md"
    cat > "$MEM/projects/$proj/memory.md" <<EOF
---
topic: $proj
scope: project
summary: s
repo_path: $rpval
---
EOF
}

run() { MEMORY_DIR="$MEM" bash "$SYNC" "$@" 2>&1; }

# --- relative repo_path resolves and links (the core regression) ---
mkdir -p "$ROOT/myrepo"
mk_project relproj myrepo
out="$(run --harness claude relproj)"
assert_contains "$out" "link: relproj/relproj-skill" "relative repo_path links"
assert_not_contains "$out" "normalize first" "no stale normalize-first rejection"
assert_file "$ROOT/myrepo/.claude/skills/relproj-skill" "symlink created under resolved checkout"
assert_eq "$MEM/projects/relproj/skills/relproj-skill" \
          "$(readlink "$ROOT/myrepo/.claude/skills/relproj-skill")" \
          "symlink points back to the canonical store"

# --- second run is idempotent ---
out="$(run --harness claude relproj)"
assert_contains "$out" "already-current/skipped" "re-run is idempotent"

# --- $MEMORY_DIR sentinel resolves to the memory tree itself ---
mk_project metaproj '$MEMORY_DIR'
run --harness claude metaproj >/dev/null
assert_file "$MEM/.claude/skills/metaproj-skill" "\$MEMORY_DIR sentinel resolves to memory tree"

# --- unresolvable repo_path (missing dir, no remote) -> warn + skip ---
mk_project ghostproj does-not-exist-anywhere
out="$(run --harness claude ghostproj)"
assert_contains "$out" "cannot resolve" "unresolvable repo_path warns"
assert_contains "$out" "1 warnings" "skips the one project, no crash"

# --- --list prints the absolute resolved target ---
out="$(run --harness claude --list relproj)"
assert_contains "$out" "$ROOT/myrepo/.claude/skills/relproj-skill" "--list shows absolute resolved target"

# --- copy mode materializes the SKILL.md in the repo ---
mkdir -p "$ROOT/copyrepo"
mk_project copyproj copyrepo
run --harness claude --mode copy copyproj >/dev/null
assert_file "$ROOT/copyrepo/.claude/skills/copyproj-skill/SKILL.md" "copy mode copies the skill into the repo"

# --- MEMORY_DIR selects the tree; it used to be clobbered ---------------------
# The script assigned MEMORY_DIR="$MEM" BEFORE sourcing _lib.sh, so a user-set
# MEMORY_DIR was discarded and the SELF-LOCATED tree synced instead — silently,
# and into whatever real repos that tree points at. The sandbox here holds only
# `relproj`, so if resolution regresses to self-location the listing names some
# other project (or nothing) and these assertions fail.
out="$(MEMORY_DIR="$MEM" bash "$SYNC" --harness claude --list relproj)"
assert_contains "$out" "relproj/relproj-skill" "MEMORY_DIR selects the tree to sync"
assert_not_contains "$out" "WARN: MEMORY_ROOT" "no deprecation notice when MEMORY_ROOT is unset"

# A tree with no projects/ at all must fail loudly rather than silently falling
# back to self-location — the fail-closed half of the same bug.
EMPTY="$(new_sandbox)"
set +e
out="$(MEMORY_DIR="$EMPTY" bash "$SYNC" --harness claude --list 2>&1)"; code=$?
set -e
assert_exit 1 "$code" "MEMORY_DIR pointing at a tree with no projects/ exits 1"
assert_contains "$out" "no projects dir" "…and says so rather than syncing another tree"
rm -rf "$EMPTY"

# --- MEMORY_ROOT still works, but warns (deprecated alias) --------------------
# Honoured deliberately: silently ignoring it would reintroduce the very
# wrong-tree failure above for anyone who had set it.
out="$(MEMORY_ROOT="$MEM" bash "$SYNC" --harness claude --list relproj 2>&1)"
assert_contains "$out" "relproj/relproj-skill" "MEMORY_ROOT is still honoured"
assert_contains "$out" "MEMORY_ROOT is deprecated" "…and prints a deprecation notice"

# MEMORY_ROOT wins over MEMORY_DIR while the shim exists, so anyone who set both
# keeps the tree they had rather than silently switching.
out="$(MEMORY_ROOT="$MEM" MEMORY_DIR="$ROOT" bash "$SYNC" --harness claude --list relproj 2>&1)"
assert_contains "$out" "relproj/relproj-skill" "MEMORY_ROOT takes precedence over MEMORY_DIR"

finish
