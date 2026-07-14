#!/usr/bin/env bash
# Install the observe-only spike hooks into ~/.codex/hooks.json (backs up any
# existing), pointing at the capture hook sitting beside this script. Clears the
# prior log. See README.md for the full procedure.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CAP="$SCRIPT_DIR/spike-capture.sh"
HJ="$HOME/.codex/hooks.json"
mkdir -p "$HOME/.codex"
if [ -e "$HJ" ]; then cp "$HJ" "$HJ.spike-bak.$(date +%s)"; echo "backed up existing -> $HJ.spike-bak.*"; fi
cat > "$HJ" <<JSON
{
  "hooks": {
    "SessionStart":     [ { "hooks": [ { "type": "command", "command": "bash $CAP SessionStart" } ] } ],
    "UserPromptSubmit": [ { "hooks": [ { "type": "command", "command": "bash $CAP UserPromptSubmit" } ] } ],
    "PreCompact":       [ { "hooks": [ { "type": "command", "command": "bash $CAP PreCompact" } ] } ],
    "PostCompact":      [ { "hooks": [ { "type": "command", "command": "bash $CAP PostCompact" } ] } ]
  }
}
JSON
rm -f "$HOME/.codex-spike/events.log"
echo "installed spike hooks -> $HJ"
echo "capture hook          -> $CAP"
echo "log will be           -> $HOME/.codex-spike/events.log"
