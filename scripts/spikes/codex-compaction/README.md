# P1 Spike — does Codex fire a usable compaction hook?

Tooling for the gating spike of the **codex-arm-recompact-sentinel** plan
(`projects/ai-memory/plans/`). Observe-only; installs nothing permanent.

**Goal (SC1):** determine whether Codex emits a hook event on compaction, its name,
its payload shape, and whether its `session_id` == the `UserPromptSubmit` session_id.
The `.recompact` sentinel is keyed on session_id — a mismatch makes the whole task
infeasible, which is why this is a gate, not a quick edit.

## Files
- `spike-capture.sh` — observe-only hook. Logs raw stdin + a per-event tag to
  `~/.codex-spike/events.log`, one JSON record per line. Never writes stdout, so it
  cannot inject or block the Codex session. Registered once per candidate event with a
  distinct `$1` tag.
- `spike-install.sh` — writes `~/.codex/hooks.json` (backs up any existing), registering
  the capture hook on `SessionStart` / `UserPromptSubmit` / `PreCompact` / `PostCompact`.
  Self-locating: points at the `spike-capture.sh` beside it.
- `spike-analyze.sh` — reads the log and prints the SC1 verdict (MATCH / MISMATCH / no-event).
- `spike-teardown.sh` — restores or removes `~/.codex/hooks.json`.

## Procedure
1. `bash scripts/spikes/codex-compaction/spike-install.sh`
2. Run interactive Codex in a throwaway git dir:
   `cd /tmp && mkdir -p codex-spike-run && cd codex-spike-run && git init -q . && codex`
   - **Accept the hook-trust prompt** if shown, else hooks silently never fire (the #1
     cause of an empty log).
3. Send 2-3 normal prompts (baseline `UserPromptSubmit` session_id).
4. Force a compaction: type `/compact`; if unavailable, fill context until Codex
   auto-compacts.
5. Send one more prompt after compaction (confirms session_id is stable across the boundary).
6. `bash scripts/spikes/codex-compaction/spike-analyze.sh` → copy the `== VERDICT (SC1) ==`
   block into the plan.
7. `bash scripts/spikes/codex-compaction/spike-teardown.sh`

## Reading the result
- **MATCH** on `PreCompact` / `PostCompact` / `SessionStart source=compact` → GO. That event
  name becomes `compaction_arm = <EVENT>` in the codex manifest `[hooks]`. Proceed to P2/P3.
- **No candidate fired**, or **session_id absent/mismatched** → spike-gated close (SC5):
  document, confirm the breadcrumb fallback still works, close the task. No engine changes.

## Gotchas
- If `codex` rejects `hooks.json` complaining about an unknown event key, drop
  `PreCompact`/`PostCompact` and re-run with just `SessionStart`+`UserPromptSubmit` — a rejected
  file means Codex doesn't know that event name, which is itself a finding.
- Global `~/.codex/hooks.json` is the manifest target; if events don't fire there, try a
  project-level `.codex/hooks.json` in the run dir as a fallback probe.
