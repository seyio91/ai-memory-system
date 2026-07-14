#!/usr/bin/env bash
# Spike capture hook — OBSERVE ONLY. Logs raw stdin + a per-event tag, one JSON
# record per line. Never blocks, never writes to stdout (so it injects nothing
# and cannot break the Codex session). Registered once per candidate event with a
# distinct $1 tag so we can tell which event fired.
set -u
TAG="${1:-unknown}"
LOG_DIR="${SPIKE_LOG_DIR:-$HOME/.codex-spike}"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/events.log"
RAW="$(cat)"
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if command -v python3 >/dev/null 2>&1; then
  TAG="$TAG" TS="$TS" LOG="$LOG" RAW="$RAW" python3 - <<'PY'
import json, os
raw = os.environ["RAW"]
try:
    p = json.loads(raw)
except Exception:
    p = {"_unparsed_raw": raw}
d = p if isinstance(p, dict) else {"_nonobject": p}
rec = {
    "tag": os.environ["TAG"],
    "ts": os.environ["TS"],
    "session_id": d.get("session_id"),
    "source": d.get("source"),
    "hook_event_name": d.get("hook_event_name"),
    "keys": sorted(d.keys()),
    "raw": p,
}
with open(os.environ["LOG"], "a") as f:
    f.write(json.dumps(rec) + "\n")
PY
else
  printf '%s\t%s\t%s\n' "$TAG" "$TS" "$(printf '%s' "$RAW" | tr '\n' ' ')" >> "$LOG"
fi
exit 0
