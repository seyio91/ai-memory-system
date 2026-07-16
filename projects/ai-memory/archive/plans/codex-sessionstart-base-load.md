---
plan: codex-sessionstart-base-load
status: done
created: 2026-07-16
completed: 2026-07-16
owner: claude (orchestrator)
task_provider: notion
task_ref: 39ef6850-c619-8122-beb8-ce224fa2d8f1
---

# Plan — Move the Codex base-load from AGENTS.md to a SessionStart hook

## Goal
Codex is the only registered harness that still materializes its full memory base as a
file (`~/.codex/AGENTS.md`, rebuilt at launch by `codex-mem.sh` → `build-context-md.sh`).
Claude and Antigravity inject the base live via a hook. This forces every interactive
Codex session through the `codex-mem.sh` alias (a plain `codex` boots with a stale-or-absent
base) and keeps a bespoke file-build path alive. A live probe (2026-07-16) confirmed Codex
`exec` fires `SessionStart(source=startup)` **and** honors its `additionalContext` — headless
and interactive both. Move the dynamic memory base onto a `SessionStart` hook, leaving a
hand-owned static `AGENTS.md` for workflow rules + overlay only (the Antigravity model), so
plain `codex` gets full memory and the memory-tree file-build retires.

Validation (2026-07-16) upgraded the motivation from hygiene to a probable live bug: the
generated `AGENTS.md` is 35,311 bytes and `project_doc_max_bytes` is unset (codex default
32 KiB) — so today's base is likely **silently truncated at the tail**, which is exactly
where `working.md` (the freshest content) renders. Confirm during Phase 4's probe.

## Success criteria
- `drivers/hook.sh` registers the `session_bootstrap` command with `AI_MEMORY_HOOK_FORMAT=<manifest format>` env-wrapped (md for codex), verified by a test asserting the produced `SessionStart` command string contains `AI_MEMORY_HOOK_FORMAT=md` for the codex manifest.
- After install, `~/.codex/hooks.json` `SessionStart` runs the shared session-bootstrap script (not `arm_recompact.sh`), and a fresh `codex` session (no alias, no wrapper) shows the full `<memory:*>` base in context for a pinned repo.
- A one-shot `codex exec` in a pinned repo sees identity + project memory with **no** generated `AGENTS.md` present (re-run the isolated-home probe shape, asserting a project-memory-only fact is answerable).
- The **full-size** payload survives hook injection intact: the real render, chunked, reassembles **verbatim** from the session rollout's injected messages (byte comparison, NOT a sentinel echo — codex's middle-elision defeats tail sentinels).
- `AGENTS.md` no longer contains the memory tree — `codex-mem.sh` does not run `build-context-md.sh`; a hand-owned `~/.codex/AGENTS.md` is never overwritten by the memory system.
- No double-injection: the base appears exactly once in a session (hook only), confirmed by grepping a session transcript for a unique identity marker.
- `--executor-bare` runs get **no** injection at all — base *and* breadcrumbs absent (`AI_MEMORY_SKIP_INJECT=1` honored by both the session script and `inject.sh`), verified with a real bare run; `project_doc_max_bytes=0` retained for file/repo docs.
- `arm_recompact.sh` survives release N as a shim exec'ing the shared script (a stale `hooks.json` entry from a pre-flip install still works); its deletion is deferred to N+1.
- The header-keyed migration converts a generated `AGENTS.md` (header present → replaced with `AGENTS.local.md` content or a stub) and provably never touches a hand-owned one (header absent → byte-identical after run).
- `run-tests.sh` passes, including the new/updated codex-hooks, hook-mapping, and validate-manifest assertions.

## Design
- **End state = the Antigravity model.** Static base (workflow rules + user overlay) is a
  hand-owned `~/.codex/AGENTS.md`, never written by the memory system; dynamic memory
  (identity → project → index → domain → working) injects live via `SessionStart`. This is
  exactly `render_full` in `md` format, which the shared `scripts/hooks/lib.sh` already emits.
- **Reuse Claude's session script, don't fork it.** `harnesses/claude/hooks/session_start_memory.sh`
  already handles *both* branches: `source=startup` → emit `render_full`; `source=compact` →
  drop the sentinel and defer to `UserPromptSubmit`. `arm_recompact.sh` is a strict subset
  (compact branch only). **Relocate keeping the filename** — `scripts/hooks/session_start_memory.sh`
  (where `inject.sh`/`guard.sh`/`lib.sh` already live for the isomorphic Claude+Codex pair);
  point both manifests' `session_script` at it. Keeping the name means the existing
  `session_start_memory.sh` entry in `_hook_register_native_json`'s `ours` sweep-marker tuple
  matches **both** the old Claude registration and the new one — stale entries sweep on
  re-install with zero marker edits (same trick as the legacy `inject_memory.sh` marker).
  *Alternatives — leave it under `harnesses/claude/` → rejected: buries a shared script under
  one harness's dir, contradicting the scripts/hooks/ convention; rename to `session_start.sh`
  → rejected: requires growing the marker tuple to sweep the old name.*
- **`arm_recompact.sh` retires via N/N+1, not deletion.** `~/.codex/hooks.json` points at it
  by absolute path and is only rewritten by `install.sh` — a manual `git pull` crossing the
  commit would otherwise leave SessionStart on a dead path *and* no AGENTS.md build: zero
  memory, silently (the `identity.md`-untrack gotcha class). Release N ships it as a one-line
  shim exec'ing the shared script; N+1 deletes it. (`sync-system.sh` re-runs `install.sh`, so
  synced consumers re-register immediately; the shim protects manual pulls — how the dev
  instance got bitten last time.)
- **The engine gap.** `drivers/hook.sh:320` registers `session_cmd="bash $script"` with no
  format env, because Claude defaults to xml. Codex needs md. Fix: format-wrap `session_cmd`
  from the manifest `format` (same pattern as `inject_cmd`/`guard_cmd` at `:312`/`:316`).
- **File-build retirement is coupled to the wire-up, not a later phase.** Keeping a
  generated `AGENTS.md` *and* the hook would double-inject the whole base (~13k tokens). So
  the flip is atomic: when `SessionStart` starts injecting, `codex-mem.sh` must stop building
  the memory-tree `AGENTS.md` in the same change. The overlay (`AGENTS.local.md`) and any
  static workflow rules survive as a hand-owned `AGENTS.md`.
- **Bare-executor suppression is two levers, not a moved one.** `project_doc_max_bytes=0`
  stays (it suppresses the hand-owned AGENTS.md + repo-level docs); the hook side gains a
  dedicated `AI_MEMORY_SKIP_INJECT=1`, exported by `codex-mem.sh --executor-bare` and honored
  by **both** the session script and `inject.sh` (base *and* breadcrumbs — a lean reviewer
  gets nothing). Env inheritance through codex → hook is proven by the Antigravity guard
  precedent (`agy.sh` exports, hook reads). *Alternative — overload `AI_MEMORY_ROLE=bare` →
  rejected: role means task/explore/validate (what the run may* **do**, *guard semantics);
  injection is what the run* **sees** *— conflating the axes muddies both.*
- **Generated→hand-owned AGENTS.md conversion is a header-keyed migration.** The generated
  file self-identifies (`<!-- Generated by codex-mem … -->` header), so
  `migrations/<ver>-*.sh` can act safely by construction: header present → replace with
  `AGENTS.local.md` content (seeding the hand-owned file; stub if no overlay), header absent
  → hand-owned, never touched. Forward-only, idempotent. `AGENTS.local.md` retires — it
  existed only because AGENTS.md was regenerated. *Alternative — UPGRADING note only →
  rejected: leaves a stale memory snapshot as the static base on every instance that doesn't
  act, and this case (unlike the identity.md untrack) is one the runner* can *cover.*
- **Wrapper stays for the executor.** `codex-mem.sh` still assembles exec sandbox/network/
  stdin flags (`--executor`/`--executor-bare`). The win is scoped: the **file** goes, the
  **wrapper** stays for delegation.

## Decisions (locked)
- Static base becomes hand-owned `AGENTS.md`; memory tree moves to the `SessionStart` hook. Mirrors Antigravity.
- Relocate the session-bootstrap script to `scripts/hooks/session_start_memory.sh` — **same filename** (sweep-marker continuity). (Validated 2026-07-16.)
- `arm_recompact.sh`: **N/N+1 shim**, not same-release deletion (stale `hooks.json` absolute paths survive manual pulls). (Validated 2026-07-16.)
- Bare gate: dedicated **`AI_MEMORY_SKIP_INJECT=1`** honored by session script + `inject.sh`; `project_doc_max_bytes=0` retained. Not `AI_MEMORY_ROLE=bare`. (Validated 2026-07-16.)
- Generated→hand-owned AGENTS.md: **header-keyed migration**, seeding from `AGENTS.local.md`; overlay retires. (Validated 2026-07-16.)
- File-build retirement and hook wire-up ship together (double-injection forbids a redundant-overlap phase).
- Compaction-path reliability on codex is **out of scope for the flip** and gated separately (startup is probe-proven; compact is not). The existing sentinel→`UserPromptSubmit` recovery stays intact and unchanged.
- Content parity is exact by construction: hook `render_full` md and `build-context-md.sh` render the same section set (`identity project index domain working`) through the same formatter.

## Phases
### Phase 1 — engine: format-wrap the session-bootstrap command
- `drivers/hook.sh`: wrap `session_cmd` with `env MEMORY_DIR=… AI_MEMORY_HOOK_FORMAT=<format> AI_MEMORY_HOOK_EVENT=<event> bash $script` (parity with `inject_cmd`).
- Extend `scripts/tests/test_codex_hooks.sh`: assert the `SessionStart` command for the codex manifest carries `AI_MEMORY_HOOK_FORMAT=md` and points at the shared session script.

### Phase 2 — relocate + share the session-bootstrap script
- Move `harnesses/claude/hooks/session_start_memory.sh` → `scripts/hooks/session_start_memory.sh` — same filename (self-locate logic: fix the repo-root depth from `../../..` to `../..`).
- Update Claude manifest `session_script` to the new path; confirm Claude SessionStart still injects xml (no behavior change) and that re-install sweeps the old-path entry from `settings.json` (existing marker covers it).
- Add `AI_MEMORY_SKIP_INJECT=1` no-op gates to the session script and `inject.sh` (+ tests).
- **NB (sequencing fix, found in execution):** `arm_recompact.sh` → shim moved to **Phase 3**. If the shim (which exec's the *full* shared script, including the startup-inject branch) landed while codex's manifest still routes SessionStart through `compaction_arm`→`arm_script`, codex would start injecting at startup *while Phase 2 still builds AGENTS.md* → double-injection. The shim must land **with** the manifest flip + AGENTS.md retirement (atomic), so it belongs in Phase 3. Phase 2 leaves `arm_recompact.sh` + codex manifest untouched (zero codex behavior change).

### Phase 3 — flip codex manifest + retire the memory-tree AGENTS.md
- Codex manifest: replace `compaction_arm = SessionStart` (`arm_script`) with `session_bootstrap = SessionStart` (`session_script`). Keep `per_turn_inject`/`infra_guard` as-is (the compact recovery still rides `UserPromptSubmit` via the shared script's compact branch + `inject.sh`). Update `validate-manifest.sh` / `test_hook_mapping.sh` / `test_install_harness.sh` expectations.
- **Replace `harnesses/codex/hooks/arm_recompact.sh` body with a one-line shim exec'ing the shared `scripts/hooks/session_start_memory.sh`** (moved here from Phase 2 — see the sequencing NB). Shim defaults `AI_MEMORY_HOOK_FORMAT=md` so a stale pre-flip `hooks.json` entry (registered without the format env) still injects md. Delete in N+1. This is what makes the flip safe for a manual `git pull` that hasn't re-run `install.sh`.
- `codex-mem.sh`: stop calling `build-context-md.sh`; never write `AGENTS.md`. `--executor-bare` exports `AI_MEMORY_SKIP_INJECT=1` **and keeps** `-c project_doc_max_bytes=0`.
- Migration `migrations/<ver>-codex-agents-handoff.sh`: header-keyed — generated `AGENTS.md` → replaced with `AGENTS.local.md` content (stub if absent); no header → untouched. Idempotent.
- Update `install.sh` codex-hybrid notes / `drivers/file.sh` `driver_notes` (no longer "rebuilt each launch from memory"; now hand-owned static + live hook) + `UPGRADING.md` (re-trust: codex re-prompts `/hooks` when a hook command changes; headless bypasses).

### Phase 4 — verify + document
- Re-run the isolated-home probe shape: pin a repo, launch plain `codex` (no alias) and one-shot `codex exec`; confirm full base present, exactly once, no generated AGENTS.md, **tail sentinel intact at full ~35KB payload**.
- Verify the truncation hypothesis while at it: pre-flip AGENTS.md (35,311 B) vs codex default `project_doc_max_bytes` — record the finding either way.
- Real `--executor-bare` run: assert no base, no breadcrumbs.
- Update `memory.md` Architecture Decisions ("Codex adapter" + "Hook layer" entries — including the stale "Open: compaction_recovery … not yet on Codex" line) to reflect codex as hook-base + hand-owned static file.
- Remove `identity.md`'s Codex sibling-delegation caveat (per-cwd hook resolution obsoletes it); fix `memory.md` "mid-session memory edits don't appear until relaunch" (post-flip, `@memory` re-injects live).
- Update `docs/harnesses/codex.md` / `domain/codex.md`.

## Gate finding (2026-07-16) — cap probe FAILED; redesigned to chunked injection
The Phase 4 probe ran early (before merge, after Phase 3 was built) and **failed**: codex
hard-caps EVERY hook `additionalContext` message at **~10,100 bytes** (intact ≤ ~10,000B),
middle-eliding with a `…N tokens truncated…` marker — head and tail survive, so a
tail-sentinel-only check passes on a 90%-dropped payload. Verification must be a
**verbatim full-payload comparison against the session rollout**, never a sentinel echo.
The cap applies to SessionStart AND UserPromptSubmit (so the shipped post-compact full
re-inject on main silently truncates today for >10KB payloads — same fix covers it), is
not lifted by `tool_output_token_limit`, and has no visible config knob (codex 0.144.4).
Counter-probe: **multiple hook entries each get their own ~10KB budget, delivered in
registration order** — chunked injection is viable. Probes were token-free: real auth +
`openai_base_url` pointed at a dead port; the rollout records the (truncated) hook
message before any API call.

**User decisions (2026-07-16):** chunked hooks transport. *(Superseded same day:)* domain
was to be dropped from the md render on my claim it inlined 61.5KB — measurement showed
the md `domain` section is a ~6.5KB **lazy-load table**, not inlined files; with corrected
numbers the user chose to **keep the domain table** (payload ~96.8KB → 11-12 slices of
the 12 registered; `session_chunks`/`inject_chunks = 12`, ~108KB capacity, loud overflow).

### Phase 3b — chunked hook injection (build)
- `render_full` md: drop `domain` (align with xml section set).
- `scripts/hooks/lib.sh`: deterministic line-boundary slicer — full payload → ≤9,000B
  slices; helper selects slice i of N from `AI_MEMORY_HOOK_CHUNK=i/N`. **Stateless**:
  every chunk invocation renders + slices independently (no cache, no ordering dependency).
  Slice overflow (payload > N slices) appends a loud `[ai-memory: base truncated — raise
  session_chunks]` line to the LAST slice — fail loud, never silent.
- `drivers/hook.sh`: manifest keys `session_chunks` / `inject_chunks` (default 1). N>1 →
  register N entries for the event, each env-wrapped with `AI_MEMORY_HOOK_CHUNK=i/N`;
  N=1 keeps today's single-entry command byte-identical (Claude unchanged). Sweep must
  remove ALL stale same-script entries on re-install.
- `session_start_memory.sh`: chunk-aware (emit slice i); compact-arm fires from chunk 1
  only. `inject.sh`: post-compact full re-inject chunk-aware; per-prompt breadcrumb from
  chunk 1 only.
- codex manifest: `session_chunks = 8`, `inject_chunks = 8`.
- `validate-manifest.sh` KNOWN_KEYS + tests: chunked registration (test_codex_hooks,
  test_install_harness), slicer determinism/empty/overflow + chunk-1-only arming
  (test_shared_hooks), chunked re-inject (test_inject_memory).

## Risks / open questions
- **Hook execution order across N entries is observed, not documented.** The 3-entry probe
  delivered messages in registration order; the stateless slicer makes correctness
  order-independent, but out-of-order delivery would interleave the base oddly. Phase 4's
  verbatim rollout check catches it (concatenated slices must reassemble the render).
- **Compaction reliability on codex is unproven.** Only `source=startup` is probe-confirmed. If codex's SessionStart `additionalContext` is unreliable post-compaction (as on Claude), the recovery path *must* stay on the `UserPromptSubmit` sentinel — which it does; this plan does not touch it. Re-probe compact before any later simplification.
- **Double-injection during rollout.** Manifest flip and `codex-mem.sh` file-retirement must land in the same change/commit, else a window exists where both AGENTS.md and the hook inject (~13k tokens twice).
- **Bare-gate correctness.** A wrong `AI_MEMORY_SKIP_INJECT` gate leaks the full base into every lean review subagent, silently — hence the real-bare-run criterion.
- **Cross-harness relocation.** Moving the session script changes Claude's wiring too; Claude SessionStart must be re-verified (xml, startup + compact) so the move is behavior-preserving for both harnesses.
- **Trust re-prompt.** Changed hook commands make interactive codex re-ask `/hooks` trust once; until trusted, hooks (and therefore memory) don't run. UPGRADING note; headless is unaffected (`--dangerously-bypass-hook-trust`).
