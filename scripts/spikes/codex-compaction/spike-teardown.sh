#!/usr/bin/env bash
set -euo pipefail
HJ="$HOME/.codex/hooks.json"
BAK="$(find "$(dirname "$HJ")" -maxdepth 1 -name "$(basename "$HJ").spike-bak.*" 2>/dev/null | sort | tail -1)"
if [ -n "$BAK" ]; then mv "$BAK" "$HJ"; echo "restored $HJ from $BAK"; else rm -f "$HJ"; echo "removed spike $HJ (no prior file)"; fi
echo "log retained at $HOME/.codex-spike/events.log (delete manually when done)"
