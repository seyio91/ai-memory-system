#!/usr/bin/env bash
# Golden test: the codex-mem AGENTS.md build is pinned byte-for-byte against
# scripts/tests/fixtures/codex_agents.golden. Guards the content-core + md
# formatter refactor (and any future change to it) from silently drifting the
# file-materialize output. Sandbox paths are normalized to __MEM__/__BIN__ so the
# fixture is machine-independent.
. "$(dirname "$0")/_assert.sh"

FIXTURE="$(dirname "$0")/fixtures/codex_agents.golden"

MEM="$(new_sandbox)"; BIN="$(new_sandbox)"
trap 'rm -rf "$MEM" "$BIN"' EXIT
export MEMORY_DIR="$MEM"
seed_min_tree "$MEM"

# Active project with non-empty working.md (so PROJECT + WORKING sections emit).
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
WORK="$MEM/work"; mkdir -p "$WORK/.claude"; printf 'proj\n' > "$WORK/.claude/memory-project"

# Stub codex (build path only; we never exec the real thing).
cat > "$BIN/codex" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$BIN/codex"; export PATH="$BIN:$PATH"

AGENTS="$BIN/AGENTS.md"; export CODEX_INSTRUCTIONS_FILE="$AGENTS"
OVERLAY="$BIN/AGENTS.local.md"; printf 'my permanent overlay line\n' > "$OVERLAY"
export CODEX_OVERLAY_FILE="$OVERLAY"

(cd "$WORK" && bash "$SCRIPTS_DIR/codex-mem.sh") >/dev/null 2>&1
assert_file "$AGENTS" "AGENTS.md generated"

got="$(sed "s|$MEM|__MEM__|g; s|$BIN|__BIN__|g" "$AGENTS")"
want="$(cat "$FIXTURE")"
assert_eq "$want" "$got" "AGENTS.md byte-for-byte matches golden fixture"

finish
