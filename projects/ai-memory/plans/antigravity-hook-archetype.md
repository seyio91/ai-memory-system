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
- The memory-built **AGENTS.md is gone**; only a hand-owned static global `~/.gemini/config/AGENTS.md`
  (workflow-rules base, the `~/.claude/CLAUDE.md` analogue — *not* `AGENTS.local.md`, which agy lacks)
  remains. Antigravity manifest is `archetype = hook`.
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
is dropped; a hand-owned static global `~/.gemini/config/AGENTS.md` carries the workflow-rules base (the
`~/.claude/CLAUDE.md` analogue — agy has **no** `AGENTS.local.md`, so the static base is a plain AGENTS.md).
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
  AGENTS.md; static base = hand-owned global `~/.gemini/config/AGENTS.md` (agy has no `AGENTS.local.md`).
  Manifest → `archetype = hook`.
- **Enforcement = one `PreToolUse` guard, executor-delegations-only** (gated on `AI_MEMORY_ROLE`):
  always-on deny-list for executor sessions + read-only when `explore`. Interactive `agy` unguarded.
- **Deny-list is a shared shipped artifact** the guard reads (reusable), not inline prose.
- **Scope = both** injection and enforcement (two phases behind one `hooks.json`).
- Content **selection stays in `content-core.sh`**; only Antigravity's hook I/O envelope + registration
  are new. Claude behavior untouched.

## Phase 0 findings (probe complete — 2026-07-06)
Probed `agy` v1.0.16 (binary `~/.local/bin/agy`; runtime state `~/.gemini/antigravity-cli/`; docs
`~/.gemini/antigravity-cli/builtin/skills/agy-customizations/docs/`). Sandbox note: home-dir reads
need sandbox disabled or they return empty.

- **hooks.json location — RESOLVED. Two customization roots** (`json_configs.md`): **global
  `~/.gemini/config/`** and per-project **`.agents/`** (walked up from cwd to repo root, git-style).
  → **Install the memory hooks globally at `~/.gemini/config/hooks.json`** — fires for every `agy`
  session regardless of repo, the exact analogue of Claude's global `~/.claude/settings.json` hooks.
  (Workspace `.agents/hooks.json` is the per-repo/team-shared surface; not what we want for a global
  memory install.) Hook handler cwd = the dir containing `hooks.json` (`~/.gemini/config/`); the
  script resolves the *real* repo from the stdin `workspacePaths`/`cwd`, not its own cwd — so a global
  hook still resolves the active project per-invocation. `~/.agents/` also exists at home level and is
  reachable by walk-up, but the config root is the documented global location.
- **AGENTS.md discovery + no `AGENTS.local.md`.** `AGENTS.md`/`GEMINI.md` are walked up cwd→repo root and
  merged; a global `~/.gemini/config/AGENTS.md` applies to *every* session. ⚠️ **`AGENTS.local.md` does
  not exist in agy** (string absent from binary) — the design's "keep the AGENTS.local.md overlay" is
  corrected to: **static workflow-rules base = a hand-owned global `~/.gemini/config/AGENTS.md`** (the
  true `~/.claude/CLAUDE.md` analogue: static, global, always-on). The *dynamic per-project memory*
  moves entirely into the PreInvocation hook — so a global static `AGENTS.md` is fine (it carries no
  per-project content, hence no clobber). What the pure-hook design drops is the *memory-built* AGENTS.md.
- **Tool catalog** (binary `CORTEX_STEP_TYPE_*` enum + binary strings + live `transcript.jsonl`
  ground-truth). ⚠️ **Derived name ≠ live `toolCall.name` for some tools** — the doc's "lowercase the
  step type" rule is only approximate: step type `LIST_DIRECTORY` surfaces as `list_dir`,
  `list_permissions` isn't in the enum at all. **The guard must use broad regex matchers + in-script
  logic, NOT a hardcoded exact-name list**, and be spot-verified against a live transcript.
  Agent-invokable **WRITE** set (explore denies): file edits `write_to_file`/`write_file`/`create_file`/
  `replace_content`/`delete_file` (+ step types `WRITE_BLOB`/`FILE_CHANGE`/`PROPOSE_CODE`), `move`,
  `delete_directory`, `edit_notebook`, `execute_notebook`; shells `run_command`/`shell_exec`/
  `send_command_input`/`run_extension_code`; `git_commit`, `generate_image`, `restart_dev_server`,
  `execute_browser_javascript`, `cloud_sql_execute_sql`/`cloud_sql_update_schema`/`set_up_cloud_sql`,
  `deploy_firebase`/`set_up_firebase`, `install_applet_package`/`install_applet_dependencies`,
  `invoke_subagent`/`browser_subagent`, `brain_update`, `mcp_tool` (capability = server-defined, treat
  as write), browser-mutation `browser_*` (click/input/press_key/select/scroll/drag/mouse_*/resize/
  refresh, `open_browser_url`). **READ** set (allowed): `view_file`/`view_file_outline`/`view_code_item`/
  `view_content_chunk`, `list_dir`, `grep_search`, `code_search`, `find`/`find_all_references`,
  `read_resource`/`read_notebook`/`read_terminal`/`read_url_content`/`read_browser_page`, `list_resources`,
  `search_web`, `retrieve_memory`, browser reads (`browser_get_dom`, `capture_browser_*`,
  `list_browser_pages`, `browser_*_network_request*`), `list_permissions`, `ask_question`/`notify_user`.
- **Deny-list is robust regardless of tool-name drift:** every O/E/V destructive op (terraform/kubectl
  apply, gh/bkt/az merge, helm install/upgrade, destroy) runs via **`run_command`**, so matching its
  `args.CommandLine` covers the whole class — that's the guard's primary matcher; broad write-tool-name
  regex is the secondary (explore) layer. `overwrite` in PreToolUse is **not implemented** — the guard
  can only `allow`/`deny`/`ask`, not rewrite args (fine; we only deny).
- **PreToolUse decision vocabulary:** `allow` / `deny` (hard block) / `ask` / `force_ask`. Guard emits
  `{"decision":"deny","reason":...}`. PreInvocation emits `{"injectSteps":[{"ephemeralMessage":...}]}`.

## Phases
### Phase 0 — Probe Antigravity's tool catalog (prerequisite) — ✅ done
- Enumerated the tool catalog (write vs read) and resolved the `hooks.json` install location — see
  **Phase 0 findings** above. Install target: global `~/.gemini/config/hooks.json`.

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
- ~~**Tool-catalog dependency**~~ — RESOLVED (Phase 0). Write/read lists authored above. **Guard uses
  broad regex matchers + in-script logic, not hardcoded names** (derived names drift from live
  `toolCall.name`, e.g. `list_dir`); spot-verify against a live transcript
  (`~/.gemini/antigravity-cli/brain/<id>/.system_generated/logs/transcript.jsonl`) in Phase 2. The
  `run_command` `CommandLine` deny-list covers the destructive class regardless of naming.
- **Workspace-trust allowlist** — NEW, OPEN. `~/.gemini/antigravity-cli/settings.json` has a
  `trustedWorkspaces` list; hooks/customizations may only auto-run in trusted workspaces. Confirm a
  global `~/.gemini/config/hooks.json` fires in a fresh/untrusted repo — else install must also register
  the repo as trusted. Needs a live authed `agy` session.
- ~~**`hooks.json` discovery location**~~ — RESOLVED (Phase 0): global `~/.gemini/config/hooks.json`
  (per-repo `.agents/hooks.json` is the alternative surface, not used for the global install).
- **`ephemeralMessage` persistence** — STILL OPEN. Confirm it survives the turn adequately; if too
  transient for the breadcrumb, fall back to `userMessage`. Needs a live authed `agy` session
  (couldn't exercise the loop in the read-only probe).
- **Generalizing the `hook` driver** — how much of Antigravity's JSON contract the driver absorbs vs a
  per-harness override script; decide during Phase 1. (The Claude `hook` driver emits raw-text
  `additionalContext`; Antigravity needs a JSON `injectSteps` envelope + `hooks.json` registration into
  the global config root.)
- Multi-harness `guard` manifest capability is **out of scope** (deferred until a 2nd hook-capable harness).
