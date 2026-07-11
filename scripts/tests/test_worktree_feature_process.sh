#!/usr/bin/env bash
# Validates the DOCUMENTED worktree feature process for the two harnesses that
# have no in-session EnterWorktree (Codex, Antigravity): create a worktree, open
# the session IN it, and both the context read and the checkpoint write route to
# working.<wt>.md. Uses the realistic topology — worktree under .claude/worktrees/,
# project marker only at the repo root (walk-up), memory tree a SEPARATE dir from
# the code repo — so this guards the actual deployment shape, not a toy sibling.
. "$(dirname "$0")/_assert.sh"

if ! command -v git >/dev/null 2>&1; then printf '  SKIP git unavailable\n'; finish; fi

REPO_ROOT="$(cd "$SCRIPTS_DIR/.." && pwd)"
MEM="$(new_sandbox)"; CODE="$(new_sandbox)"; BIN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$CODE" "$BIN"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOF
# Distinct content in base vs overlay so we can prove WHICH file was used.
printf '# Working\n\nBASE-SCRATCH\n'      > "$MEM/projects/proj/working.md"
printf '# Working\n\nWT-FEATURE-SCRATCH\n' > "$MEM/projects/proj/working.feat.md"

# Code repo (separate from MEM); marker ONLY at the root; worktree under .claude/worktrees/.
git -C "$CODE" init -q
git -C "$CODE" -c user.name=T -c user.email=t@e commit --allow-empty -qm init
mkdir -p "$CODE/.agents"; printf 'proj\n' > "$CODE/.agents/memory-project"
git -C "$CODE" worktree add -q -b feat "$CODE/.claude/worktrees/feat" 2>/dev/null
WT="$CODE/.claude/worktrees/feat"

# ============ CODEX PROCESS: `git worktree add` + run codex in the worktree ============
# Stub codex so codex-mem.sh runs without the real binary.
cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/codex"; export PATH="$BIN:$PATH"
export CODEX_INSTRUCTIONS_FILE="$BIN/AGENTS.md"

# Step 1 — context build from within the worktree -> overlay, not base.
( cd "$WT" && bash "$REPO_ROOT/harnesses/codex/scripts/codex-mem.sh" ) >/dev/null 2>&1
body="$(cat "$BIN/AGENTS.md" 2>/dev/null)"
assert_contains     "$body" "WT-FEATURE-SCRATCH" "codex process: context build reads the worktree overlay"
assert_not_contains "$body" "BASE-SCRATCH"        "codex process: context build does NOT read the base"

# Step 2 — checkpoint writer from within the worktree -> overlay target.
ck="$( cd "$WT" && bash "$REPO_ROOT/harnesses/codex/scripts/codex-mem-checkpoint.sh" --for-codex )"
assert_contains "$ck" "WORKING_MD: $MEM/projects/proj/working.feat.md" \
    "codex process: checkpoint writer targets the worktree overlay"

# ============ ANTIGRAVITY PROCESS: `git worktree add` + open the worktree as a workspace ============
# Stub agy so agy.sh runs without the real binary; capture the env it exports.
ENVCAP="$BIN/agy-env"
cat > "$BIN/agy" <<EOF
#!/usr/bin/env bash
printf 'CWD=%s\n' "\${AI_MEMORY_CWD:-}" > "$ENVCAP"
exit 0
EOF
chmod +x "$BIN/agy"

# Step 1 — launching agy FROM the worktree exports AI_MEMORY_CWD = the worktree
# (this is "open the worktree as a workspace").
( cd "$WT" && bash "$REPO_ROOT/harnesses/antigravity/scripts/agy.sh" -p x ) >/dev/null 2>&1
assert_contains "$(cat "$ENVCAP")" "CWD=$WT" "antigravity process: opening the worktree exports it as AI_MEMORY_CWD"

# Step 2 — preinvocation with that cwd injects the overlay, not the base.
OUT="$(printf '{"invocationNum":0}' \
    | AI_MEMORY_PROJECT=proj AI_MEMORY_CWD="$WT" MEMORY_DIR="$MEM" \
      bash "$REPO_ROOT/harnesses/antigravity/hooks/preinvocation.sh")"
assert_contains     "$OUT" "WT-FEATURE-SCRATCH" "antigravity process: preinvocation injects the worktree overlay"
assert_not_contains "$OUT" "BASE-SCRATCH"         "antigravity process: preinvocation does NOT inject the base"

finish
