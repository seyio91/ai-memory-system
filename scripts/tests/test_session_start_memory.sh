#!/usr/bin/env bash
# scripts/hooks/session_start_memory.sh -- compaction-arm behaviour:
# SessionStart(source=compact) writes the .recompact sentinel that inject.sh
# consumes on the next prompt; startup injects the base instead of arming.
#
# Was test_codex_arm_recompact.sh, exercising the codex shim that delegated here.
# The shim is deleted; every assertion below was always about THIS script's
# behaviour, so they carry over unchanged. Renamed so run-tests.sh --changed maps
# session_start_memory.sh -> test_session_start_memory.sh by naming convention
# rather than relying on the basename-grep fallback.
. "$(dirname "$0")/_assert.sh"

REPO="$(cd "$SCRIPTS_DIR/.." && pwd)"
ARM="$REPO/scripts/hooks/session_start_memory.sh"

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

startup_context() { # session_id
    local output rc
    if output="$(payload startup "$WORK" "$1" | bash "$ARM" 2>/dev/null)"; then
        rc=0
    else
        rc=$?
    fi
    assert_exit 0 "$rc" "startup: $1 exits 0"
    STARTUP_CONTEXT="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"], end="")' <<<"$output")"
}

assert_working_tail() { # payload label
    local wanted
    wanted="$(printf 'WORKING-TAIL\n</memory:working>')"
    case "$1" in
        *"$wanted") _ok "$2: working tail intact" ;;
        *) _bad "$2: working tail intact" ;;
    esac
}

mkdir -p "$MEM/.agents" "$MEM/projects/proj/plans" "$MEM/initiatives" "$MEM/scripts"
cp "$REPO/scripts/initiative-status.sh" "$MEM/scripts/initiative-status.sh"
cp "$REPO/scripts/_lib.sh" "$MEM/scripts/_lib.sh"
printf 'proj\n' > "$MEM/.agents/memory-project"
cat > "$MEM/projects/proj/memory.md" <<'EOF'
---
topic: proj
scope: project
summary: proj summary
repo_path: $MEMORY_DIR
---
# Project: proj
EOF
printf '# Todo\n' > "$MEM/projects/proj/todo.md"
printf '%s\n' '---' 'plan: seeded' 'status: draft' '---' > "$MEM/projects/proj/plans/seeded.md"
printf '# Working\n\nWORKING-TAIL\n' > "$MEM/projects/proj/working.md"
cat > "$MEM/initiatives/dispatch.md" <<'EOF'
---
kind: initiative
slug: dispatch
status: active
created: 2026-08-15
---
# Dispatch
## Targets
### proj/seeded
- execution_mode: software_adw
- plan: projects/proj/plans/seeded.md
- stages: discover -> plan -> implement -> validate
- depends_on: none
## Closure
Open.
EOF

# First startup seeds the snapshot; advancing the plan without a stream entry is stale.
startup_context initiative-fresh
fresh_payload="$STARTUP_CONTEXT"
assert_not_contains "$fresh_payload" 'initiative-alert' "initiative alert: fresh Target is silent"
assert_working_tail "$fresh_payload" "initiative alert: fresh Target"
sed 's/^status: draft$/status: in_progress/' "$MEM/projects/proj/plans/seeded.md" > "$MEM/projects/proj/plans/seeded.next"
mv "$MEM/projects/proj/plans/seeded.next" "$MEM/projects/proj/plans/seeded.md"
startup_context initiative-stale
stale_payload="$STARTUP_CONTEXT"
stale_count="$(printf '%s' "$stale_payload" | grep -o '<memory:initiative-alert>' | wc -l | tr -d '[:space:]')"
assert_eq 1 "$stale_count" "initiative alert: exactly one block for stale Target"
assert_contains "$stale_payload" 'WARN: proj/seeded advanced (plan -> implement)' "initiative alert: stale Target named"
assert_contains "$stale_payload" 'append the missing D<n>-proposed entry or ack' "initiative alert: remedy reaches the payload"
assert_working_tail "$stale_payload" "initiative alert: stale Target"

rm -rf "$MEM/initiatives"
startup_context initiative-missing
missing_payload="$STARTUP_CONTEXT"
assert_not_contains "$missing_payload" 'initiative-alert' "initiative alert: missing initiatives is silent"
assert_working_tail "$missing_payload" "initiative alert: missing initiatives"

mkdir -p "$MEM/initiatives"
startup_context initiative-empty
empty_payload="$STARTUP_CONTEXT"
assert_not_contains "$empty_payload" 'initiative-alert' "initiative alert: empty initiatives is silent"
assert_working_tail "$empty_payload" "initiative alert: empty initiatives"

cat > "$MEM/initiatives/broken.md" <<'EOF'
---
kind: initiative
slug: wrong
status: active
created: 2026-08-15
---
## Targets
### proj/broken
EOF
startup_context initiative-malformed
malformed_payload="$STARTUP_CONTEXT"
assert_not_contains "$malformed_payload" 'initiative-alert' "initiative alert: malformed initiative is silent"
assert_working_tail "$malformed_payload" "initiative alert: malformed initiative"

reuse="$(grep -n 'initiative-status.sh' "$REPO/scripts/hooks/lib.sh" 2>/dev/null || true)"
assert_contains "$reuse" 'bash "$MEMORY_DIR/scripts/initiative-status.sh"' "initiative alert: checker reused by subprocess"
alert_source="$(sed -n '/^render_initiative_alert()/,/^}/p' "$REPO/scripts/hooks/lib.sh")"
assert_not_contains "$alert_source" 'snapshot_stage_for' "initiative alert: no copied snapshot logic"
assert_not_contains "$alert_source" 'stream_entry_count' "initiative alert: no copied stream-count logic"

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
# event choice pure manifest config: the engine names the wired event in
# AI_MEMORY_HOOK_EVENT, and the script arms on any *Compact* event, rejecting only
# an explicit non-compact source.
STATE_NS="$MEM/state-nosource"
out_ns="$(printf '{"trigger":"auto","cwd":"%s","session_id":"cx-precompact"}' "$WORK" \
    | MEMORY_STATE_DIR="$STATE_NS" AI_MEMORY_HOOK_EVENT=PreCompact bash "$ARM")"
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
