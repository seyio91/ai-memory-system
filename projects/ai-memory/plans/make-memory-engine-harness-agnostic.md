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
      e.g. Codex has no skills dir.
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
  covers all of them — this is what makes "full multi-harness" tractable.

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
  skills_dir     = (none)      # skills step skipped + reported
  commands       = doc         # native | doc | none
  refresh        = launch
```
Installer = generic engine: manifest → archetype driver (place hook / register
file-materialize) → skills fan-out (if `skills_dir`) → commands surface (per `commands`).
**Oddball escape:** optional `harnesses/<name>/<name>.sh` override hooks the driver calls
only when present (Cursor `.mdc` multi-file, Gemini TOML commands).
**Capability degradation is explicit** — missing surface is skipped and reported, not failed.

### Section 3 — Layout restructure (no root-level default harness)
New parent `harnesses/`; every harness is a sibling entry incl. Claude:
```
scripts/                 shared engine: install.sh, content-core.sh,
                         formatters/{xml,md}, drivers/{hook,file}, (existing CLIs)
harnesses/claude/        manifest, hooks/ (was root claude/hooks/),
                         commands/ (was root claude/commands/), CLAUDE.md
harnesses/codex/         manifest, AGENTS.md handling (absorbs scripts/codex-mem.sh)
harnesses/cursor/        manifest (+ optional cursor.sh override)
harnesses/gemini/        manifest (+ optional gemini.sh override)
```
Root `claude/` and `scripts/codex-mem.sh` both collapse into `harnesses/<name>/`.

### Section 4 — Skills fan-out (generalize `link-skills.sh`)
Canonical store `skills/<name>/` stays. `link-skills.sh` is Claude-pathed today; generalize
to fan into each enabled harness's `skills_dir` from the manifest. Harnesses without a skills
dir (Codex) → step skipped + reported.

### Section 5 — Commands surface
Slash-command `.md` bodies are already just agent prompts ("run this bash, parse, report").
Per-harness `commands` capability:
- `native` — symlink into the harness's command dir (Claude).
- `doc` — materialize a **"Memory Commands" reference doc** into the injected context so
  `/task`→"run `taskctl …`" stays discoverable on no-slash-command harnesses (Codex).
- `none` — nothing.

### Section 6 — Migration, tests, non-goal reversal
- `memory_common.sh` self-locates `MEMORY_DIR` as "two levels up from the symlinked hook";
  `harnesses/claude/hooks/` is now *three* up — resolver + its test change.
- `.gitignore` tracked-path carve-outs name `claude/` explicitly → move to `harnesses/`.
- Consciously **reverses** the current `non-goals: no bootstrap script` decision — the
  installer *becomes* the agent-runnable bootstrap; README demoted to backup.
- New golden test for file-materialize output; full suite stays green.

## Decisions (locked)
- Approach **C** (hybrid: manifest default + optional per-harness override script).
- Two delivery archetypes (`hook`, `file`); format flavor (`xml`/`md`) is orthogonal.
- Single shared content core; both existing outputs derive from it.
- No root-level default harness; all under `harnesses/<name>/`.
- Scope: **full multi-harness**, surface = **everything** the harness supports
  (context + skills + commands), designed to a **generic file-materialize** archetype.
- Parent dir is **`harnesses/`** (mirrors `docs/harnesses/<name>.md`).
- Commands on no-slash-command harnesses → a **materialized "Memory Commands" reference doc**
  folded into the injected context (reuses the command `.md` bodies, already agent prompts).
- Harness selection → **`install.sh --harness <name>` explicit, with environment auto-detect
  fallback** when the flag is omitted (probe `~/.codex`, `$CURSOR_*`, `~/.gemini`, `~/.claude`).

## Risks / open questions
_All three design opens resolved 2026-07-02 — see Decisions (locked)._

**Risks / to resolve during design or phasing:**
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
      statusline.sh, settings.hooks.json) and the Codex assets (`codex-mem.sh` + AGENTS handling)
      → `harnesses/codex/`.
- [ ] Fix `memory_common.sh` `MEMORY_DIR` self-location (symlink parent is now **three** levels up,
      not two) + its test.
- [ ] Update `.gitignore` tracked-path carve-outs (`claude/` → `harnesses/`), `install.sh` symlink
      sources, `link-skills.sh`/`link-agents.sh`, and the docs paths (`docs/install.md`, `docs/harnesses/*`).
- **Gate:** full suite green after the move; a clean `install.sh` still wires Claude + Codex identically.

### Phase 3 — Manifest + archetype drivers + installer engine
- [ ] Define the manifest schema; author `harnesses/claude/manifest` (`archetype=hook, format=xml,
      commands=native, skills_dir=~/.claude/skills`) and `harnesses/codex/manifest`
      (`archetype=file, format=md, context_target=~/.codex/AGENTS.md, commands=doc, skills_dir=none`).
- [ ] Implement `scripts/drivers/hook.sh` and `scripts/drivers/file.sh` (the two archetypes).
- [ ] Rewrite `install.sh` as the generic engine: resolve harness (`--harness` flag → else
      auto-detect) → read manifest → run archetype driver → skills fan-out → commands surface.
      Optional per-harness `harnesses/<name>/<name>.sh` override, called only when present.
- [ ] `validate-manifest.sh` static check + `test_install_harness.sh` (claude & codex reproduce
      today's wiring from their manifests; auto-detect resolves correctly).
- **Gate:** `install.sh --harness claude` and `--harness codex` reproduce the pre-Phase-3 wiring.

### Phase 4 — Skills & commands generalization
- [ ] Generalize `link-skills.sh` to fan into each harness's manifest `skills_dir`; **skip + report**
      when `none` (Codex).
- [ ] Implement the commands surface per manifest: `native` (symlink), `doc` (materialize the
      "Memory Commands" reference via content-core into the injected context), `none`.
- **Gate:** skills fan-out works on a skills-capable harness; Codex install emits the commands doc;
      capability gaps are reported, never silent failures.

### Phase 5 — Prove multi-harness + agent-runnable install; docs & non-goal reversal
- [ ] Add a new file-materialize harness by config alone where possible — **Gemini CLI**
      (`harnesses/gemini/manifest` → `GEMINI.md`) and/or **Cursor** (`.cursor/rules/*.mdc`, using the
      override script for its multi-file model) — proving the archetype generalizes past Codex.
- [ ] Validate the headline path: from **inside Codex**, an agent runs `install.sh` and gets a working
      setup (context + the commands doc; skills skipped-and-reported).
- [ ] Docs: rewrite `docs/install.md` + `docs/harnesses/*` to the manifest model; add an
      "adding a harness" guide; **reverse the `no bootstrap script` non-goal** in `memory.md`
      (the installer is now the agent-runnable bootstrap).
- **Gate:** the top success criterion (install from a non-Claude harness) demonstrably works end-to-end.
