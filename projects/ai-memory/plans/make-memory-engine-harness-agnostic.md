---
plan: make-memory-engine-harness-agnostic
status: active
created: 2026-07-01
owner: claude (orchestrator)
task_provider: notion
task_ref: 38ef6850-c619-8103-8fa8-ec66b0cb9115
---

## Goal

Make the memory system installable and operable from **any coding harness**, not just
Claude Code. The centerpiece is an **agent-runnable, harness-agnostic installer**: sit
inside Codex (or Cursor, Gemini, etc.), say "install the memory system," and it wires
*that* harness up — context injection, skills, and commands — in the harness's own idiom,
degrading gracefully where a harness lacks a surface. Today the system silently treats
Claude Code as the default (root-level `claude/` dir, Claude-only hooks/commands, Codex
bolted on via `scripts/codex-mem.sh`); the goal removes that privilege.

> **Status: design approved (2026-07-02) — ready to execute.** All three opens resolved
> (`harnesses/` parent dir · materialized "Memory Commands" doc · `--harness` flag +
> auto-detect). Phases decomposed below. Behavior-preserving refactors (Phase 1–2) land
> before new capability (Phase 3–5); each phase gates on the full test suite staying green.

## Success criteria

- [ ] From inside a non-Claude harness (Codex as the proof case), an agent can run one
      documented command (`install.sh` / `install.sh --harness <name>`) and end up with a
      working memory system for that harness: context injected in the harness's idiom,
      plus whatever skills/commands surfaces that harness supports.
- [ ] Claude Code install remains byte-for-byte equivalent in behavior (existing hook
      output and `test_inject_memory.sh` unchanged / still green).
- [ ] No harness is a root-level peer: Claude, Codex, and any new harness all live under
      `harnesses/<name>/`; `scripts/` holds only shared engine.
- [ ] Content selection (which files, order, full-vs-breadcrumb) exists in exactly one
      place; both Claude XML output and Codex markdown output are produced from it.
- [ ] Adding a new file-materialize harness is a manifest entry (+ optional override
      script only for genuine oddballs), not new engine code.
- [ ] Capability gaps degrade explicitly (skipped + reported), never silently fail —
      e.g. a context-only harness (Aider: conventions file, no skills/command surface).
- [ ] **The endgoal:** the *same folder* opened in Claude and in Codex resolves to the *same
      project* and *same in-flight state* — one harness-neutral marker (`.agents/memory-project`),
      no `.claude/`-branded dependency, so "where we stopped" (working.md/checkpoints) carries across.
- [ ] Executor exposes two roles — `task` (write-capable) and `exploration` (read-only) — each
      selecting a harness and model from `config.local.sh`, with the legacy single var as fallback.
      The selected harness is resolved through its **manifest `exec_*` block** (one registry for
      install *and* execute), not per-harness code in `executor.sh`; a harness without a read-only
      mode is skipped for `exploration`, not silently run write-capable.
- [ ] A single third-party harness (**Antigravity**) is registered once and works as **both** an
      install target (AGENTS.md + skills fanned into `~/.agents/skills`) and a `task`-role executor
      (`agy -p`), with no Claude/Codex-specific code paths — proving the two-face registry.
- [ ] Full test suite green; new golden test pins the Codex/file-materialize output.

## Design

**Chosen approach: C — hybrid (manifest by default, module escape hatch).**
Rejected alternatives:
- **A (pure declarative manifests):** can't express oddball harnesses (Cursor multi-file
  `.cursor/rules/*.mdc`, Gemini TOML commands) without bolt-on escapes.
- **B (per-harness code modules, à la `taskprovider`):** re-duplicates as boilerplate what
  a manifest states in one line; "full multi-harness" becomes N modules even when thin.
- C is the shape the codebase already chose twice (`executor.sh` built-in-types + generic
  escape; `taskprovider` env-value-is-module registry + generic fallback).

**Key enabling insight:** most of the system is *already* harness-agnostic. The bash CLIs
(`taskctl`, `executor.sh`, `regenerate-index.sh`, `lint-memory.sh`, `memory-pin.sh`, …)
run in any shell. Only **three delivery surfaces** are Claude-bound: context injection
(hooks), skills (`~/.claude/skills` symlinks), commands (`~/.claude/commands`). Generalize
those three + the installer and the rest already works.

**Harnesses cluster into two delivery archetypes** (orthogonal to format flavor):
- `hook` — in-band, live per-prompt (Claude: `UserPromptSubmit`/`SessionStart` stdout).
- `file` — materialize markdown to a path the tool auto-reads at launch (Codex AGENTS.md,
  Cursor rules, Gemini GEMINI.md, Aider conventions). One driver + per-harness config
  covers all of them — this is what makes "full multi-harness" tractable. When a `file`
  harness has **no hook to refresh in-band**, its refresh is triggered by a **per-harness
  launch wrapper** that regenerates the materialized context before handing off to the real
  harness command — `codex-mem.sh` is exactly this (wraps `codex`, rebuilds AGENTS.md first).

Format flavor (`xml` `<memory:*>` tags vs `md` `# === X ===` headers) is a **separate**
parameter from archetype.

### Section 1 — Harness-agnostic content core (dedup selection)
One source of "what content, what order, what fidelity," replacing the duplicated walks in
`claude/hooks/memory_common.sh` (`assemble_full_memory`/`assemble_breadcrumb`) and
`scripts/codex-mem.sh`. Emits a **format-neutral ordered list of named sections** + a mode
(`full` | `breadcrumb`): `[{identity}, {project}, {index}, {domain}, {working}]`.
Formatters serialize (`xml` / `md`). Pure refactor — existing outputs must be reproducible;
`test_inject_memory.sh` + a new codex golden test pin it.

### Section 2 — Installer + manifest (the spine)
`install.sh --harness <name>` (auto-detect when omitted: `~/.codex`, `$CURSOR_*`,
`~/.gemini`, …), **agent-runnable from inside any harness** (any agent that runs bash).
Reads a per-harness declarative **manifest**:
```
harnesses/codex/manifest:
  # deliver face (install target)
  archetype      = file        # hook | file
  format         = md          # xml | md
  context_target = ~/.codex/AGENTS.md
  skills_dir     = ~/.agents/skills  # Codex DOES have a skills dir (.agents/skills std) — fan out like Claude
  commands       = skill       # native | skill | doc | none  (Codex: prompts deprecated → commands are skills)
  refresh        = launch
  # execute face (executor runtime) — see Section 8
  exec_cmd       = <headless invocation, {prompt} placeholder>   # e.g. codex exec / agy -p {prompt}
  exec_model_flag = <model flag template>                        # e.g. --model {model}
  exec_readonly  = <read-only headless invocation, optional>     # empty → not an exploration-role executor
```
**A harness manifest declares two capability faces, either or both** (see Section 8):
a **deliver** face (install surfaces — archetype/format/context_target/skills_dir/commands)
and an **execute** face (headless-invocation contract — `exec_*`). Aider is deliver-only;
a bare scriptable CLI could be execute-only; Codex and Antigravity fill both. This is what
makes "register a harness once, use it for install *and* as an executor" true — the executor
selection (Section 8) reads the `exec_*` block from the same manifest instead of `executor.sh`
carrying per-harness knowledge.

Installer = generic engine: manifest → archetype driver (place hook / register
file-materialize) → skills fan-out (if `skills_dir`) → commands surface (per `commands`).
**Per-harness override (`harnesses/<name>/<name>.sh`), two legitimate roles** — the driver
calls it only when present:
1. **Format oddball** — content the generic materializer can't express (Cursor `.mdc` multi-file,
   Gemini TOML commands).
2. **Launch/command wrapper to load the memory system** — when the harness has no native hook,
   the override wraps the harness's own launch command to inject/refresh context before handing
   off. **`codex-mem.sh` is the reference:** it stands in for `codex`, regenerating AGENTS.md
   from the content core on each launch. Overriding the harness command *for the purpose of
   loading the memory system* is explicitly sanctioned, not a workaround.

**Capability degradation is explicit** — missing surface is skipped and reported, not failed.

### Section 3 — Layout restructure (no root-level default harness)
New parent `harnesses/`; every harness is a sibling entry incl. Claude:
```
scripts/                 shared engine ONLY: install.sh, content-core.sh,
                         formatters/{xml,md}, drivers/{hook,file}, and the
                         cross-system CLIs (taskctl, executor.sh, lint-memory.sh,
                         regenerate-*.sh, memory-pin.sh, _lib.sh, …)
harnesses/claude/        manifest, hooks/ (was root claude/hooks/),
                         commands/ (was root claude/commands/), CLAUDE.md,
                         scripts/ (any Claude-only glue)
harnesses/codex/         manifest, AGENTS.md handling, scripts/ (codex-mem.sh +
                         codex-mem-checkpoint.sh move here from scripts/)
harnesses/cursor/        manifest (+ optional cursor.sh override)
harnesses/gemini/        manifest (+ optional gemini.sh override)
```
**Placement rule (locked):** `scripts/` holds **only** scripts used across the whole
system. A script that serves **one harness** lives under that harness's own
`harnesses/<name>/scripts/`, never in the shared `scripts/`. Concretely: `codex-mem.sh` and
`codex-mem-checkpoint.sh` → `harnesses/codex/scripts/`; root `claude/` → `harnesses/claude/`.
For the generalized linkers (`link-skills.sh`/`link-commands.sh`/`link-agents.sh`): the
generic fan-out engine stays shared (it reads each manifest); only a genuinely Claude-idiom
remainder, if any survives generalization, moves under `harnesses/claude/`.
The **override entry point** is the conventional `harnesses/<name>/<name>.sh` (e.g.
`harnesses/codex/codex.sh` — the launch wrapper the engine invokes); it may delegate to helper
scripts under that harness's `scripts/` (so `codex.sh` calls `harnesses/codex/scripts/codex-mem.sh`).

### Section 4 — Skills fan-out (generalize `link-skills.sh`)
Canonical store `skills/<name>/` stays. `link-skills.sh` is Claude-pathed today; generalize
to fan into each enabled harness's `skills_dir` from the manifest — Claude (`~/.claude/skills`)
**and Codex (`~/.agents/skills`, the cross-agent `.agents/skills` standard)** both fan out. Our
canonical `skills/<name>/SKILL.md` already matches the format Codex expects. Only a harness with
genuinely no skills dir → step skipped + reported.

### Section 5 — Commands surface
Slash-command `.md` bodies are already just agent prompts ("run this bash, parse, report").
Per-harness `commands` capability:
- `native` — symlink into the harness's native command dir (Claude `~/.claude/commands`).
- `skill` — deliver each command `.md` as a **skill** into `skills_dir` (Codex: prompts are
  deprecated; **skills ARE the custom-command mechanism**, so a command *is* a skill — commands
  and skills unify into the one `.agents/skills` surface).
- `doc` — materialize a **"Memory Commands" reference doc** into the injected context; fallback
  for a harness with neither a native command dir nor a skills surface.
- `none` — nothing.

Consequence: on a `skill`-command harness, the commands step and the skills fan-out target the
same `skills_dir`. Our command `.md` bodies need a thin `SKILL.md` wrapper (name/description
frontmatter) to be skill-shaped — a mechanical transform, generated at install.

### Section 6 — Migration, tests, non-goal reversal
- `memory_common.sh` self-locates `MEMORY_DIR` as "two levels up from the symlinked hook";
  `harnesses/claude/hooks/` is now *three* up — resolver + its test change.
- `.gitignore` tracked-path carve-outs name `claude/` explicitly → move to `harnesses/`.
- Consciously **reverses** the current `non-goals: no bootstrap script` decision — the
  installer *becomes* the agent-runnable bootstrap; README demoted to backup.
- New golden test for file-materialize output; full suite stays green.

### Section 7 — Harness-agnostic project identity (de-brand the marker)
The forward marker that binds a checkout to a project is Claude-branded: **`.claude/memory-project`**.
Codex (and every other harness) has no reason to read `.claude/`, so the same folder opened in a
different harness resolves to *no project* — breaking the endgoal (open a folder in Claude, reopen it
in Codex, and it knows where we stopped). Fix: **move the marker out of `.claude/` to the neutral,
cross-agent `.agents/` namespace** — the same directory already adopted for skills (`.agents/skills`,
`~/.agents/.skill-lock.json`).

- **Marker path:** `.claude/memory-project` → **`.agents/memory-project`**. Same content (the project
  slug), same walk-up-from-cwd detection, same bidirectional design — only the path de-brands.
- **Mechanism unchanged:** the reverse map (`repo`/`repo_path` frontmatter + `resolve_repo_path`) and
  the per-prompt "walk up for the marker; no marker → dormant, no global fallback" rule stay exactly
  as they are. This is a *rename + read-path*, not a redesign.
- **All adapters read the one neutral file:** the Claude hook and the Codex adapter both look for
  `.agents/memory-project`, so both land on the same project slug → the same `working.md`/checkpoints.
- **Transitional back-compat:** adapters read `.agents/memory-project` first, fall back to the legacy
  `.claude/memory-project` with a one-line deprecation warning; the fallback is removed once existing
  pins are migrated.
- **Out of scope (stays in task `385f6850`):** multi-session/worktree concurrency and a per-branch
  `working.md` overlay are *not* part of this — they remain that separate backlog item.

### Section 8 — Executor roles (task / exploration) + harness:model config
Today there is one executor (`AI_MEMORY_EXECUTOR`, default `claude-subagent`), resolved by
`executor.sh --which` → `subagent` | `cli:<key>`; model is implicit, harness baked into the key.
Split it into **two independently-configurable roles**, each selecting a **harness and model**:

| Role | Purpose | Write posture | Maps to today |
|------|---------|---------------|---------------|
| **task** | Execute self-contained instructions (a plan step) | write-capable, within the deny-list | current executor / `codex --executor` / claude subagent |
| **exploration** | Scout files/repo, search, read-only investigation | **read-only** | claude `Explore` agent / `codex-mem.sh --executor-bare` |

- **Config (gitignored `config.local.sh`, per "instance config never in tracked memory"):**
  `AI_MEMORY_EXECUTOR_TASK` and `AI_MEMORY_EXECUTOR_EXPLORE`, each a `harness[:model]` value
  (`claude:sonnet`, `claude:haiku`, `codex:<model>`, `antigravity:<model>`, `cli:<key>`). Documented
  in `config.local.sh.example`.
- **The env var stays the control surface; the manifest registry is what makes a value resolvable.**
  Setting `AI_MEMORY_EXECUTOR_TASK=codex` (or `antigravity`, `claude`, …) still selects the executor
  exactly as today — but the named `harness` must be a **registered harness**: `harnesses/<name>/manifest`
  exists and declares an **execute face** (`exec_cmd`). Resolution = look the name up in the registry and
  read its `exec_*` block. `codex` works as an executor *because* `harnesses/codex/manifest` registered it,
  not because `executor.sh` hardcodes it (the `executor.sh:38,55` special-case is deleted). An env value
  naming an **unregistered** harness — or one whose manifest has no execute face — is a resolution error:
  reported, then the configured fallback (`AI_MEMORY_EXECUTOR_FALLBACK`, then the legacy
  `AI_MEMORY_EXECUTOR_CMD_<key>` template) applies. So "register the harness" is the precondition for
  "name it in the env var."
- **Harness** = which runtime runs it (claude-subagent / codex / generic CLI) — and once the
  manifest registry (Section 2–3) exists, `harness` can name **any registered harness**, resolved
  through that harness's **`exec_*` manifest block** (not per-harness code in `executor.sh`).
  `executor.sh`'s current codex special-case (`executor.sh:38,55`) and the ad-hoc
  `AI_MEMORY_EXECUTOR_CMD_<key>` templates collapse into reading `exec_cmd` / `exec_model_flag`
  from the manifest — the same registry that drives install. **Model** = explicit per role (new;
  today implicit), threaded via `exec_model_flag`.
- **Read-only is an optional capability, not a guarantee.** The `exploration` role needs a
  read-only headless mode (`exec_readonly`). A harness that lacks one (e.g. **Antigravity** —
  `agy -p` is write-capable with `--dangerously-skip-permissions`, no clean `--read-only`) is
  simply **not offered for the `exploration` role**; it stays a valid `task`-role executor, and
  exploration degrades to the Claude `Explore` agent. Missing `exec_readonly` → skipped +
  reported, never a silent write-capable stand-in for a read-only role.
- **Backward compatible:** existing single `AI_MEMORY_EXECUTOR` remains the fallback for any role
  left unset — no breakage for current configs.
- **`executor.sh` grows `--role task|explore`**; `--which`/`--run` resolve per role. The
  **Validator keeps resolving through the `task` role** (a fresh, separate invocation — independence
  unchanged). The orchestrator picks the role by task nature: read-only investigation → `explore`
  (cheap model, read-only — matches "delegate token-heavy fetches to subagents"); execute a step → `task`.
- **Relation to this plan:** the role split + model config can ship on today's `executor.sh`
  independently; only the "harness = any installed harness" richness leans on the harness registry.
  Folded here because that's the natural convergence point.

## Decisions (locked)
- Approach **C** (hybrid: manifest default + optional per-harness override script). The override
  has **two sanctioned roles**: (a) format oddballs the generic materializer can't express, and
  (b) **wrapping the harness's own launch/command to load the memory system** when the harness
  lacks a native hook (`codex-mem.sh` wraps `codex` + rebuilds AGENTS.md). Overriding the harness
  command *to load memory* is allowed by design, not a hack.
- Two delivery archetypes (`hook`, `file`); format flavor (`xml`/`md`) is orthogonal.
- Single shared content core; both existing outputs derive from it.
- No root-level default harness; all under `harnesses/<name>/`.
- **`scripts/` = cross-system shared engine ONLY.** Harness-specific scripts live under that
  harness's `harnesses/<name>/scripts/`, never in shared `scripts/` (e.g. `codex-mem.sh`,
  `codex-mem-checkpoint.sh` → `harnesses/codex/scripts/`).
- Scope: **full multi-harness**, surface = **everything** the harness supports
  (context + skills + commands), designed to a **generic file-materialize** archetype.
- Parent dir is **`harnesses/`** (mirrors `docs/harnesses/<name>.md`).
- Commands surface has **four** capabilities: `native` (symlink to the harness's command dir —
  Claude), `skill` (deliver command `.md` bodies as skills into `skills_dir` — **Codex**, whose
  prompts are deprecated and whose skills ARE the command mechanism), `doc` (materialized "Memory
  Commands" reference doc — fallback for harnesses with neither), `none`. On a `skill` harness,
  commands and skills unify into the one `.agents/skills` surface.
- Harness selection → **`install.sh --harness <name>` explicit, with environment auto-detect
  fallback** when the flag is omitted (probe `~/.codex`, `$CURSOR_*`, `~/.gemini`, `~/.claude`).
- **Project marker is harness-neutral:** `.claude/memory-project` → **`.agents/memory-project`** (same
  walk-up + reverse-map mechanism, de-branded so every harness reads the one file). Marker-path move
  only — multi-session/worktree work stays in task `385f6850`.
- **Two executor roles, each harness:model-configurable.** `task` (execute self-contained steps,
  write-capable) and `exploration` (read-only scouting) resolve from separate `config.local.sh` vars
  (`AI_MEMORY_EXECUTOR_TASK`/`_EXPLORE`, `harness[:model]`); single `AI_MEMORY_EXECUTOR` is the
  fallback. Validator stays on the `task` role as a fresh invocation.
- **One registry, two faces.** A harness manifest declares a **deliver** face (install surfaces)
  and/or an **execute** face (`exec_cmd`/`exec_model_flag`/`exec_readonly`). Executor selection
  (Section 8) resolves the chosen harness through its manifest `exec_*` block — `executor.sh` stops
  carrying per-harness knowledge (codex special-case + `AI_MEMORY_EXECUTOR_CMD_*` collapse into
  manifest reads). **The env var (`AI_MEMORY_EXECUTOR*`) remains the control surface; its value must
  name a *registered* harness (manifest with an execute face).** `codex`/`antigravity` are selectable
  as executors *because they are registered*, not built in. An unregistered/execute-less name → reported
  resolution error, then fallback. Registration is the precondition for naming a harness in the env var. Faces are independent: deliver-only (Aider), execute-only (bare CLI), or both
  (Codex, Antigravity). **Read-only (`exec_readonly`) is optional** — a harness lacking it is not
  offered for the `exploration` role (degrade to Claude `Explore`), never silently run write-capable.
- **Antigravity is the Phase 5 proof harness** (replaces the tentative Gemini/Cursor headline).
  Facts (CLI v1.0.16, `agy` at `~/.local/bin/agy`): headless `agy -p {prompt}` (+ `--model`,
  `--dangerously-skip-permissions`); context via `AGENTS.md`/`GEMINI.md` at launch (`file` archetype,
  `agy.sh` launch-wrapper mirrors `codex-mem.sh`); skills as `skills/<name>/SKILL.md` (byte-identical
  to our store, zero-transform); `commands=skill`. **Natively discovers `.agents/` walking up to the
  repo root** — so it picks up the Phase 6 neutral marker (`.agents/memory-project`) and `.agents/skills`
  with no adapter, validating the `.agents/` namespace bet against a real third-party harness. Chosen
  over Cursor as headline because it exercises **both** faces at once; Cursor stays the `.mdc` override
  example.

## Risks / open questions
_All three design opens resolved 2026-07-02 — see Decisions (locked)._

**Risks / to resolve during design or phasing:**
- **Codex capability surface is richer than the design assumed (found 2026-07-03).** Codex has a
  **skills dir** — the documented **`.agents/skills`** standard (user `~/.agents/skills`, repo
  `.agents/skills`, system `/etc/codex/skills`; ref https://developers.openai.com/codex/skills),
  registry at `~/.agents/.skill-lock.json` — now wired as `skills_dir`, so Codex is no longer a
  degradation example. Its skill layout (`SKILL.md` + `name`/`description` frontmatter) matches our
  canonical store, so fan-out is a symlink, no transform. **`.agents/skills` is cross-agent** (the
  lock lists codex/cursor/gemini-cli/amp/…), so one fan-out target may serve several file-harnesses —
  worth modeling as a shared skills_dir rather than per-harness. Degradation example moved to a
  context-only harness (Aider). **Commands on Codex → resolved:** Codex `~/.codex/prompts/*.md` are
  **deprecated**; skills ARE the custom-command mechanism, so Codex uses the new `commands=skill`
  value (deliver command `.md` bodies as skills into `skills_dir`), not `doc` and not prompts. On
  Codex, commands and skills therefore unify into the one `.agents/skills` surface — see Section 5
  and Decisions (locked).
- Auto-detection reliability across harnesses (env signals differ; may need per-harness probe).
- Skills/commands mapping for harnesses with genuinely different models (Cursor scoped rules,
  Gemini TOML) — how much the override escape hatch must carry.
- Executor/Validator roles lean on the Claude `Agent` tool — on other harnesses these degrade
  to "codex-as-executor" / no in-harness subagent; clarify what "the system" guarantees per harness.
- `MEMORY_DIR` resolution depth change must not break existing installs mid-migration.
- **Antigravity read-only is deferred, not absent.** `agy -p` has no read-only *flag*
  (`--dangerously-skip-permissions` auto-approves; `--sandbox` restricts the terminal, not file writes) —
  **but its `hooks.json` `PreToolUse` gate can enforce read-only** by returning `{"decision":"deny"}` on
  write tools before they run (stronger than prompt-level; on par with codex execpolicy). The gate reads
  `toolCall.name` + `args.CommandLine` from stdin, so it can allow reads and deny writes incl. mutating
  `run_command`s via a denylist. **Baseline (Phase 5): `exec_readonly` empty → exploration degrades to
  Claude `Explore`.** **Upgrade (deferred): an env-gated `PreToolUse` read-only guard** (one `hooks.json`,
  enforce iff `AI_MEMORY_ROLE=explore`; inert for `task`). **Dependency risk:** the guard needs
  Antigravity's full write-tool catalog (only `run_command`/`view_file`/`browser_*` known from docs) +
  the command-mutation denylist — probe `agy`'s tool set before writing it. See "Deny-list enforcement" below.
- **Antigravity supports a `hook` archetype (live refresh), not only `file`.** `hooks.json` `PreInvocation`
  fires before each model call and returns `injectSteps` (`ephemeralMessage`/`userMessage`) — genuine
  in-band injection like Claude. Nuance: it fires **every** invocation, so gate on `invocationNum == 1`
  (in the payload) for session-start semantics. AGENTS.md (persistent rules) + `PreInvocation` (live
  working.md/checkpoint refresh) can combine. **Baseline (Phase 5): `file` archetype (AGENTS.md +
  `agy.sh` launch wrapper, mirrors codex) — simplest proof.** **Upgrade (deferred): `hook` via
  `PreInvocation`** — the Phase 3 `hook` driver later covers Antigravity too (differs from Claude only in
  I/O shape: JSON stdin → `injectSteps` vs stdout text). Do not block the proof on it.
- **Deny-list enforcement via `PreToolUse` (bigger than one harness).** The same gate that yields read-only
  can enforce the **entire O/E/V deny-list** (`terraform apply`, `kubectl apply`, `gh pr merge`, …) at the
  tool boundary for the `task` role — today that list is only *restated in prompts* and only truly enforced
  for codex (execpolicy). Antigravity would be the **second executor with enforced guardrails**, and more
  flexible (arbitrary shell guard + command-line inspection). Reframes "read-only exploration" as one case
  of a general **tool-gating capability** the manifest could expose (e.g. a `guard` field). Captured as a
  cross-project insight in `working.md`; a manifest `guard` capability is a candidate follow-up, out of
  scope for this plan's core.

## Phases

Ordered so **behavior-preserving refactors (1–2) land before new capability (3–5)**. Every
phase gates on `scripts/run-tests.sh` staying green; phases 1–2 additionally require the
Claude hook output to be **byte-identical** to today (they touch the live injection path).

### Phase 1 — Content core extraction (pure refactor, no behavior change) — ✅ DONE 2026-07-05
- [x] Add `scripts/content-core.sh`: single source of content selection → a format-neutral
      ordered section list (`identity, project, index, domain, working`). `content_sections <project>
      [kind...]` emits tab-separated `kind\tpath\tname` records, presence-gated, in canonical order;
      the kind filter is how each consumer selects its subset (mode = the consumer's kind set +
      full-vs-breadcrumb renderer, not a core param).
- [x] Add formatters `scripts/formatters/xml.sh` (`xml_render_full` / `xml_render_breadcrumb`) and
      `scripts/formatters/md.sh` (`md_render` + `_md_render_domain` table).
- [x] Rewire `memory_common.sh` (Claude → content-core + xml; sources the engine from the resolved
      **repo root**, not `MEMORY_DIR`, so the test-overridden content tree still finds the code) and
      `codex-mem.sh` (→ content-core + md; overlay/header framing stays codex-specific). Duplicated
      selection walks deleted.
- [x] Golden tests: `test_inject_memory.sh` unchanged/green; **new** `test_codex_agents_golden.sh`
      pins the AGENTS.md build byte-for-byte against `tests/fixtures/codex_agents.golden`.
- **Gate:** ✅ met — pre/post-refactor outputs diffed **byte-identical** (codex AGENTS.md, Claude
      full, Claude breadcrumb); suite **22/22 green**; live symlinked hook verified.

### Phase 2 — Layout restructure (move, no logic change)
- [ ] Create `harnesses/`; move `claude/` → `harnesses/claude/` (hooks, commands, CLAUDE.md,
      statusline.sh, settings.hooks.json) and the Codex assets (`codex-mem.sh` +
      `codex-mem-checkpoint.sh` + AGENTS handling) → `harnesses/codex/scripts/`.
- [ ] **Audit `scripts/` against the placement rule** (shared-only): relocate any harness-specific
      script to `harnesses/<name>/scripts/`. Known movers: `codex-mem.sh`, `codex-mem-checkpoint.sh`
      → `harnesses/codex/scripts/`. Update every caller/path ref (`sync-system.sh`, `codex-mem*`
      cross-refs, `run-tests.sh` discovery, docs).
- [ ] Fix `memory_common.sh` `MEMORY_DIR` self-location (symlink parent is now **three** levels up,
      not two) + its test.
- [ ] Update `.gitignore` tracked-path carve-outs (`claude/` → `harnesses/`), `install.sh` symlink
      sources, `link-skills.sh`/`link-agents.sh`, and the docs paths (`docs/install.md`, `docs/harnesses/*`).
- **Gate:** full suite green after the move; a clean `install.sh` still wires Claude + Codex identically.

### Phase 3 — Manifest + archetype drivers + installer engine
- [ ] Define the manifest schema with **two capability faces**: **deliver** (`archetype`, `format`,
      `context_target`, `skills_dir`, `commands`, `refresh`) and **execute** (`exec_cmd`,
      `exec_model_flag`, `exec_readonly` — all optional; absent execute block = deliver-only harness).
- [ ] Author `harnesses/claude/manifest` (`archetype=hook, format=xml, commands=native,
      skills_dir=~/.claude/skills`; execute face = subagent, resolved in-harness) and
      `harnesses/codex/manifest` (`archetype=file, format=md, context_target=~/.codex/AGENTS.md,
      commands=skill, skills_dir=~/.agents/skills`; `exec_cmd=codex exec …`).
- [ ] Implement `scripts/drivers/hook.sh` and `scripts/drivers/file.sh` (the two archetypes).
- [ ] Rewrite `install.sh` as the generic engine: resolve harness (`--harness` flag → else
      auto-detect) → read manifest → run archetype driver → skills fan-out → commands surface.
      Optional per-harness `harnesses/<name>/<name>.sh` override, called only when present.
- [ ] `validate-manifest.sh` static check + `test_install_harness.sh` (claude & codex reproduce
      today's wiring from their manifests; auto-detect resolves correctly).
- **Gate:** `install.sh --harness claude` and `--harness codex` reproduce the pre-Phase-3 wiring.

### Phase 4 — Skills & commands generalization
- [ ] Generalize `link-skills.sh` to fan into each harness's manifest `skills_dir` (Claude
      `~/.claude/skills` **and** Codex `~/.agents/skills`); **skip + report** only when a harness
      declares no skills dir.
- [ ] Implement the commands surface per manifest: `native` (symlink), `skill` (wrap each command
      `.md` in a thin `SKILL.md` and fan into `skills_dir` — Codex), `doc` (materialize the "Memory
      Commands" reference via content-core into the injected context), `none`.
- **Gate:** skills fan-out works on a skills-capable harness; Codex install emits the commands doc;
      capability gaps are reported, never silent failures.

### Phase 5 — Prove multi-harness + agent-runnable install; docs & non-goal reversal
- [ ] **Register Antigravity** (`agy` v1.0.16) as the headline third-party proof harness —
      `harnesses/antigravity/manifest` with **both faces**: deliver (`archetype=file, format=md,
      context_target` → `AGENTS.md`, `skills_dir=~/.agents/skills`, `commands=skill`, `refresh=launch`
      via a `harnesses/antigravity/agy.sh` wrapper mirroring `codex-mem.sh`) and execute
      (`exec_cmd=agy -p {prompt} --dangerously-skip-permissions`, `exec_model_flag=--model {model}`,
      `exec_readonly=` empty → task-role only). Its skills are `skills/<name>/SKILL.md` (zero-transform).
- [ ] Prove **the executor face**: set `AI_MEMORY_EXECUTOR_TASK=antigravity[:model]` and confirm a
      delegated `task` step runs through `agy -p` resolved **from the manifest** (no `executor.sh`
      special-case); confirm `exploration` correctly refuses Antigravity and degrades to Claude `Explore`.
- [ ] Confirm the **`.agents/` native-discovery** payoff: with Antigravity, the Phase 6 marker
      (`.agents/memory-project`) and `.agents/skills` are picked up with no adapter.
- [ ] **Baseline only for the proof** (`file` archetype + `agy.sh` wrapper; `exec_readonly` empty →
      Explore). Record — but do **not** build here — the `hooks.json` upgrades: env-gated `PreToolUse`
      read-only guard, `PreInvocation` live refresh (`hook` archetype), and `PreToolUse` deny-list
      enforcement (see Risks + `working.md`). Building any requires probing `agy`'s full tool catalog first.
- [ ] (Optional, config-only) add **Cursor** (`.cursor/rules/*.mdc`) as the override-script example,
      proving the escape hatch — not the headline.
- [ ] Validate the agent-runnable path: from **inside Codex**, an agent runs `install.sh` and gets a working
      setup (context injected via AGENTS.md + skills and commands-as-skills fanned into `~/.agents/skills`).
- [ ] Docs: rewrite `docs/install.md` + `docs/harnesses/*` to the manifest model; add an
      "adding a harness" guide; **reverse the `no bootstrap script` non-goal** in `memory.md`
      (the installer is now the agent-runnable bootstrap).
- **Gate:** the top success criterion (install from a non-Claude harness) demonstrably works end-to-end.

### Phase 6 — Harness-agnostic project marker (`.claude/memory-project` → `.agents/memory-project`)
- [ ] Move the marker path in every reader/writer: the Claude hook detection (`memory_common.sh` /
      `inject_memory.sh` walk-up), `memory-pin.sh` (writes the marker), `lint-memory.sh` (back-pin
      check), and the Codex adapter (`codex-mem.sh`) so it resolves the project from the same file.
- [ ] Add transitional back-compat: read `.agents/memory-project` first, fall back to legacy
      `.claude/memory-project` with a deprecation warning.
- [ ] Migrate existing pins: one-off sweep of pinned checkouts (`.claude/memory-project` →
      `.agents/memory-project`); update `/pin` docs and any `.gitignore`/marker references.
- [ ] Tests: `test_memory_pin.sh`, `test_inject_memory.sh`, marker back-pin lint case updated to the
      neutral path (+ a fallback-read case).
- **Gate:** same folder resolves to the same project slug from **both** Claude and Codex; full suite
      green. (Multi-session/worktree + branch-overlay `working.md` remain out of scope — task `385f6850`.)

### Phase 7 — Executor roles (task / exploration) + harness:model config
- [ ] Extend `executor.sh` with `--role task|explore`; resolve each from `AI_MEMORY_EXECUTOR_TASK` /
      `AI_MEMORY_EXECUTOR_EXPLORE` (`harness[:model]`), falling back to the legacy `AI_MEMORY_EXECUTOR`.
      Parse `harness[:model]`; thread `model` into the invocation via the harness's `exec_model_flag`.
- [ ] **Resolve the invocation from the manifest `exec_*` block**, not per-harness code: the env-var
      value names a harness; look it up in the registry and read its `exec_*` (`exec_cmd` for `task`,
      `exec_readonly` for `explore`). Replace the codex special-case (`executor.sh:38,55`) — `codex`
      resolves only because `harnesses/codex/manifest` registered it. `claude-subagent` stays the
      in-harness plane (Agent tool). An env value naming an **unregistered** harness (or one with no
      execute face) → reported resolution error, then fallback (`AI_MEMORY_EXECUTOR_FALLBACK`, then a
      legacy `AI_MEMORY_EXECUTOR_CMD_<key>` template if set).
- [ ] `exploration` role is **read-only** — a harness with a non-empty `exec_readonly` (claude `Explore`
      / `codex-mem.sh --executor-bare`); a harness without one (e.g. Antigravity) is **skipped for
      `explore` + reported**, degrading to Claude `Explore`. `task` role stays write-capable within the
      deny-list.
- [ ] Validator resolves through the `task` role (fresh invocation) — update the workflow docs
      (`identity.md` / `CLAUDE.md` O/E/V section) to name the two roles.
- [ ] `config.local.sh.example` documents both vars; `test_executor.sh` covers role resolution,
      `harness[:model]` parsing, **manifest `exec_*` resolution** (registered name resolves; the
      read-only-absent skip; an **unregistered / execute-less name errors then falls back**),
      read-only exploration posture, and fallback to the legacy var / `AI_MEMORY_EXECUTOR_CMD_*`.
- **Gate:** both roles resolve and run with the configured harness+model; legacy single-var configs
      still work unchanged; full suite green.
