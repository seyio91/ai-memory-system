#!/usr/bin/env bash
# Golden test: the build-context-md.sh file-materialize output is pinned
# byte-for-byte against scripts/tests/fixtures/codex_agents.golden. Guards the
# content-core + md formatter (and any future change to it) from silently
# drifting. Post-flip, no registered harness builds a context file at launch
# (codex injects via SessionStart) — the builder stays as the generic
# refresh=launch engine capability, exercised here directly. Sandbox paths are
# normalized to __MEM__/__BIN__ so the fixture is machine-independent.
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
WORK="$MEM/work"; mkdir -p "$WORK/.agents"; printf 'proj\n' > "$WORK/.agents/memory-project"

AGENTS="$BIN/AGENTS.md"
OVERLAY="$BIN/AGENTS.local.md"; printf 'my permanent overlay line\n' > "$OVERLAY"

(cd "$WORK" && bash "$SCRIPTS_DIR/build-context-md.sh" "$AGENTS" "codex-mem" "$OVERLAY") >/dev/null 2>&1
assert_file "$AGENTS" "AGENTS.md generated"

got="$(sed "s|$MEM|__MEM__|g; s|$BIN|__BIN__|g" "$AGENTS")"
want="$(cat "$FIXTURE")"
assert_eq "$want" "$got" "AGENTS.md byte-for-byte matches golden fixture"

finish
