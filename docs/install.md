# Install & layout

How to install the wiring, rebuild it by hand, the on-disk layout, and how a repo is
mapped to a project (both directions).

> **Multi-harness.** `install.sh` is a generic, **manifest-driven** engine: it wires whichever
> harness you name (or auto-detects one), reading that harness's `harnesses/<name>/manifest`.
> Registered today: **Claude Code**, **Codex CLI**, **Antigravity**. To add another, see
> [Adding a harness](harnesses/adding-a-harness.md).

## Install

This repo **is** the memory tree. Clone it, then run the installer — it wires the
target harness (context injection, skills, commands, agents) in that harness's own
idiom and points `~/.claude-memory` at the clone so paths resolve.

```bash
git clone https://github.com/seyio91/ai-memory-system.git ~/.claude-memory
cd ~/.claude-memory
./install.sh                      # auto-detect the harness (prefers ~/.claude)
./install.sh --harness codex      # or wire a specific one: claude | codex | antigravity
./install.sh --list               # list registered harnesses
```

`install.sh` is idempotent, backs up anything it would overwrite, and is **agent-runnable**
— an agent inside any harness can run it to wire *that* harness up. It:

- resolves the harness (`--harness` flag, else auto-detect) and reads its **manifest**,
- validates the manifest (`scripts/validate-manifest.sh`), then runs the archetype driver:
  **hook** either symlinks `*.sh` + `statusline.sh` into `~/.claude/` (Claude) or registers
  namespaced `PreInvocation`/`PreToolUse` entries into a JSON hooks file (Antigravity —
  `~/.gemini/config/hooks.json`, injection live per model call via `agy.sh`);
  **file** (Codex) prepares the `context_target` dir — the context is rebuilt on
  each launch by the harness wrapper (`codex-mem.sh`), not symlinked,
- delivers **commands** per the manifest — `native` symlinks into the command dir (Claude
  `~/.claude/commands`), `skill` wraps each command as a `SKILL.md` into `skills_dir`
  (Codex/Antigravity `~/.agents/skills`), `doc` renders a reference, `none`,
- fans the bundled `skills/` (and Claude-shaped `agents/`) into each manifest's `skills_dir`
  via `scripts/link-skills.sh` / `link-agents.sh`,
- links the clone to `$MEMORY_DIR`, stamps `config.local.sh`, and seeds `identity.md` /
  `orchestrator.md` / `index.md` from their `*.template.md` if missing.

The manual steps it prints depend on the harness (e.g. Claude: register `settings.hooks.json`
+ place `CLAUDE.md`; a file harness: alias its launch wrapper).

Two steps it leaves to you:

1. **Register settings** — merge the hook entries and the `statusLine` from `harnesses/claude/settings.hooks.json` into `~/.claude/settings.json`.
2. **Global rules** — symlink `harnesses/claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (or merge into your existing one).

Then edit `identity.md` (start from `identity.template.md`) and `orchestrator.md`
(start from `orchestrator.template.md`), onboard a repo with `/pin <project>`,
and start a session. To install from a different clone path, set `MEMORY_DIR` to
that path before running `install.sh`.

> **Committed vs ignored.** The engine ships — `scripts/`, the `harnesses/claude/` wiring,
> `skills/`, `agents/`, and the `*.template.md` files. Your data does not: the real
> `index.md`, `domain/*.md`, `projects/*` (except `_template/`), `tasks/`, and
> `archive/` are git-ignored — and so are `identity.md` and `orchestrator.md`,
> which are per-instance. The tracked templates are their generic starting
> points; `install.sh` copies them whenever the live files are missing. See
> `.gitignore`.

## Upgrading

Upgrade with `scripts/sync-system.sh`. By default instances use `AI_MEMORY_CHANNEL=release`
and sync to the latest stable `v*` tag. Set `AI_MEMORY_CHANNEL=dev` in gitignored
`config.local.sh` for a source or dogfood checkout that should ff-pull its tracking branch
instead. One-shot `--to <ref>` syncs to a tag, branch, or sha without changing the channel.

See [UPGRADING.md](../UPGRADING.md) for the channel table, rollback behavior, semver rule,
and migration compatibility rules. After every checkout, `sync-system.sh` automatically runs
pending migrations and re-runs `install.sh`, so harness wiring is rebuilt from the checked-out
version.

## Rebuilding the wiring by hand

Prefer not to run the installer? The components, in build order — each has a detailed spec section elsewhere in the docs.

1. **Memory tree** — create `~/.claude-memory/` with `identity.md`, `orchestrator.md`, `index.md` (with the AUTOGEN fence), and the `domain/`, `projects/`, `scripts/` directories. See [Directory layout](#directory-layout).
2. **Project scaffold** — create `projects/_template/` (`memory.md` with the 5 required sections + frontmatter, empty `working.md`, `todo.md`, `plans/.gitkeep`, `archive/{plans,todos,working}/.gitkeep`). See [File formats](file-formats.md).
3. **Scripts** — populate `scripts/` (`_lib.sh`, `regenerate-index.sh`, `lint-memory.sh`, `archive-cleanup.sh`, `new-project.sh`, `memory-pin.sh`) plus the `scripts/tests/` suite; `chmod +x` all executables. Also create the `scripts/taskprovider/` Python package (stdlib-only task-provider layer — see [Task-provider layer](task-provider.md)). See [Scripts reference](scripts.md).
4. **Claude hooks** — keep the `~/.claude/hooks/` runtime root, symlink `harnesses/claude/statusline.sh` to `~/.claude/statusline.sh`, and register the three hook commands into `~/.claude/settings.json`: shared `scripts/hooks/inject.sh` for `UserPromptSubmit`, `harnesses/claude/hooks/session_start_memory.sh` for `SessionStart`, and `harnesses/claude/hooks/block_task_tools.sh` for `PreToolUse`. See [Claude Code › Hooks](harnesses/claude.md#hooks).
5. **Claude slash commands & skills** — symlink the command files in `commands/` into `~/.claude/commands/` (see [Slash commands](harnesses/claude.md#slash-commands)) and link the bundled `skills/` into `~/.claude/skills/` via `scripts/link-skills.sh` (see [Skills](harnesses/claude.md#skills)). Skills are auto-discovered by their `description`; the `brainstorming` gate is anchored by the `orchestrator.md` Orchestration routing rule.
6. **Global rules** — symlink `harnesses/claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (maintenance rules, workflow tiers, file-as-page nudge).
7. **Codex bridge** — populate `harnesses/codex/scripts/` (`codex-mem.sh`, `codex-mem-checkpoint.sh`), then create `~/.codex/AGENTS.local.md` (can be empty), `~/.codex/prompts/checkpoint.md`, `~/.codex/skills/checkpoint/{SKILL.md,agents/openai.yaml}`, and `~/.codex/rules/default.rules` (the executor deny list). `AGENTS.md` is generated — do not author it. See [Codex CLI](harnesses/codex.md).
8. **Verify** — run `scripts/lint-memory.sh` (expect exit 0), `scripts/regenerate-index.sh` (index matches frontmatter), launch a Claude session and confirm `<memory:*>` blocks inject, and confirm a `TaskCreate` call is blocked.

The `install.sh` route automates steps 4–6 (the `~/.claude/` symlinks) and the `~/.claude-memory` link; do them by hand only if you skip the installer. Per-engagement content (`projects/*`, `domain/*`) is user data and git-ignored — a clone gives you the scaffold (`projects/_template/`, the `*.template.md` files), not someone else's contents.

## Directory layout

```
~/.claude-memory/                      # the clone (default location; override with MEMORY_DIR)
├── install.sh                         # Links the harnesses/claude/ wiring into ~/.claude (see Install)
├── LICENSE
├── .gitignore                         # Ships templates + engine; ignores your real memory data
├── identity.md                        # Hard rules, injected once per session (per-instance, git-ignored)
├── identity.template.md               # Generic starting point for identity.md
├── orchestrator.md                    # Workflow doctrine, injected once per session (per-instance, git-ignored)
├── orchestrator.template.md           # Generic starting point for orchestrator.md
├── CHANGELOG.md                       # Thin changelog shell; release.sh finalizes sections
├── UPGRADING.md                       # Channel, rollback, semver, and migration notes
├── .applied-version                   # Migration high-water marker (gitignored)
├── index.md                           # Lifecycle prose + AUTOGEN roster (git-ignored; regenerated)
├── index.template.md                  # Template for index.md
├── domain/                            # Cross-project knowledge (one file per topic)
│   ├── _template.md                   #   committed; real domain/<topic>.md files are git-ignored
│   └── <topic>.md                     #   your knowledge files (loaded on demand via index match)
├── harnesses/                         # Per-harness wiring (Claude Code, Codex CLI)
│   ├── claude/                        #   Claude Code wiring — symlinked into ~/.claude by install.sh
│   │   ├── hooks/                     #     session_start_memory.sh, block_task_tools.sh
│   │   ├── commands/                  #     the slash commands (/pin, /checkpoint, /new-project, …)
│   │   ├── statusline.sh              #     context-bar status line (shows active memory project) → ~/.claude/statusline.sh
│   │   ├── settings.hooks.json        #     reference shape for auto-merged ~/.claude/settings.json hooks
│   │   └── CLAUDE.md                  #     global workflow rules → ~/.claude/CLAUDE.md
│   └── codex/
│       └── scripts/                   #   codex-mem.sh (Codex wrapper), codex-mem-checkpoint.sh
├── agents/                            # Bundled subagent definitions → ~/.claude/agents (link-agents.sh)
├── skills/                            # Authored per-instance skills → ~/.claude/skills (gitignored except .gitkeep)
├── skills.toml.example                 # Tracked remote-skill catalog template
├── skills.toml                         # Per-instance remote-skill manifest (gitignored)
├── .skill-cache/                       # Remote skills materialized here by resolve-skills.sh — gitignored
│   └── skills.lock                     #   pins each resolved commit (never committed)
├── migrations/                         # Forward-only instance migrations; see migrations/README.md
│   └── README.md
├── projects/
│   ├── _template/                     # Scaffold copied by new-project.sh
│   └── <name>/
│       ├── memory.md                  # Durable project memory (5 required sections)
│       ├── working.md                 # In-flight scratchpad (auto-injected when non-empty)
│       ├── plans/                     # Non-trivial plans (orchestrator-authored)
│       ├── todo.md                    # Checkbox source of truth for executable work
│       └── archive/                   # Persisted artifacts. NEVER read unless asked.
│           ├── plans/                 # Completed plans (moved by /plan-archive)
│           ├── todos/                 # Rolled todo snapshots (moved by /todo-archive)
│           └── working/               # Promoted working-memory snapshots (moved by /promote-memory)
├── tasks/                            # Local task-provider store (flat; one file per task,
│   └── <slug>.md                     #   project: in frontmatter; status in frontmatter only)
├── archive/
│   └── tasks/                        # Archived tasks (moved here on `set-status archived`)
└── scripts/
    ├── _lib.sh                        # Shared bash helpers (sourced)
    ├── regenerate-index.sh            # Rebuild index.md AUTOGEN block from frontmatter
    ├── lint-memory.sh                 # Mechanical content-quality checks
    ├── archive-cleanup.sh             # Prune archive/ files past retention threshold
    ├── new-project.sh                 # Bootstrap a new project from _template
    ├── taskctl                        # Bash wrapper → python3 -m taskprovider (used by /task, /start)
    └── taskprovider/                  # Python task-provider package (stdlib only):
        │                              #   contract.py, factory.py, __main__.py (JSON CLI),
        ├── providers/                 #   providers/{local,notion}/ (pkg + README + image)
        └── tests/                     #   unittest suite (offline; Notion live smoke gated)
```

After `install.sh`, these `~/.claude/` paths are **symlinks into this repo** (`harnesses/claude/`, `skills/`, `agents/`) — so editing them edits the repo, and `git pull` updates them:

```
~/.claude/
├── settings.json                      # Registers the three hooks; NOT a symlink — install.sh merges hook entries
├── CLAUDE.md                          # → harnesses/claude/CLAUDE.md  (global maintenance rules + file-as-page nudge)
├── hooks/                             # runtime root kept for hook/statusline compatibility
├── statusline.sh                      # → harnesses/claude/statusline.sh
├── commands/                          # → commands/  (slash commands, symlinked)
│   ├── new-project.md
│   ├── pin.md
│   ├── checkpoint.md
│   ├── plan.md
│   ├── plan-done.md
│   ├── plan-archive.md
│   ├── todo-archive.md
│   ├── promote-memory.md
│   ├── archive-cleanup.md
│   ├── reindex.md
│   ├── lint-memory.md
│   ├── task.md                        # /task — capture/manage backlog tasks
│   └── start.md                       # /start — begin a captured task (gate → brainstorm/plan)
├── skills/                            # → repo skills/ and .skill-cache/ (auto-discovered via description, symlinked)
│   └── <name>/SKILL.md                #   authored or remote materialized skills
└── agents/                            # → repo agents/  (subagent definitions, symlinked)

~/.codex/
├── AGENTS.md                          # Generated on every codex-mem.sh launch
├── AGENTS.local.md                    # User-owned overlay, never overwritten
├── rules/default.rules                # Executor deny list (apply/merge/destructive)
├── prompts/checkpoint.md              # /checkpoint slash command (explicit invoke)
└── skills/checkpoint/                 # Codex skill (autonomous invoke via natural language)
    ├── SKILL.md
    └── agents/openai.yaml
```

## Active-project detection

Both Claude's hook and the Codex wrapper resolve the project the same way:

1. Walk up from `$PWD` looking for `.agents/memory-project` (a one-line file naming the active project); the legacy `.claude/memory-project` is still read as a fallback when the neutral marker is absent. Readers check `.agents/memory-project` first, then fall back to `.claude/memory-project` — migrate old markers with `scripts/migrate-marker.sh`.
2. If no marker is found → no project context (generic Claude, memory system dormant). There is no global fallback, so concurrent sessions in different repos never collide.

Pin a repo to a project once:

```bash
cd /path/to/repo
~/.claude-memory/scripts/memory-pin.sh my-project   # preferred — writes forward marker + reverse map
# or, to hand-create just the forward marker:
mkdir -p .agents && echo my-project > .agents/memory-project
```

Any session — Claude or Codex — opened anywhere in that repo auto-loads `projects/my-project/`.

This is the **forward** map (checkout → project). The **reverse** map (project → checkout) is below.

## Reverse map: project → checkout

The forward map lets a checkout name its project. The reverse map lets a project's `memory.md` record *where its code lives on disk* — so cross-project work can not only read a sibling's memory but also inspect the sibling's actual code. The path is resolved **per environment**, so the same `memory.md` works on a laptop and inside a container/sandbox.

**Identifier — path-first, git remote as fallback.** `AI_MEMORY_PROJECTS_ROOT` (default `$HOME/Projects`) is the root under which checkouts live. Frontmatter stores `repo_path` *relative to that root*; the resolved path is `$AI_MEMORY_PROJECTS_ROOT/$repo_path`. If that directory is gone, the resolver falls back to locating a checkout under the root whose `origin` remote matches the stored `repo`. Override it per environment in `config.local.sh` (preferred) or via the env var:

| Environment | `AI_MEMORY_PROJECTS_ROOT` |
|-------------|---------------------------|
| Host (laptop) | `$HOME/Projects` (default) |
| Sandbox / container | `/workspace` |

**Per-environment config — `config.local.sh`.** `scripts/_lib.sh` and `taskctl` source a gitignored `config.local.sh` (next to the memory tree) if present, so per-machine values reach scripts, hooks, and subagents that don't inherit your shell rc. Copy `config.local.sh.example` and set `AI_MEMORY_PROJECTS_ROOT`, `MEMORY_TASK_PROVIDER`, etc. there. (`MEMORY_DIR` itself must come from the env, since it's needed to *find* the config file.)

**Populate it with `memory-pin` (or `/pin`).** Run from *inside* a checkout:

```bash
cd /path/to/repo
~/.claude-memory/scripts/memory-pin.sh my-project
```

It writes both directions in one action: the forward `.agents/memory-project` marker, and the reverse `repo` + `repo_path` fields into `projects/my-project/memory.md` frontmatter (body left byte-for-byte intact). The projects root is canonicalized before stripping (so a symlinked root like macOS `/var` → `/private/var` still matches git's physical toplevel); a checkout outside the root is stored as an absolute `repo_path` with a warning. In Claude, `/pin my-project` does the same. **Drift** (moved/missing checkout, mismatched back-pin) is caught by `lint-memory.sh`, not auto-repaired.

**Resolving in code.** `resolve_repo_path <project>` (in `_lib.sh`) prints the checkout dir and returns 0, else returns 1 — path-first, then the git-remote fallback. This is the single resolver used everywhere; the local path is **never** duplicated into a cross-project relationship table — a delegate reads it from the sibling's own frontmatter via the resolver.
