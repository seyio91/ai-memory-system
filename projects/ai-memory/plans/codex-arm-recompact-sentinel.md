---
plan: codex-arm-recompact-sentinel
status: active
created: 2026-07-14
owner: claude (orchestrator)
task_provider: local
task_ref: 39df6850-c619-81d9-a020-f7bd74344efe
---

## Goal

Give Codex the deterministic post-compaction memory recovery Claude already has: a
standalone Codex hook that arms the shared `.recompact` sentinel at compaction, so the
next `UserPromptSubmit` force-reinjects the full memory payload (not just the breadcrumb
pointer). Gated on a spike confirming Codex fires a compaction event whose `session_id`
matches `UserPromptSubmit`'s.

## Success criteria

- **SC1 (spike — GATE):** A real Codex compaction is forced and recorded in this plan:
  whether a hook event fires, its event name, its stdin/payload shape, and its `session_id`
  compared to the `session_id` `UserPromptSubmit`/`inject.sh` sees. Go/no-go decision recorded.
- **SC2 (conditional on SC1 match):** `harnesses/codex/hooks/arm_recompact.sh`, fed the
  compaction event on stdin, writes `$STATE_DIR/<session_id>.recompact`; a unit test asserts
  the sentinel file appears (mirrors the Claude `source=compact` assertion in
  `scripts/tests/test_shared_hooks.sh`).
- **SC3 (conditional):** Codex manifest `[hooks]` gains `compaction_arm = <EVENT>` + an
  `arm_script` key, and `drivers/hook.sh` registers it; `install.sh` on a Codex instance
  writes the arm entry into the Codex hooks JSON **idempotently** — a re-sync neither
  duplicates nor orphans it.
- **SC4 (conditional):** End-to-end — after a real Codex compaction, the next prompt receives
  the full `<memory:identity>...` payload, not only the breadcrumb.
- **SC5 (SC1 no-match branch):** The negative finding is documented here (Design/Risks), the
  task closes as "not feasible on Codex today", and the breadcrumb fallback is confirmed still
  functioning — no regression.

## Design

**Chosen approach:** a dedicated Codex-side arm hook wired through the existing native-JSON
registrar, gated behind a spike. Claude's working path is untouched.

**Data flow (consumer unchanged, already shared):** compaction event -> `arm_recompact.sh`
writes `$STATE_DIR/<session_id>.recompact` -> next `UserPromptSubmit` -> `inject.sh` sees the
sentinel, deletes it, force-injects the full payload. Codex already has the `per_turn_inject`
consumer wired; this adds only the *arming* half it lacks.

**Units:**
1. **`harnesses/codex/hooks/arm_recompact.sh`** (new, ~6 lines of logic) — sources
   `scripts/hooks/lib.sh`; reads `session_id` from stdin JSON; `mkdir -p "$STATE_DIR"`;
   `: > "$(recompact_sentinel "$id")"`; prunes stale `*.recompact` (`-mtime +2`). Standalone
   mirror of Claude's `source=compact` branch. Exact stdin field parsing finalized by the spike.
2. **Codex manifest `[hooks]`** — add `compaction_arm = <EVENT>` (the `<EVENT>` string is pure
   config, set from the spike) + an `arm_script = $MEMORY_DIR/harnesses/codex/hooks/arm_recompact.sh`
   key.
3. **`drivers/hook.sh` -> `_hook_register_native_json`** — add a 5th role case
   (`compaction_arm -> arm_script`), a command-build branch, extend the hardcoded
   `INJECT/GUARD/SESSION/BLOCK` env-prefix loop with `ARM`, and add `arm_recompact.sh` to the
   `ours` marker tuple so re-sync manages it idempotently. Consistent with the existing 4-role
   hardcoding — no generalization (YAGNI).

**Key property:** the driver is event-string-agnostic, so units 1 and 3 can be built *before*
the spike pins the event name — the spike only fills the manifest `<EVENT>` value and confirms
the `session_id` match.

**Rejected alternatives:**
- *Reuse Claude's `session_start_memory.sh`* — its normal-start path emits SessionStart context
  Codex does not want; gating it dirties a working hook.
- *Shared `arm_recompact_sentinel()` helper in `lib.sh`* — cleaner DRY but touches Claude's path;
  deferred (revisit if a 3rd harness needs it). ~6-line duplication accepted.
- *Fold arming into an existing Codex hook* — impossible; the sentinel must be written at
  compaction time, which requires a compaction-triggered event.

## Decisions (locked)

- **Spike-gated close**, not must-land-with-fallback. A no-match spike result documents the
  finding and closes; the breadcrumb fallback already covers the gap, so nothing regresses.
- **Standalone Codex arm script**; Claude's `session_start_memory.sh` stays untouched. ~6-line
  duplication accepted.
- **No driver generalization** — add a 5th hardcoded role, consistent with the existing 4.
- **Event string is manifest config**, set from the spike; the driver stays event-agnostic, so
  the arm script + driver wiring can land before the event name is pinned.
- **The arm SCRIPT is event-agnostic too (corrected post-P3, validator finding).** Its gate is
  `[ -z "$SOURCE" ] || [ "$SOURCE" = "compact" ] || exit 0` — it arms on SessionStart(source=compact)
  AND on PreCompact/PostCompact (which carry `trigger`, no `source`), rejecting only an explicit
  non-compact source (SessionStart source=startup). The original strict `source=compact` gate would
  have silently no-op'd if the manifest were flipped to Pre/PostCompact — so the fallback is a real
  manifest one-liner ONLY because of this relaxation. Primary event stays `SessionStart` (Claude parity).

## P1 spike findings (2026-07-14) — VERDICT: GO ✅

Real Codex compaction forced via live TTY (`/compact`), 8 events captured, all sharing one
`session_id` (`019f6165-712d-7d41-be62-3ba0c25f8be7`). Ordered capture:
`SessionStart(startup) → UserPromptSubmit ×3 → PreCompact → PostCompact → SessionStart(source=compact) → UserPromptSubmit`.

- **SC1 MATCH:** the post-compaction `session_id` is **identical** to `UserPromptSubmit`'s — the
  sentinel is keyed on session_id, so a file written at compaction survives into the resumed
  session. Three viable arm events (all matched): `PreCompact`, `PostCompact`,
  `SessionStart source=compact`.
- **Chosen event: `SessionStart` gated on `source=compact`.** Rationale: exact parity with Claude
  (`harnesses/claude/hooks/session_start_memory.sh:31` arms on the same `source=compact` gate),
  so P2 reuses the identical `recompact_sentinel`/`STATE_DIR` path and mirrors the SC2 assertion
  shape. Empirically fires *before* the next `UserPromptSubmit` (capture order above), so arming
  is never too late. `PreCompact`/`PostCompact` carry only `trigger` (no `source`) and would
  diverge from Claude's gate — kept as fallback if P4 shows auto-compaction skips
  `SessionStart(compact)` (spike exercised manual `/compact` only).
- **Manifest config:** `compaction_arm = SessionStart`; arm script gates on `source=compact`
  internally (SessionStart also fires with `source=startup`, which must NOT arm).
- **Residual risk (P4):** confirm auto-compaction (context-full) also emits `SessionStart(compact)`;
  only manual `/compact` was spiked.

## P4 E2E findings (2026-07-14 ~22:35) — SC4 CONFIRMED (manual /compact) ✅

Surgical live test (worktree arm script, `MEMORY_DIR=/Users/seyi/Downloads/personal/claude/memory` so
its `STATE_DIR` matches the live `inject.sh`). Behavioral proof: planted `P4-RECOMPACT-PROOF-7Z9Q` in the
full payload only (grep=1 full / grep=0 breadcrumb), ran `/compact`, sent one resume prompt → **Codex
echoed the token**. Since that token reaches a prompt ONLY via the arm→sentinel→`inject.sh` full re-inject,
this proves the whole chain end to end. Log corroboration: `thread/status/changed` → lone SessionStart
hook (22:33:10) → prompt-processing hooks → `.sessions/` mtime bumped (sentinel written+consumed same turn).

- **Timing finding:** in-place `/compact` does NOT fire `SessionStart(source=compact)` at compaction time —
  it fires on the **resume (next prompt)**, in the same turn as `UserPromptSubmit`. Matches the P1 order.
- **Ordering resolved:** the arm (SessionStart) ran BEFORE inject (UserPromptSubmit) on the resume turn —
  the marker reached the FIRST post-compaction prompt, so no dangling-sentinel / deferred-inject problem.
- **Trust:** the SessionStart arm hook fired without a separate `/hooks` prompt (project already trusted).
- **SC4 auto branch — CONFIRMED (2026-07-14 ~22:50):** forced a real AUTO compaction via
  `codex -c model_auto_compact_token_limit=40000` + context fill (log shows `auto_compact` +
  `op.dispatch.compact`, distinct from manual). Fresh marker `P4-AUTO-PROOF-3K8M` planted post-launch
  (absent from `AGENTS.md` build; full=1/breadcrumb=0) → Codex echoed it on the auto-resume prompt;
  `.sessions/` mtime bumped (sentinel write+consume). **Auto-compaction recovery works identically to
  manual.** No PreCompact/PostCompact pivot needed. SC4 fully closed.

## Phases

- [x] **P1 — Spike [GATE]:** forced a real Codex compaction; captured events, payload shapes, and
  `session_id`. **GO** — SC1 MATCH, arm event = `SessionStart source=compact`. (SC1) ✅
- [x] **P2 — Arm script:** `harnesses/codex/hooks/arm_recompact.sh` (gates on `source=compact`,
  writes `$STATE_DIR/<session_id>.recompact`) + `scripts/tests/test_codex_arm_recompact.sh` (4
  assertions: compact→sentinel + no stdout, startup no-op, no-project no-op). Full suite green
  (42 tests, shellcheck clean). Committed `37b8514`. (SC2) ✅
- [x] **P3 — Manifest + driver wiring:** codex `[hooks]` `compaction_arm = SessionStart` +
  `arm_script` key; `_hook_register_native_json` 5th role (`compaction_arm → arm_script`) + `ARM`
  prefix + `arm_recompact.sh` in the `ours` marker tuple; `validate-manifest` KNOWN_KEYS gains
  `arm_script`. **Folded in the adjacent orphan bug**: legacy `inject_memory.sh` added to `ours`
  so pre-P3 symlink-in-HOME entries are swept on re-sync (double-injection fix). `test_codex_hooks`
  asserts the SessionStart arm entry (once, correct cmd) + legacy sweep. Suite green 42/42;
  re-sync idempotent. Committed `3b4329d`. (SC3) ✅
- [~] **P4 — E2E verify + close:** SC4 CONFIRMED both branches (manual `/compact` + auto). Remaining:
  validator gate → mark done → PR → canonical install from main.
  - [x] Doc sub-item: `docs/harnesses/codex.md` compaction-recovery section updated (commit `bb8a4ee`).
  - [x] SC4 manual `/compact` E2E — marker echoed, arm→inject chain proven (commit `7fb1661`).
  - [x] SC4 auto-compaction E2E — marker echoed on auto-resume; `auto_compact` in log; recovery works.
  - [ ] Validator gate (SC1–SC5) → `/plan-done` → `/plan-archive`.
  - [ ] PR `worktree-codex-arm-recompact-sentinel` → main → canonical `install.sh --harness codex`
        (driver's `ours` marker auto-replaces the surgical worktree-path arm entry with the main-path one).

## Risks / open questions

- **Spike may find no usable event or a `session_id` mismatch** -> spike-gated close (accepted;
  breadcrumb path stays intact). This is the primary uncertainty.
- **Codex hook-trust:** newly registered hooks may require a trust prompt / bypass flag
  (`--dangerously-bypass-hook-trust` already used by `exec_readonly`) — onboarding friction to
  account for in P3/P4.
- **6-line duplication** with Claude's arm logic; revisit a `lib.sh` extraction if a 3rd harness
  ever needs it.
- **Adjacent, separately tracked (working.md):** `_hook_register_native_json`'s `ours` tuple omits
  the legacy `inject_memory.sh` name, orphaning pre-P3 entries on re-sync (hit live 2026-07-14).
  The `ours`-tuple touch in P3 is the natural place to also fix it, but it is out of this plan's
  scope unless folded in deliberately.
