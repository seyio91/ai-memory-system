#!/usr/bin/env bash
set -euo pipefail
HJ="$HOME/.codex/hooks.json"
BAK="$(ls -t "$HJ".spike-bak.* 2>/dev/null | head -1 || true)"
if [ -n "$BAK" ]; then mv "$BAK" "$HJ"; echo "restored $HJ from $BAK"; else rm -f "$HJ"; echo "removed spike $HJ (no prior file)"; fi
echo "log retained at $HOME/.codex-spike/events.log (delete manually when done)"
