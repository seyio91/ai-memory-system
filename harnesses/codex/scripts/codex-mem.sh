#!/usr/bin/env bash
set -euo pipefail

if ! command -v codex >/dev/null 2>&1; then
    echo "codex-mem: codex not found in PATH" >&2
    exit 1
fi

# Executor shorthand: `codex-mem.sh --executor "<prompt>"` expands to the orchestrator-workflow
# default invocation — workspace-write sandbox, network on (for gh), no approval prompts.
# Deny rules in ~/.codex/rules/default.rules still block apply/merge/etc. The memory base is
# NOT built into AGENTS.md any more; it injects live via the SessionStart hook, so a plain
# --executor run sees fresh identity/project memory through that channel.
#
# `--executor-bare` is the same, minus the memory stack: it exports
# `AI_MEMORY_SKIP_INJECT=1` (the SessionStart + UserPromptSubmit hooks honor it and emit
# nothing — no base, no breadcrumb) and sets `project_doc_max_bytes=0` so codex doesn't read
# the hand-owned AGENTS.md / repo docs either. Use it for read-only review/analysis subagents
# that don't need identity/project memory — keeps the orchestrator's fan-out lean. The
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
            --dangerously-bypass-hook-trust
            --sandbox workspace-write
            --skip-git-repo-check
            -c sandbox_workspace_write.network_access=true
        )
        if [ "$EXECUTOR_BARE" = true ]; then
            EXECUTOR_FLAGS+=(-c project_doc_max_bytes=0)
            # Suppress ALL memory injection through the native hooks (base + breadcrumb).
            # Exported so codex passes it down to the hook subprocess it spawns.
            export AI_MEMORY_SKIP_INJECT=1
        fi
        ;;
esac

# In executor mode, redirect stdin from /dev/null so codex doesn't block waiting
# for stdin EOF when invoked from a harness that holds stdin open (e.g. via a
# unix socket peer). Interactive `codex-mem.sh` calls keep stdin inherited.
if [ "$EXECUTOR_MODE" = "true" ]; then
    exec codex ${EXECUTOR_FLAGS[@]+"${EXECUTOR_FLAGS[@]}"} "$@" </dev/null
else
    exec codex ${EXECUTOR_FLAGS[@]+"${EXECUTOR_FLAGS[@]}"} "$@"
fi
