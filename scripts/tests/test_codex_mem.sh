#!/usr/bin/env bash
# codex-mem.sh: AGENTS.md section build order + --executor flag expansion.
# Uses a stub `codex` on PATH that records its args, so no real codex is needed.
. "$(dirname "$0")/_assert.sh"

MEM="$(new_sandbox)"
BIN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

# Active project with non-empty working.md (so the WORKING section is emitted).
mkdir -p "$MEM/projects/proj"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOF
printf '# Working\n\nactive scratch\n' > "$MEM/projects/proj/working.md"
# Project resolves only from a cwd marker now (no .active_project fallback).
WORK="$MEM/work"; mkdir -p "$WORK/.claude"; printf 'proj\n' > "$WORK/.claude/memory-project"

# Stub codex that records args then exits 0.
CAPTURE="$BIN/codex-args"
cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
printf '%s ' "\$@" > "$CAPTURE"
exit 0
EOF
chmod +x "$BIN/codex"
export PATH="$BIN:$PATH"

AGENTS="$BIN/AGENTS.md"
export CODEX_INSTRUCTIONS_FILE="$AGENTS"
OVERLAY="$BIN/AGENTS.local.md"
printf 'my permanent overlay line\n' > "$OVERLAY"
export CODEX_OVERLAY_FILE="$OVERLAY"

# --- interactive (no executor): builds AGENTS.md ---
set +e
(cd "$WORK" && bash "$SCRIPTS_DIR/../harnesses/codex/scripts/codex-mem.sh") >/dev/null 2>&1; CODE=$?
set -e
assert_exit 0 "$CODE" "codex-mem (interactive) exits 0 via stub"
assert_file "$AGENTS" "AGENTS.md generated"

# Build order: collect the === headers in file order, compare to expected sequence.
order="$(grep '^# === ' "$AGENTS" | tr '\n' '|')"
expected="# === IDENTITY ===|# === PROJECT: proj ===|# === MEMORY INDEX ===|# === DOMAIN INDEX ===|# === WORKING MEMORY ===|# === LOCAL OVERLAY ===|"
assert_eq "$expected" "$order" "AGENTS.md section build order"

body="$(cat "$AGENTS")"
assert_contains "$body" "active scratch"            "working memory included"
assert_contains "$body" "my permanent overlay line" "local overlay appended"
assert_contains "$body" "terraform"                 "domain index row present"

# --- executor mode: flag expansion captured by stub ---
: > "$CAPTURE"
set +e
(cd "$WORK" && bash "$SCRIPTS_DIR/../harnesses/codex/scripts/codex-mem.sh" --executor "do the thing") >/dev/null 2>&1; CODE=$?
set -e
assert_exit 0 "$CODE" "executor mode exits 0 via stub"
args="$(cat "$CAPTURE")"
assert_contains "$args" "exec --sandbox workspace-write" "executor: exec + workspace-write"
assert_contains "$args" "--skip-git-repo-check"          "executor: skip-git-repo-check"
assert_contains "$args" "sandbox_workspace_write.network_access=true" "executor: network access on"
assert_contains "$args" "do the thing"                   "executor: passes through the prompt"

finish
