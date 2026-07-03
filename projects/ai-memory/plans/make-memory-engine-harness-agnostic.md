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
  archetype      = file        # hook | file
  format         = md          # xml | md
  context_target = ~/.codex/AGENTS.md
  skills_dir     = ~/.agents/skills  # Codex DOES have a skills dir (.agents/skills std) — fan out like Claude
  commands       = skill       # native | skill | doc | none  (Codex: prompts deprecated → commands are skills)
  refresh        = launch
```
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
  (`claude:sonnet`, `claude:haiku`, `codex:<model>`, `cli:<key>`). Documented in
  `config.local.sh.example`.
- **Harness** = which runtime runs it (claude-subagent / codex / generic CLI) — and once the
  manifest registry (Section 2–3) exists, `harness` can name **any installed harness**. **Model**
  = explicit per role (new; today implicit).
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

## Phases

Ordered so **behavior-preserving refactors (1–2) land before new capability (3–5)**. Every
phase gates on `scripts/run-tests.sh` staying green; phases 1–2 additionally require the
Claude hook output to be **byte-identical** to today (they touch the live injection path).

### Phase 1 — Content core extraction (pure refactor, no behavior change)
- [ ] Add `scripts/content-core.sh`: single source of content selection → a format-neutral
      ordered section list (`identity, project, index, domain, working`) + mode (`full` | `breadcrumb`).
- [ ] Add formatters `scripts/formatters/xml.sh` (`<memory:*>` tags) and `scripts/formatters/md.sh`
      (`# === X ===` headers + domain table).
- [ ] Rewire `memory_common.sh` (Claude) → content-core + xml; rewire `codex-mem.sh` → content-core + md.
      Delete the duplicated selection walks.
- [ ] Golden tests: `test_inject_memory.sh` unchanged/green; **new** `test_codex_agents_golden.sh`
      pins the AGENTS.md build byte-for-byte.
- **Gate:** both existing outputs byte-reproducible from the core; full suite green.

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
- [ ] Define the manifest schema; author `harnesses/claude/manifest` (`archetype=hook, format=xml,
      commands=native, skills_dir=~/.claude/skills`) and `harnesses/codex/manifest`
      (`archetype=file, format=md, context_target=~/.codex/AGENTS.md, commands=skill, skills_dir=~/.agents/skills`).
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
- [ ] Add a new file-materialize harness by config alone where possible — **Gemini CLI**
      (`harnesses/gemini/manifest` → `GEMINI.md`) and/or **Cursor** (`.cursor/rules/*.mdc`, using the
      override script for its multi-file model) — proving the archetype generalizes past Codex.
- [ ] Validate the headline path: from **inside Codex**, an agent runs `install.sh` and gets a working
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
      Parse `harness[:model]`; thread `model` into subagent/codex/CLI invocation.
- [ ] `exploration` role is **read-only** — claude `Explore` agent type (or `codex-mem.sh
      --executor-bare`); `task` role stays write-capable within the deny-list.
- [ ] Validator resolves through the `task` role (fresh invocation) — update the workflow docs
      (`identity.md` / `CLAUDE.md` O/E/V section) to name the two roles.
- [ ] `config.local.sh.example` documents both vars; `test_executor.sh` covers role resolution,
      `harness[:model]` parsing, read-only exploration posture, and fallback to the legacy var.
- **Gate:** both roles resolve and run with the configured harness+model; legacy single-var configs
      still work unchanged; full suite green.
