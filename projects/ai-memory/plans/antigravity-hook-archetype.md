---
plan: antigravity-hook-archetype
status: draft
created: 2026-07-06
owner: claude (orchestrator)
---

# Plan — Antigravity hook-archetype (live injection + PreToolUse enforcement)

## Goal
Promote Antigravity from a `file`-archetype harness (AGENTS.md rebuilt by the `agy.sh` launch
wrapper, stale until relaunch) to a genuine **`hook` archetype** using its `hooks.json`. A
`PreInvocation` hook injects memory **live, cwd-resolved, per model call** — exactly like Claude's
`UserPromptSubmit` — eliminating the relaunch-to-refresh caveat *and* the global-AGENTS.md
location/concurrency problem. A `PreToolUse` guard adds **preventive** enforcement (the O/E/V
deny-list, plus enforced read-only for the `explore` executor role), making Antigravity the second
harness with real guardrails after codex execpolicy.

## Success criteria
- A `PreInvocation` hook injects project memory into Antigravity **without relaunch**: editing
  `working.md` mid-session and triggering a new model call surfaces the change.
- Injection is **cwd-resolved per invocation** — launching/working in different pinned repos resolves
  the correct project (no global single-file clobber). `invocationNum==1` → full payload; later → the
  `<memory:active>` breadcrumb.
- The memory-built **AGENTS.md is gone**; only the hand-owned `AGENTS.local.md` overlay remains as the
  static base. Antigravity manifest is `archetype = hook`.
- A `PreToolUse` guard, active **only for executor delegations** (gated on `AI_MEMORY_ROLE`): denies the
  O/E/V deny-list (apply/merge/destructive), and *additionally* denies write tools when `AI_MEMORY_ROLE=explore`.
  Interactive `agy` sessions are unguarded.
- Antigravity gains a working **`exec_readonly`** → it resolves as a valid `explore`-role executor (no
  longer degrades to Claude Explore); `test_executor.sh` reflects it.
- The deny-list is a **shared shipped artifact** (a file the guard reads), reusable by a future
  `guard` manifest capability — not inline prose.
- Full suite green; Claude wiring untouched (byte-identical).

## Design
Reached via the brainstorming skill (2026-07-06). Antigravity `hooks.json` (`PreInvocation` for live
injection; `PreToolUse` for enforcement) is the enabling mechanism.

**Inject — pure hook (chosen).** One `PreInvocation` script resolves the active project from `cwd`
(`workspacePaths`) per call and emits `injectSteps` (`ephemeralMessage`) built from `content-core.sh`:
`invocationNum==1` → full (identity/project/index/working), else → breadcrumb. The memory-built AGENTS.md
is dropped; the static `AGENTS.local.md` overlay stays (the true `~/.claude/CLAUDE.md` analogue).
- *Rejected — hybrid (AGENTS.md base + hook delta):* its "persistent per-project base" doesn't exist —
  the built AGENTS.md's only home is a **global** `~/.gemini/config/AGENTS.md` (single-project, clobbers
  under concurrency, and unverified that Antigravity even reads it there). Pure hook is cwd-resolved like
  Claude, so it sidesteps the file-location question entirely.
- *Rejected — keep file archetype:* the relaunch caveat + global-file concurrency are exactly what this
  plan removes.

**Contract adapter.** Antigravity's hook I/O differs from Claude's (JSON stdin `invocationNum` → JSON
stdout `injectSteps`, vs Claude's raw-text `additionalContext`). So the Phase-3 `hook` driver / a new
Antigravity hook script wraps the shared `content-core.sh` output in Antigravity's `injectSteps` envelope
— the *selection* stays shared, only the serialization/registration differs.

**Enforce — one `PreToolUse` guard, executor-only (chosen).** A guard script reads `toolCall.name` +
`args.CommandLine`, returns `allow`/`deny`. Gated on `AI_MEMORY_ROLE` (set by `executor.sh` at launch):
- **executor sessions:** always deny the O/E/V deny-list (apply/merge/destructive), matched against
  `CommandLine` (covers `run_command`, which is both read and write) + known write tools.
- **`explore` additionally:** deny *all* write tools → Antigravity becomes a real read-only executor,
  supplying the `exec_readonly` it lacks today.
- **interactive `agy`:** unguarded (the human decides).
- *Rejected — always-on for all sessions:* constrains the user's own hands; codex-style always-on floor
  is stronger but the user chose executor-only.

**Deny-list as a shared artifact.** The list ships as data (`scripts/deny-list.*`), read by the guard —
seeding the future manifest `guard` capability (working.md generalization) without building that
mechanism yet (YAGNI until a 2nd hook-capable harness needs it).

## Decisions (locked)
- **Inject model = pure hook** (`PreInvocation`, cwd-resolved, `invocationNum`-gated); drop the built
  AGENTS.md; keep the `AGENTS.local.md` overlay as the static base. Manifest → `archetype = hook`.
- **Enforcement = one `PreToolUse` guard, executor-delegations-only** (gated on `AI_MEMORY_ROLE`):
  always-on deny-list for executor sessions + read-only when `explore`. Interactive `agy` unguarded.
- **Deny-list is a shared shipped artifact** the guard reads (reusable), not inline prose.
- **Scope = both** injection and enforcement (two phases behind one `hooks.json`).
- Content **selection stays in `content-core.sh`**; only Antigravity's hook I/O envelope + registration
  are new. Claude behavior untouched.

## Phases
### Phase 0 — Probe Antigravity's tool catalog (prerequisite)
- Enumerate `agy`'s tool names (write vs read) from docs / a live session — only `run_command`,
  `view_file`, `browser_*` are known. Authors the write-tool list the guard needs. Confirm the
  `hooks.json` install location (workspace `.agents/hooks.json` vs global `~/.gemini/config/`).

### Phase 1 — PreInvocation live injection (hook archetype)
- Antigravity hook script: read stdin (`invocationNum`, `cwd`), resolve project, build via `content-core.sh`,
  emit `injectSteps`. Generalize/extend the `hook` driver for the JSON envelope + `hooks.json` registration.
- Flip `harnesses/antigravity/manifest` to `archetype = hook`; retire the built-AGENTS.md path (keep overlay).
- Tests (hermetic hook I/O: full on `invocationNum==1`, breadcrumb after, cwd resolution).

### Phase 2 — PreToolUse guard (enforcement) + exec_readonly
- Guard script + shared deny-list artifact; `AI_MEMORY_ROLE`-gated (deny-list always; write-deny on explore).
- `executor.sh` sets `AI_MEMORY_ROLE` on launch; Antigravity manifest gains `exec_readonly`; `test_executor.sh`
  reflects Antigravity as a valid `explore` executor.
- Tests (deny-list blocks; explore denies writes; interactive unguarded).

### Phase 3 — Docs
- `docs/harnesses/antigravity.md`, adding-a-harness (hook archetype for a JSON-contract harness), working.md
  enforcement note graduated.

## Risks / open questions
- **Tool-catalog dependency (Phase 0 gates the rest).** The write-tool list is unknown beyond
  `run_command`/`view_file`/`browser_*`; the guard's write-denial is best-effort until confirmed. The
  `CommandLine` deny-list covers the destructive class regardless.
- **`ephemeralMessage` persistence** — confirm it survives the turn adequately; if too transient for the
  breadcrumb, fall back to `userMessage`. Verify against a live `agy` session.
- **`hooks.json` discovery location** — global vs workspace `.agents/hooks.json`; affects install (the
  hook driver's registration step).
- **Generalizing the `hook` driver** — how much of Antigravity's JSON contract the driver absorbs vs a
  per-harness override script; decide during Phase 1.
- Multi-harness `guard` manifest capability is **out of scope** (deferred until a 2nd hook-capable harness).
