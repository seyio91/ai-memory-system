---
doc: hook-standardization
kind: investigation
status: open — review + design (2026-07-12)
created: 2026-07-12
owner: claude (orchestrator)
task_ref: 39bf6850-c619-817d-88a5-e32f529496fe
---

# Investigation — standardize the hook layer across harnesses

Trigger: while designing [[on-demand-project-load]] we found Codex now ships **stable native hooks**
(`codex features list` → `hooks stable true`), including a `UserPromptSubmit` event that injects
model-visible `additionalContext` — schema-identical to Claude. That retired the "Codex can't switch
mid-session" blocker and exposed a bigger opportunity: **the hook layer is wired ad-hoc per harness; it should
be a single declarative, manifest-driven capability.** This doc = (A) review of current hook usage, (B) the
Codex-features-onto-hooks review, (C) a standardization + onboarding design.

## Key finding — Claude and Codex hook systems are isomorphic; Antigravity diverges

| Contract element | Claude Code | Codex CLI (≥ ~0.135) | Antigravity (`agy`) |
|---|---|---|---|
| Per-turn pre-model event | `UserPromptSubmit` | `UserPromptSubmit` | `PreInvocation` |
| Session event | `SessionStart` (`source`=startup/resume/clear/compact) | `SessionStart` (same `source` set) | first `PreInvocation` |
| Tool gate | `PreToolUse` (+ matcher) | `PreToolUse` (matcher `^Bash$`/`apply_patch`/mcp) | `PreToolUse` (matcher `*`) |
| Compaction | `SessionStart source=compact` + sentinel | `PreCompact` / `PostCompact` (native) | — |
| Stdin JSON | `session_id`, `cwd`, `prompt`, `hook_event_name`… | `session_id`, `cwd`, `prompt`, `hook_event_name`, `model`, `turn_id`, `source`… | agy hook payload (no session id) |
| Inject output | `hookSpecificOutput.additionalContext` | `hookSpecificOutput.additionalContext` (identical) | XML `<memory:*>` payload |
| Block output | exit 2 / `decision:block` | exit 2 / `decision:block` (identical) | guard denies via `AI_MEMORY_ROLE` |
| Registration | `~/.claude/settings.json` (manual merge) | `~/.codex/hooks.json` or `[hooks]` in `config.toml` | `~/.gemini/config/hooks.json` (driver-written) |

**Implication:** Claude's hook scripts (`inject_memory.sh`, `session_start_memory.sh`, `block_task_tools.sh`)
read the same stdin fields and emit the same `additionalContext` Codex expects — they can be **shared
harness-neutral scripts**, with Antigravity the one harness needing an I/O adapter (`PreInvocation` name +
XML payload + no `session_id`).

## A. Current hook inventory (as built)

- **Claude** (hook archetype). 3 hooks in `settings.json` (manually merged from `settings.hooks.json`):
  `UserPromptSubmit`→`inject_memory.sh` (per-turn breadcrumb / full reload), `SessionStart`→
  `session_start_memory.sh` (full inject once; arms compaction sentinel), `PreToolUse` matcher
  `TaskCreate|TaskUpdate`→`block_task_tools.sh`. Plus symlinked `statusline.sh`. Shared lib
  `memory_common.sh` (`detect_project`, `assemble_*`).
- **Antigravity** (hook archetype). `hooks.json` written by `drivers/hook.sh:141`: `ai-memory-inject`→
  `PreInvocation`→`preinvocation.sh` (live memory inject), `ai-memory-guard`→`PreToolUse` matcher `*`→
  `pretooluse.sh` (executor-only infra deny via `AI_MEMORY_ROLE`). Plus statusline via
  `statusline_settings`.
- **Codex** (file archetype — NO hooks today). `codex-mem.sh` rebuilds `~/.codex/AGENTS.md` at launch via
  `build-context-md.sh`. Infra deny = optional `~/.codex/rules/default.rules` execpolicy + `--sandbox`
  flag. `/checkpoint` via prompt + skill.
- **The driver** (`drivers/hook.sh`) has **two hardcoded registration styles** (`hooks_dir` symlink +
  manual settings note for Claude; `hooks_json` with **hardcoded event names** `PreInvocation`/`PreToolUse`
  for Antigravity). Role→event mapping is implicit and duplicated; Codex isn't in this path at all.

## B. Codex features → hooks (the "review all Codex features to use hooks")

Target = **hybrid**: keep `AGENTS.md` for the static base (the `CLAUDE.md` analogue — identity + workflow
rules, stable per session); move everything *dynamic* onto hooks.

| Capability | Codex today (file) | Codex with hooks (target) |
|---|---|---|
| Identity + workflow-rules base | `AGENTS.md` at launch | **keep** `AGENTS.md` (static, correct as-is) |
| Per-turn active-project memory + `working.md` | baked into `AGENTS.md` at launch → **stale mid-session, no live project switch** | **`UserPromptSubmit`** hook → live inject; **unblocks mid-session project switch** + fresh working overlay |
| Session bootstrap / full payload | `AGENTS.md` | `SessionStart` hook (or leave to `AGENTS.md` base) |
| Infra deny-list guard | `~/.codex/rules/default.rules` (optional execpolicy) | **`PreToolUse`** hook (matcher `^Bash$`/`apply_patch`) — a real gate, same as others |
| Compaction recovery | none | **`PreCompact`/`PostCompact`** (native events) |
| Checkpoint on wind-down | skill/prompt | optional **`Stop`** hook to auto-checkpoint |

Net: Codex stops being a pure file archetype and becomes **file(base) + hook(dynamic)** — and gains
mid-session project switch, live working.md, and a real infra gate.

## C. Standardization design

**1. Canonical hook roles** (harness-neutral names the memory system reasons about):
`session_bootstrap`, `per_turn_inject`, `infra_guard`, `task_tool_block`, `compaction_recovery`
(+ optional `checkpoint_on_stop`).

**2. Canonical contract = the Claude/Codex one.** Stdin JSON (`session_id`, `cwd`, `prompt`,
`hook_event_name`, `source`, `tool_name`…); stdout `hookSpecificOutput.additionalContext` to inject; exit 2
/ `decision:block` to gate. Shared scripts speak this contract; Antigravity gets a thin adapter.

**3. Manifest-declared role→event map.** Replace the hardcoded event names in `drivers/hook.sh` with a
declarative block per manifest, e.g.:

```
[hooks]
per_turn_inject    = UserPromptSubmit         # Codex/Claude; Antigravity: PreInvocation
session_bootstrap  = SessionStart
infra_guard        = PreToolUse:^Bash$|apply_patch
task_tool_block    = PreToolUse:TaskCreate|TaskUpdate
compaction_recovery= PreCompact,PostCompact
```

The generalized driver reads role→{event,matcher}, maps each to the shared script, and writes it into the
harness's native hooks file in that harness's JSON/TOML shape (Claude `settings.json`, Codex `hooks.json`,
Antigravity `hooks.json`). **Onboarding a harness = fill in this map + declare the JSON shape**; no driver
code per harness.

**4. Shared hook scripts.** Because Claude≡Codex contract, the injector/guard/blocker scripts become
harness-neutral (live under `scripts/hooks/` or promoted from `harnesses/claude/hooks/`), consuming the
canonical stdin and emitting the canonical stdout. Antigravity keeps a small adapter that maps its
`PreInvocation` payload ↔ canonical + renders XML.

**5. This subsumes the backlog "guard capability" task.** Task `396f6850-c619-81b2-…` ("Manifest guard
capability — unify executor infra-deny across harnesses") is exactly the `infra_guard` role here. It should
be folded into this standardization rather than done separately.

## Relationship to other work

- **[[on-demand-project-load]]** becomes a *consumer*: with Codex on `UserPromptSubmit`, the project-switch
  capability is supported on all three harnesses (no Codex exclusion). The pin resolver plugs into
  `per_turn_inject` uniformly. Update that doc's decision #4 accordingly (the "Codex not supported" reversal,
  already started, is finished by this initiative).
- Codex native **`memories`** feature exists (`experimental`, off) — potential overlap with this whole
  system; note for later, out of scope now.

## Open questions / forks

1. **How much script sharing?** (a) One harness-neutral script set both Claude & Codex use + Antigravity
   adapter [recommended — the contract is identical], vs (b) keep per-harness scripts, standardize only the
   wiring. Fork on maintenance vs. blast radius.
2. **Codex target = hybrid vs full-hook.** Recommended hybrid (AGENTS.md base + hooks for dynamic). Full-hook
   (drop AGENTS.md) is simpler conceptually but loses the always-present base if a hook fails to register.
3. **Claude registration parity.** Claude's `settings.json` merge is a *manual* note today (unlike
   Antigravity's driver-written `hooks.json`). Standardization could auto-merge Claude too — but Claude
   `settings.json` is user-owned and risky to rewrite. Decide: keep manual, or driver-merge with the same
   fail-closed backup logic already in `_hook_register_json`.
4. **Codex trust model.** Non-managed Codex hooks require explicit trust (`/hooks`), or
   `--dangerously-bypass-hook-trust`, or `requirements.toml` managed hooks. Onboarding must handle first-run
   trust — likely register as managed via `requirements.toml`, or document the one-time `/hooks` trust step.
5. **Version floor.** Codex hook support (esp. `UserPromptSubmit`+`additionalContext`) lands ~April-2026
   stable / present in 0.135.0. Gate the Codex hook capability on a probed codex version (extend
   `exec_probe`).

## Verification — Codex hook injection CONFIRMED (2026-07-12)

- **Empirical Codex hook test PASSED.** A project-local `.codex/hooks.json` `UserPromptSubmit` hook emitting
  a marker (`BANANA7788`) via `hookSpecificOutput.additionalContext`, run headless via
  `codex exec --cd <dir> --skip-git-repo-check --dangerously-bypass-hook-trust --sandbox read-only -o answer.txt`,
  made the model answer with exactly the marker — content it could only know from the injected context.
  Runtime reported **OpenAI Codex v0.144.1**. Project-local `.codex/hooks.json` discovery + headless trust
  bypass both work. **Codex per-turn context injection is proven; the Codex-on-hooks pivot is validated, not
  just doc-backed.** Harness preserved under scratchpad `codex-hook-test/`.
