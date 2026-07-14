---
plan: hook-standardization
status: active
created: 2026-07-14
owner: claude (orchestrator)
task_provider: notion
task_ref: 39bf6850-c619-817d-88a5-e32f529496fe
---

# Standardize the hook layer across harnesses (+ move Codex onto native hooks)

## Goal
Make hook wiring a declarative, manifest-driven capability: canonical hook roles → a per-harness `[hooks]` role→event map → a generalized `drivers/hook.sh` that registers shared hook scripts into each harness's native hooks file. Move Codex off the file-archetype `AGENTS.md`-only model onto native hooks (hybrid: `AGENTS.md` static base + hooks for dynamic memory/guard/compaction), so it gains live per-turn injection, mid-session project switch, and a real infra gate.

## Success criteria
1. Every harness manifest carries a `[hooks]` role→event map; `drivers/hook.sh` contains **no hardcoded event names** (`PreInvocation`/`PreToolUse`/`UserPromptSubmit`/`SessionStart` are all read from the map). *(P1 — done, PR #57.)*
2. **(Descoped 2026-07-14.)** The **behavioral** layer is shared; the **registration** layer may keep a small per-harness branch. Onboarding a harness reuses the shared content + hook scripts (criterion 3); wiring them into that harness's native hooks-file shape (`settings.json` merge / `hooks.json` write / `requirements.toml`) **may be a small per-harness driver branch** — that is accepted, not a failure. The dropped goal was "manifest-only, zero per-harness driver code" (see the descope decision).
3. A single `scripts/hooks/inject.sh` + `guard.sh` code path is shared by the **isomorphic Claude + Codex pair** (identical stdin/`additionalContext` contract; format chosen at the `content-core.sh` + `formatters/*` boundary only). **Antigravity is NOT forced through this contract** — it keeps its own thin registration + `PreInvocation`/XML/no-`session_id` injection path rather than a canonical adapter (see Fork 1 / the descope decision).
4. Interactive Codex injects live per-turn active-project memory + `working.md` via `UserPromptSubmit` (empirically verified with a marker probe, per the investigation) and supports mid-session project switch. Below the probed version floor, Codex falls back to the file-archetype `AGENTS.md` with **no error**.
5. Codex `infra_guard` denies the shared deny-list under `AI_MEMORY_ROLE` (executor role), matching Antigravity's gate; interactive Codex stays unguarded.
6. Claude `settings.json` hook registration is **driver-written and fail-closed** (backs up before write, refuses on an unparseable / non-object file, touches only ai-memory hook keys) and idempotent on re-run.
7. `requirements.toml` registers the Codex memory hooks as managed/trusted, so interactive `codex` runs them with **no manual `/hooks` step**.
8. Claude + Antigravity injection/guard behavior is **unchanged** (regression: identical `additionalContext` payloads and deny behavior). Full test suite green, including a new stage covering the role→event mapping.
9. Guard task `396f6850-c619-81b2-…` is folded in as the `infra_guard` role and closed; `on-demand-project-load` decision #4 is updated (Codex no longer excluded); `docs/harnesses/codex.md`'s "no native memory hook" line is corrected.

## Design
Seed: `projects/ai-memory/investigations/hook-standardization.md` (review of current hook usage, the Codex-features→hooks analysis, and the standardization design in its §C). Design settled through the brainstorm gate; the five open forks are resolved below.

**Canonical roles** (harness-neutral names the memory system reasons about): `session_bootstrap`, `per_turn_inject`, `infra_guard`, `task_tool_block`, `compaction_recovery`. A harness **omits roles it cannot serve** (Antigravity has no `session_id`, so no `compaction_recovery`). `checkpoint_on_stop` is **cut** (YAGNI — no consumer yet).

**Canonical contract = the Claude/Codex one** (they are isomorphic — see the investigation's contract table): stdin JSON (`session_id`, `cwd`, `prompt`, `hook_event_name`, `source`, `tool_name`…); stdout `hookSpecificOutput.additionalContext` to inject; exit 2 / `decision:block` to gate. Shared scripts speak this contract; Antigravity gets a thin I/O adapter.

**Six units:**
1. **Manifest `[hooks]` role→event map** (data, never sourced) — each manifest declares `role = event[:matcher]`, e.g. `per_turn_inject = UserPromptSubmit`, `infra_guard = PreToolUse:^Bash$|apply_patch`, `task_tool_block = PreToolUse:TaskCreate|TaskUpdate`. Onboarding a harness's hooks = fill this map + declare the hooks-file shape.
2. **Generalized `drivers/hook.sh`** — reads the role→event map, resolves each role to its shared script, and writes it into the harness's native hooks file in that harness's JSON/TOML shape. Replaces today's two hardcoded registration styles and the hardcoded `PreInvocation`/`PreToolUse` event names.
3. **Shared hook scripts `scripts/hooks/`** — `inject.sh`, `guard.sh`, `block-task.sh` consume the canonical stdin and emit canonical stdout. Format (xml/md) is chosen per-harness via the existing `content-core.sh` + `formatters/{xml,md}.sh` split — the branch lives at the formatter boundary only, not sprinkled through the script.
4. **Antigravity — keep its own path** (descoped 2026-07-14). Antigravity is the one divergent harness (`PreInvocation`, no `session_id`, XML). Rather than an adapter forcing it through the canonical Claude/Codex contract, it **retains its existing thin registration + injection path**, sharing only the content layer (`content-core.sh` + `xml.sh`), which it already does. No canonical-contract adapter is built.
5. **Codex hybrid** — `AGENTS.md` stays the static identity+rules base (resilient if a hook fails to register); new hooks handle `per_turn_inject` (UserPromptSubmit), `infra_guard` (PreToolUse `^Bash$`/`apply_patch`), and `compaction_recovery` (PreCompact/PostCompact). `requirements.toml` registers them managed/trusted. A version-floor gate (extended `exec_probe`) falls back to the file archetype below the floor.
6. **Claude auto-merge** — the driver merges hook entries into `~/.claude/settings.json` using the existing fail-closed `_hook_register_json` logic (backup, refuse-on-unparseable), removing the last manual install step.

**Forks resolved (decision record):**
- *Fork 1 — script-sharing depth* → **shared set for the isomorphic pair, staged; Antigravity keeps its own path** (narrowed 2026-07-14). One harness-neutral behavioral script set (`inject.sh`/`guard.sh`) for **Claude & Codex only** — they are contract-isomorphic, so dedup is nearly free and kills drift in the logic that actually carries bugs. Staged so Codex adopts the shared scripts first (greenfield, zero risk) and Claude migrates last (its path is in daily use). **Antigravity is out of the shared behavioral set** — it shares only the content layer it already shares; no canonical adapter. *Rejected:* big-bang (touches the daily-use Claude path at the same time as new Codex wiring); wiring-only (leaves the duplicated injector/guard logic the initiative set out to remove); **canonical-adapter-for-all** (builds an abstraction whose sole exception is a third of a small, fixed harness set — the descope below).
- *Fork 2 — Codex target* → **hybrid** (`AGENTS.md` base + hooks for dynamic). *Rejected:* full-hook (drop `AGENTS.md`) — loses the always-present base if a hook fails to register.
- *Fork 3 — Claude registration* → **auto-merge with fail-closed backup**. *Rejected:* keep-manual — leaves an asymmetric install (Antigravity auto, Claude manual) for no safety gain the backup doesn't already provide.
- *Fork 4 — Codex trust* → **`requirements.toml` managed hooks** (trusted automatically on install). *Rejected/deferred:* the one-time `/hooks` step — kept only as an undocumented fallback (see Risks).
- *Fork 5 — version floor* → **gate on a probed `codex` version via extended `exec_probe`**; below floor, fall back to file archetype with no error.

**This subsumes** backlog task `396f6850-c619-81b2-…` ("Manifest guard capability — unify executor infra-deny across harnesses") — it is exactly the `infra_guard` role here.

## Decisions (locked)
- Canonical roles: `session_bootstrap`, `per_turn_inject`, `infra_guard`, `task_tool_block`, `compaction_recovery`; a harness omits what it can't serve. `checkpoint_on_stop` cut.
- **Descope (2026-07-14) — share the isomorphic pair, don't build a canonical abstraction over all harnesses.** The value here is lopsided: ~80% is (a) the already-shared content layer (`content-core.sh` + `formatters/*`) and (b) Codex *gaining* real hook capabilities (live per-turn inject, mid-session project switch, real infra gate) — both justify themselves independently. The remaining ~20% — a fully-general driver with **zero** hardcoded event names for *all* harnesses plus an **Antigravity canonical-contract adapter** — is ceremony for a **fixed, author-controlled set of ≤5 harnesses**. The tell: the investigation's own contract table shows Antigravity diverging (no `session_id`, `PreInvocation`, XML), so the "one contract all harnesses speak" abstraction has a hardcoded exception for 1 of 3. For a bounded N, a small per-harness registration branch is more readable/debuggable than a data-driven resolver + adapter, and "onboarding the Nth harness is manifest-only" optimizes a cost we rarely pay. **So:** share the *behavioral* scripts across the **isomorphic Claude+Codex pair only**; **Antigravity keeps its own thin path** (content layer shared, no adapter); per-harness *registration* branches are accepted, not a failure. P1 (data-driven driver, no hardcoded event names) already shipped and is behavior-preserving — **not unwound** (removing it now is negative value); the descope narrows P2/P3 scope going forward, it does not revert P1.
- Canonical contract = the Claude/Codex isomorphic one, used **for that pair's shared scripts**. **No Antigravity adapter is built** (superseding the earlier "Antigravity is the sole adapter" line).
- Shared behavioral scripts live in `scripts/hooks/` (`inject.sh`/`guard.sh`, Claude+Codex); format chosen at the formatter boundary.
- Claude migrates **last**; Codex adopts shared scripts greenfield **first**.
- Codex = hybrid (`AGENTS.md` base + hooks); trust via `requirements.toml`; version-floor fallback to file archetype.
- Claude `settings.json` = driver auto-merge, fail-closed.

## Phases
- **P1 — roles + data-driven driver.** Define canonical roles; add the `[hooks]` role→event map to each manifest; rewrite `drivers/hook.sh` to read the map (no hardcoded event names). **Behavior-preserving** for Claude + Antigravity — identical registration output, now from the map. New test stage asserts the mapping and the driver's output for existing harnesses.
- **P2 — shared scripts (Claude+Codex) + Codex onto hooks.** Extract `scripts/hooks/{inject,guard}.sh` (format-param) as the shared behavioral set for the **isomorphic Claude+Codex pair**. Codex adopts them greenfield: register `per_turn_inject` + `infra_guard` into Codex's hooks file, write `requirements.toml` managed trust, add the version-floor gate to `exec_probe`. Codex becomes hybrid. Re-run the marker-probe to confirm live injection. **Descoped:** no canonical adapter; `block-task.sh` is Claude-only (Codex has no TaskCreate/TaskUpdate to gate) so it is not part of the shared extract.
- **P3 — migrate Claude onto the shared scripts.** Point Claude at the shared `scripts/hooks/{inject,guard}.sh`; add fail-closed `settings.json` auto-merge to the driver. **Antigravity is left as-is** (descoped) — it already shares the content layer and keeps its own thin registration/injection path; no adapter work. Regression: Claude + Antigravity payloads/deny behavior unchanged (Antigravity unchanged by construction).
- **P4 — compaction + docs/consumers.** Standardize `compaction_recovery` (Codex native `PreCompact`/`PostCompact`). Close guard task `396f6850`; update `on-demand-project-load` decision #4 (drop Codex exclusion); fix `docs/harnesses/codex.md` "no native memory hook". Update Architecture Decisions in `memory.md`.

## Risks / open questions
- **Claude `settings.json` auto-merge rewrites a user-owned file.** Mitigated by the fail-closed backup, but a hooks-array shape the merge doesn't understand could mis-merge — validate against a real `settings.json` fixture with existing hooks before shipping P3.
- **`requirements.toml` managed-trust may vary by codex version / not be honored everywhere.** The one-time `/hooks` step is the fallback but we chose not to document it (Fork 4) — revisit and document if managed trust proves flaky in the field.
- **The md formatter was built for `AGENTS.md` baking, not per-turn injection.** Injection works (probe-confirmed), but verify the md payload reads well injected mid-turn and that breadcrumb-vs-full-payload semantics behave on Codex.
- **`compaction_recovery` is N/A on Antigravity** (no `session_id`) — the role→event map must allow a role to be absent per harness (already implied by "omit roles it can't serve"; assert it in the P1 mapping test).
