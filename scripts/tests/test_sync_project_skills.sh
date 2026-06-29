#!/usr/bin/env bash
# Tests for scripts/sync-project-skills.sh — project-scoped skill fan-out.
# Focus: repo_path resolution via the shared resolve_repo_path (relative to
# AI_MEMORY_PROJECTS_ROOT, the $MEMORY_DIR sentinel, unresolvable), plus link/
# copy/list/idempotency behavior. Pure bash 3.2; isolated MEMORY_ROOT + root.
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

run() { MEMORY_ROOT="$MEM" bash "$SYNC" "$@" 2>&1; }

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

finish
