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

> **Status: brainstorm in progress — design ~80% settled, NOT yet approved.** Saved to
> resume the design pass. Three opens pending confirmation (see Open Questions). Do not
> begin execution until the design is approved and Phases are filled in.

## Success criteria

_(draft — finalize with user before execution)_
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

## Risks / open questions
**Opens pending user confirmation (resume here):**
1. Parent dir name — proposed `harnesses/` (vs `adapters/`).
2. Commands on no-slash-command harnesses — proposed **materialized reference doc** (vs
   rely on agent knowing CLIs exist).
3. Harness selection — proposed **`--harness` flag + auto-detect fallback** (vs auto only).

**Risks / to resolve during design or phasing:**
- Auto-detection reliability across harnesses (env signals differ; may need per-harness probe).
- Skills/commands mapping for harnesses with genuinely different models (Cursor scoped rules,
  Gemini TOML) — how much the override escape hatch must carry.
- Executor/Validator roles lean on the Claude `Agent` tool — on other harnesses these degrade
  to "codex-as-executor" / no in-harness subagent; clarify what "the system" guarantees per harness.
- `MEMORY_DIR` resolution depth change must not break existing installs mid-migration.

## Phases
_(deferred — fill in after design approval, per /new-plan decomposition.)_
