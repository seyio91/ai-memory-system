#!/usr/bin/env bash
# Reads ~/.codex-spike/events.log and prints the SC1 finding: which events fired,
# their session_id / source, and whether any compaction-candidate event's
# session_id matches the UserPromptSubmit session_id (the make-or-break for the task).
set -u
LOG="${SPIKE_LOG_DIR:-$HOME/.codex-spike}/events.log"
[ -f "$LOG" ] || { echo "no log at $LOG — run the session first"; exit 1; }
LOG="$LOG" python3 - <<'PY'
import json, os
recs = [json.loads(l) for l in open(os.environ["LOG"]) if l.strip()]
print(f"== {len(recs)} events captured ==\n")
print(f"{'tag':<16} {'source':<10} {'session_id':<40} keys")
print("-"*100)
for r in recs:
    print(f"{str(r.get('tag')):<16} {str(r.get('source')):<10} {str(r.get('session_id')):<40} {r.get('keys')}")

ups = {r.get("session_id") for r in recs if r.get("tag")=="UserPromptSubmit" and r.get("session_id")}
CAND = ("SessionStart","PreCompact","PostCompact")
comp = [r for r in recs if r.get("tag") in CAND]
# a SessionStart is only a compaction signal if source=compact
comp = [r for r in comp if not (r.get("tag")=="SessionStart" and r.get("source")!="compact")]

print("\n== VERDICT (SC1) ==")
print(f"UserPromptSubmit session_id(s): {ups or '(NONE captured — session did not log UPS)'}")
if not comp:
    print("NO compaction-candidate event fired (no PreCompact/PostCompact, no SessionStart source=compact).")
    print("=> Codex emitted no usable compaction hook. Result: NOT FEASIBLE — document + spike-gated close (SC5).")
else:
    for r in comp:
        sid=r.get("session_id"); tag=r.get("tag"); src=r.get("source")
        if sid and sid in ups:
            verdict="MATCH ✅  -> GO: build P2/P3, set compaction_arm = %s in the codex manifest"%tag
        elif sid:
            verdict="MISMATCH ❌ (id present but != UPS) -> sentinel would land at wrong path; fallback needed or close"
        else:
            verdict="NO session_id in payload ❌ -> cannot key the sentinel; fallback needed or close"
        print(f"[{tag} source={src}] session_id={sid}  => {verdict}")
PY
