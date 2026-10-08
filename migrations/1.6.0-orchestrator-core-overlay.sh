#!/usr/bin/env bash
# 1.6.0 — Orchestrator core/overlay split.
#
# Workflow doctrine used to live in one per-instance orchestrator.md, seeded once
# from a now-deleted seed file and never updated again -- every instance
# drifted from that one-time copy at its own pace. This release replaces it
# with a tracked core (doctrine/orchestrator.md, updated on every sync) plus a
# gitignored local overlay (orchestrator.local.md, additive, personal rules
# only). Precedence: identity.md > orchestrator.local.md > doctrine/orchestrator.md
# > project memory.
#
# Back up any existing root orchestrator.md -- by rename, never by copy, so the
# superseded file stops satisfying content-core.sh's legacy fallback once this
# has run -- without ever clobbering a prior backup. Then seed an empty
# orchestrator.local.md if one does not already exist. The overlay is seeded
# EMPTY (zero bytes) on purpose: content-core.sh treats a whitespace-only
# overlay as blank and falls through to the legacy root file, so any non-blank
# seed text (even a header comment) would itself count as a real overlay and
# get injected. The explanation that would have gone in that header lives in
# the printed notice and in UPGRADING.md instead.
#
# Idempotent, forward-only: a second run finds no root file left to back up
# and an overlay that already exists, so it is a silent no-op.
set -euo pipefail

: "${MEMORY_DIR:?MEMORY_DIR is required}"
: "${REPO_ROOT:?REPO_ROOT is required}"

ROOT_ORCH="$MEMORY_DIR/orchestrator.md"
BACKUP="$MEMORY_DIR/orchestrator.md.pre-1.6.0"
OVERLAY="$MEMORY_DIR/orchestrator.local.md"

if [ -f "$ROOT_ORCH" ]; then
    if [ -e "$BACKUP" ]; then
        printf '1.6.0: %s already exists -- leaving it and %s untouched.\n' "$BACKUP" "$ROOT_ORCH"
    else
        mv "$ROOT_ORCH" "$BACKUP"
        printf '1.6.0: moved %s -> %s.\n' "$ROOT_ORCH" "$BACKUP"
        printf '1.6.0: port any personal rules from %s into %s by hand -- the engine doctrine now lives in %s/doctrine/orchestrator.md and updates on every sync.\n' "$BACKUP" "$OVERLAY" "$MEMORY_DIR"
    fi
fi

if [ ! -e "$OVERLAY" ]; then
    : > "$OVERLAY"
fi
