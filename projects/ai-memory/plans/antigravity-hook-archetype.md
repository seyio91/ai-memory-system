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
- Injection resolves **the correct project per session** — launching in different pinned repos injects
  the right project's memory (no global single-file clobber; project comes from the launch env, see
  Design). `invocationNum==0` → full payload; later invocations → the `<memory:active>` breadcrumb.
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

**Inject — pure hook (chosen).** A global `~/.gemini/config/hooks.json` `PreInvocation` script emits
`injectSteps` (`ephemeralMessage`) built from `content-core.sh`: `invocationNum==0` → full
(identity/project/index/working), else → breadcrumb. **Project resolution (revised after live probe):**
the global hook payload carries no workspace handle (`workspacePaths=[]`; hook cwd = the config dir), so
the active project is resolved at **launch** by the `agy.sh` wrapper (from `$PWD`) and **exported into
agy's env** (`AI_MEMORY_PROJECT` + `MEMORY_DIR`), which the hook inherits and reads (env inheritance
verified live). An `agy` session is single-workspace for its lifetime, so launch-time resolution ==
per-invocation; the hook still re-reads content each call (live `working.md` refresh). The memory-built
AGENTS.md is dropped; a hand-owned static global `~/.gemini/config/AGENTS.md` carries the workflow-rules
base (the `~/.claude/CLAUDE.md` analogue — agy has **no** `AGENTS.local.md`, so the static base is a
plain AGENTS.md).
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
- **Inject model = pure hook** (`PreInvocation`, `invocationNum`-gated: **0-based**, `==0` → full);
  project resolved at launch via env (`agy.sh` exports `AI_MEMORY_PROJECT`/`MEMORY_DIR`, hook reads them
  — the payload has no workspace handle); drop the built AGENTS.md; static base = hand-owned global
  `~/.gemini/config/AGENTS.md` (agy has no `AGENTS.local.md`). Manifest → `archetype = hook`.
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

### Live verification (2026-07-06 — throwaway global hooks.json + real `agy -p` runs, since removed)
Ran a real authed `agy` (Gemini 3.5 Flash) with a temporary global `~/.gemini/config/hooks.json`. All
proven against ground-truth; config dir restored to pristine (no hooks.json left behind).
- ✅ **Global hook auto-runs in an *untrusted* workspace.** Both `PreInvocation` and `PreToolUse` fired
  in a fresh dir not in `trustedWorkspaces` → **trust does NOT gate the global hook.** (RESOLVED the
  trust open question.)
- ✅ **`ephemeralMessage` reaches the model.** Injected "codename = BLUE-GIRAFFE-42"; the model answered
  `BLUE-GIRAFFE-42`. Re-injected every invocation, so cross-invocation persistence is a non-issue —
  `userMessage` fallback NOT needed. (RESOLVED.)
- ✅ **`PreToolUse` deny hard-blocks.** Denying a sentinel `run_command` returned to the model as
  `tool call denied ... blocked by memory test guard` — the enforcement path works end-to-end.
- ⚠️ **`invocationNum` is 0-BASED** (observed 0 → 1 → 2 across one turn). The full-vs-breadcrumb gate is
  **`invocationNum == 0` → full**, else breadcrumb. (Plan previously said `==1`; corrected throughout.)
- ⚠️ **The `PreInvocation` payload has NO workspace handle.** `workspacePaths=[]` even in a git repo AND
  in a trusted workspace; hook `cwd`/`PWD` = `~/.gemini/config` (the hooks.json dir), never the user's
  repo. Payload fields are only `conversationId`, `transcriptPath`, `artifactDirectoryPath`,
  `invocationNum`, `initialNumSteps`, `modelName`. → **cwd/payload-based project resolution is impossible
  for a global hook.**
- ✅ **Resolution mechanism found — launch-env inheritance.** The hook process **inherits env vars
  exported when `agy` is launched** (verified: `AI_MEMORY_PROBE=HELLO123` reached the hook). So `agy.sh`
  resolves the active project from `$PWD` at launch and exports it (`AI_MEMORY_PROJECT` + `MEMORY_DIR`);
  the `PreInvocation` hook reads those to select which project's memory to inject. An `agy` session is
  single-workspace for its lifetime, so launch-time resolution == per-invocation; the hook still re-reads
  content each call, preserving live `working.md` refresh. (Per-repo `.agents/hooks.json` — working dir =
  the repo — is a viable alternative but abandons the install-once-globally model; not chosen.)
- **Confirmed live tool names:** `list_permissions` (fires first, invNum 0), `run_command` (args:
  `CommandLine`, `Cwd`, `WaitMsBeforeAsync`).

## Phases
### Phase 0 — Probe Antigravity's tool catalog (prerequisite) — ✅ done
- Enumerated the tool catalog (write vs read) and resolved the `hooks.json` install location — see
  **Phase 0 findings** above. Install target: global `~/.gemini/config/hooks.json`.

### Phase 1 — PreInvocation live injection (hook archetype) — ✅ done
Shipped: `scripts/jsonutil.sh` (shared json_escape/json_get), `harnesses/antigravity/hooks/
preinvocation.sh` (env-resolved, `invocationNum==0`→full via `content_sections|xml_render_*`), `agy.sh`
rewritten to export `AI_MEMORY_PROJECT`/`AI_MEMORY_CWD`/`MEMORY_DIR` (build-AGENTS.md dropped), manifest
flipped to `archetype=hook`/`format=xml` (+ `hooks_json`/`hook_script`), `hook` driver generalized to
register a namespaced PreInvocation entry into `~/.gemini/config/hooks.json` (python3 idempotent merge),
`validate-manifest` accepts `hooks_dir|hooks_json`. Suite 27/27. **Verified live:** a real `agy -p`
answered `ai-memory` + `Platform / Kubernetes Engineer` purely from the injected 50KB full payload.
- Antigravity hook script: read stdin `invocationNum`, read `AI_MEMORY_PROJECT`/`MEMORY_DIR` from env
  (exported by `agy.sh` at launch — payload has no workspace handle), build via `content-core.sh`, emit
  `injectSteps` (`ephemeralMessage`). Generalize/extend the `hook` driver for the JSON envelope +
  registration into global `~/.gemini/config/hooks.json`.
- `agy.sh`: resolve active project from `$PWD` at launch, export `AI_MEMORY_PROJECT` + `MEMORY_DIR`,
  drop the built-AGENTS.md path (static `~/.gemini/config/AGENTS.md` overlay stays).
- Flip `harnesses/antigravity/manifest` to `archetype = hook`.
- Tests (hermetic hook I/O: full on `invocationNum==0`, breadcrumb after; env-based project resolution).

### Phase 2 — PreToolUse guard (enforcement) + exec_readonly — ✅ done
Shipped: `harnesses/antigravity/hooks/pretooluse.sh` (self-gates on `AI_MEMORY_ROLE`; layer 1 = shared
deny-list matched on `CommandLine` for both roles; layer 2 = read-only **allowlist** for explore — chosen
over deny-by-name because live tool names drift, so allow-by-name fails safe), `scripts/deny-list.txt`
(shared shipped artifact: terraform/kubectl apply, gh/bkt/az merge, helm), `jsonutil.sh` gained
`json_get_path` (nested `toolCall.args.CommandLine`). `executor.sh` exports `AI_MEMORY_ROLE=$ROLE` before
`exec` (interactive stays unguarded). Manifest gained `exec_readonly` (= same `agy -p`; the guard enforces
read-only) + `guard_script`; the `hook` driver now registers **both** `ai-memory-inject` (PreInvocation)
and `ai-memory-guard` (PreToolUse, matcher `*`). Antigravity is now a real `explore` executor.
**Verified:** suite 27/27 (38 guard/inject assertions in test_antigravity; executor role-export tests);
guard exercised against agy's exact live PreToolUse payload shape — task→deny `terraform apply`,
explore→deny shell, explore→allow `view_file`, interactive→allow. (Full agy round-trip deny was proven in
Phase 0; a live full-session run is slow because the model re-plans after each denial — decision logic is
identical to the unit-covered path.)
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
- ~~**Workspace-trust allowlist**~~ — RESOLVED (live). Global `~/.gemini/config/hooks.json` fires in an
  untrusted workspace; `trustedWorkspaces` does not gate it. No trust registration needed at install.
- ~~**Project resolution for a global hook**~~ — RESOLVED (live). Payload has no workspace handle
  (`workspacePaths=[]`, cwd = config dir) → resolve at launch: `agy.sh` exports `AI_MEMORY_PROJECT`/
  `MEMORY_DIR`, hook inherits + reads them (env inheritance verified).
- ~~**`hooks.json` discovery location**~~ — RESOLVED (Phase 0): global `~/.gemini/config/hooks.json`
  (per-repo `.agents/hooks.json` is the alternative surface, not used for the global install).
- ~~**`ephemeralMessage` persistence**~~ — RESOLVED (live). Reaches the model (codename echoed);
  re-injected every invocation, so transience is moot — no `userMessage` fallback needed.
- **Generalizing the `hook` driver** — how much of Antigravity's JSON contract the driver absorbs vs a
  per-harness override script; decide during Phase 1. (The Claude `hook` driver emits raw-text
  `additionalContext`; Antigravity needs a JSON `injectSteps` envelope + `hooks.json` registration into
  the global config root.)
- Multi-harness `guard` manifest capability is **out of scope** (deferred until a 2nd hook-capable harness).
