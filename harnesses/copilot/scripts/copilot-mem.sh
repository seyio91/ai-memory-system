#!/usr/bin/env bash
# copilot-mem.sh — executor/headless wrapper only. Interactive Copilot sessions
# receive memory through hooks directly and do not need this wrapper.
set -euo pipefail

if ! command -v copilot >/dev/null 2>&1; then
    echo "copilot-mem: copilot not found in PATH" >&2
    exit 1
fi

if [ -z "${COPILOT_GITHUB_TOKEN:-}" ] && [ -z "${GH_TOKEN:-}" ] && [ -z "${GITHUB_TOKEN:-}" ] \
    && command -v gh >/dev/null 2>&1; then
    if token="$(gh auth token)"; then
        if [ -n "$token" ]; then
            export GH_TOKEN="$token"
        fi
    fi
fi

exec copilot "$@" </dev/null
