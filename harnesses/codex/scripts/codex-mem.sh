#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Shared engine lives in the repo-level scripts/ dir (this harness script is at
# harnesses/codex/scripts/, so scripts/ is three levels up).
MEM_SCRIPTS="$(cd "$SCRIPT_DIR/../../../scripts" && pwd)"

CODEX_INSTRUCTIONS="${CODEX_INSTRUCTIONS_FILE:-$HOME/.codex/AGENTS.md}"
CODEX_OVERLAY="${CODEX_OVERLAY_FILE:-$HOME/.codex/AGENTS.local.md}"

if ! command -v codex >/dev/null 2>&1; then
    echo "codex-mem: codex not found in PATH" >&2
    exit 1
fi

# Executor shorthand: `codex-mem.sh --executor "<prompt>"` expands to the orchestrator-workflow
# default invocation — workspace-write sandbox, network on (for gh), no approval prompts.
# Deny rules in ~/.codex/rules/default.rules still block apply/merge/etc.
#
# `--executor-bare` is the same, minus the memory stack: it SKIPS the AGENTS.md
# merge below and sets `project_doc_max_bytes=0` so codex doesn't read AGENTS.md at
# all (~13k tokens stripped). Use it for read-only review/analysis subagents that
# don't need identity/project memory — keeps the orchestrator's fan-out lean. The
# deny-rules guardrails still apply (they load from ~/.codex/rules/, not AGENTS.md).
EXECUTOR_FLAGS=()
EXECUTOR_MODE=false
EXECUTOR_BARE=false
case "${1:-}" in
    --executor|--executor-bare)
        [ "$1" = "--executor-bare" ] && EXECUTOR_BARE=true
        shift
        EXECUTOR_MODE=true
        EXECUTOR_FLAGS=(
            exec
            --sandbox workspace-write
            --skip-git-repo-check
            -c sandbox_workspace_write.network_access=true
        )
        if [ "$EXECUTOR_BARE" = true ]; then
            EXECUTOR_FLAGS+=(-c project_doc_max_bytes=0)
        fi
        ;;
esac

# Bare executor skips the memory merge entirely (codex won't read AGENTS.md anyway).
# Otherwise rebuild AGENTS.md from the memory tree via the shared context builder.
if [ "$EXECUTOR_BARE" != true ]; then
    bash "$MEM_SCRIPTS/build-context-md.sh" "$CODEX_INSTRUCTIONS" "codex-mem" "$CODEX_OVERLAY"
fi

# In executor mode, redirect stdin from /dev/null so codex doesn't block waiting
# for stdin EOF when invoked from a harness that holds stdin open (e.g. via a
# unix socket peer). Interactive `codex-mem.sh` calls keep stdin inherited.
if [ "$EXECUTOR_MODE" = "true" ]; then
    exec codex ${EXECUTOR_FLAGS[@]+"${EXECUTOR_FLAGS[@]}"} "$@" </dev/null
else
    exec codex ${EXECUTOR_FLAGS[@]+"${EXECUTOR_FLAGS[@]}"} "$@"
fi
