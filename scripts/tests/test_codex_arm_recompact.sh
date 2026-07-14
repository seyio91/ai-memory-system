#!/usr/bin/env bash
# Codex arm_recompact.sh: SessionStart(source=compact) writes the .recompact
# sentinel that inject.sh consumes on the next prompt; every other input is a no-op.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
ARM="$REPO/harnesses/codex/hooks/arm_recompact.sh"

MEM="$(new_sandbox)"
WORK="$(new_sandbox)"
trap 'rm -rf "$MEM" "$WORK"' EXIT
export MEMORY_DIR="$MEM"

seed_min_tree "$MEM"
mkdir -p "$MEM/projects/proj" "$WORK/.agents"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
---
# Project: proj
EOF
printf 'proj\n' > "$WORK/.agents/memory-project"

payload() {  # source cwd session_id
    printf '{"source":"%s","cwd":"%s","session_id":"%s"}' "$1" "$2" "$3"
}

# 1. source=compact in a project cwd -> sentinel written, no stdout.
STATE="$MEM/state-compact"
out="$(payload compact "$WORK" cx-compact | MEMORY_STATE_DIR="$STATE" bash "$ARM")"
assert_eq "" "$out" "arm: compact emits no inline output"
assert_file "$STATE/cx-compact.recompact" "arm: compact writes sentinel"

# 2. source=startup -> no sentinel (a normal restart must not force a re-inject).
STATE2="$MEM/state-startup"
payload startup "$WORK" cx-start | MEMORY_STATE_DIR="$STATE2" bash "$ARM" >/dev/null
[ ! -e "$STATE2/cx-start.recompact" ] && _ok "arm: startup does not write sentinel" \
    || _bad "arm: startup does not write sentinel"

# 2b. no `source` field (PreCompact/PostCompact shape) -> sentinel written. Keeps the
# event choice pure manifest config: the script arms regardless of which compaction
# event the manifest wires, rejecting only an explicit non-compact source.
STATE_NS="$MEM/state-nosource"
out_ns="$(printf '{"trigger":"auto","cwd":"%s","session_id":"cx-precompact"}' "$WORK" \
    | MEMORY_STATE_DIR="$STATE_NS" bash "$ARM")"
assert_eq "" "$out_ns" "arm: no-source event emits no inline output"
assert_file "$STATE_NS/cx-precompact.recompact" "arm: no-source (Pre/PostCompact) writes sentinel"

# 3. source=compact but cwd has no project -> no sentinel.
STATE3="$MEM/state-noproj"
NOPROJ="$(new_sandbox)"
payload compact "$NOPROJ" cx-noproj | MEMORY_STATE_DIR="$STATE3" bash "$ARM" >/dev/null
[ ! -e "$STATE3/cx-noproj.recompact" ] && _ok "arm: compact without project writes no sentinel" \
    || _bad "arm: compact without project writes no sentinel"
rm -rf "$NOPROJ"

finish
