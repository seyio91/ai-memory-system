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
#
# Both executor modes are credential-free by default; AI_MEMORY_EXECUTOR_GH_TOKEN=1 opts
# into a keychain-fetched GH_TOKEN for the run (see the block below).
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
        # codex re-applies .git as read-only under workspace-write, so an executor can
        # edit files but never commit ("Unable to create .git/index.lock: Operation not
        # permitted"). Widen the sandbox to this repo's git dir(s); non-repo cwd = no-op.
        GIT_ROOTS=()
        for d in "$(git rev-parse --absolute-git-dir 2>/dev/null || true)" \
                 "$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"; do
            [ -n "$d" ] || continue
            case " ${GIT_ROOTS[*]-} " in *" $d "*) continue ;; esac
            GIT_ROOTS+=("$d")
        done
        if [ "${#GIT_ROOTS[@]}" -gt 0 ]; then
            roots_json=""
            for d in "${GIT_ROOTS[@]}"; do roots_json="$roots_json${roots_json:+,}\"$d\""; done
            EXECUTOR_FLAGS+=(-c "sandbox_workspace_write.writable_roots=[$roots_json]")
        fi
        # Opt-in (AI_MEMORY_EXECUTOR_GH_TOKEN=1, typically from config.local.sh): the
        # sandbox cannot reach the macOS keychain, so gh 401s and HTTPS pushes find no
        # credential. Fetch from the keyring at launch — the token lives only in this
        # run's env, never at rest, and follows rotation. Loud if it can't be fetched.
        if [ "${AI_MEMORY_EXECUTOR_GH_TOKEN:-0}" = "1" ]; then
            gh_token="$(gh auth token 2>/dev/null || true)"
            if [ -z "$gh_token" ]; then
                echo "codex-mem: AI_MEMORY_EXECUTOR_GH_TOKEN=1 but 'gh auth token' returned nothing — run 'gh auth login'" >&2
            else
                export GH_TOKEN="$gh_token"
                # gh is the credential helper too, else an HTTPS remote still has no
                # password. Skipped if the caller already set a git env-config chain.
                if [ -z "${GIT_CONFIG_COUNT:-}" ]; then
                    export GIT_CONFIG_COUNT=1
                    export GIT_CONFIG_KEY_0=credential.helper
                    export GIT_CONFIG_VALUE_0='!gh auth git-credential'
                else
                    echo "codex-mem: GIT_CONFIG_COUNT already set — leaving credential.helper alone (HTTPS pushes may fail)" >&2
                fi
            fi
            unset gh_token
        fi
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
