# Memory System

A markdown-only memory tree shared by **Claude Code** and **OpenAI Codex CLI**. No vector DB, no daemons, no MCP servers — just files, hooks, and short shell scripts. Insights captured in one agent are visible to the other on the next session.

## Mental model

Three layers, mirroring Karpathy's LLM Wiki pattern:

1. **Schema** — hard rules and behavioral conventions. `identity.md`, `~/.claude/CLAUDE.md`. Outranks everything else.
2. **Wiki** — durable, LLM-readable knowledge. `domain/*.md` (cross-project) + `projects/*/memory.md` (engagement-specific).
3. **Scratchpad** — in-flight, per-project. `projects/*/working.md`. Matures into the wiki via `/promote-memory`.

The wiki compounds: every non-trivial synthesis gets offered for filing. The index is auto-generated from frontmatter.

---

## Install

This repo **is** the memory tree. Clone it, then run the installer — it links the
Claude Code wiring (hooks, slash commands, skills, agents) into `~/.claude/` and
points `~/.claude-memory` at the clone so the hook defaults resolve.

```bash
git clone https://github.com/seyio91/ai-memory-system.git ~/.claude-memory
cd ~/.claude-memory
./install.sh
```

`install.sh` is idempotent and backs up anything it would overwrite. It:

- links the clone to `$MEMORY_DIR` (default `~/.claude-memory`),
- symlinks `claude/hooks/*.sh` → `~/.claude/hooks/`,
- symlinks `claude/commands/*.md` → `~/.claude/commands/`,
- symlinks `claude/statusline.sh` → `~/.claude/statusline.sh` (the context-bar status line, showing the active memory project),
- links the bundled `skills/` and `agents/` into `~/.claude/` (via `scripts/link-skills.sh` / `link-agents.sh`),
- seeds `identity.md` and `index.md` from their `*.template.md` if missing.

Two steps it leaves to you:

1. **Register settings** — merge the hook entries and the `statusLine` from `claude/settings.hooks.json` into `~/.claude/settings.json`.
2. **Global rules** — symlink `claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (or merge into your existing one).

Then edit `identity.md` (start from `identity.template.md`), onboard a repo with
`/pin <project>`, and start a session. To install from a different clone path,
set `MEMORY_DIR` to that path before running `install.sh`.

> **Committed vs ignored.** The engine ships — `scripts/`, the `claude/` wiring,
> `skills/`, `agents/`, and the `*.template.md` files. Your data does not: the real
> `index.md`, `domain/*.md`, `projects/*` (except `_template/`), `tasks/`, and
> `archive/` are git-ignored. `identity.md` is committed (preferences, not client
> data) alongside `identity.template.md` as a generic starting point. See `.gitignore`.

## Rebuilding the wiring by hand

Prefer not to run the installer? The components, in build order — each has a detailed spec section below.

1. **Memory tree** — create `~/.claude-memory/` with `identity.md`, `index.md` (with the AUTOGEN fence), and the `domain/`, `projects/`, `scripts/` directories. See [Directory layout](#directory-layout).
2. **Project scaffold** — create `projects/_template/` (`memory.md` with the 5 required sections + frontmatter, empty `working.md`, `todo.md`, `plans/.gitkeep`, `archive/{plans,todos,working}/.gitkeep`). See [File format conventions](#file-format-conventions).
3. **Scripts** — populate `scripts/` (`_lib.sh`, `codex-mem.sh`, `codex-mem-checkpoint.sh`, `regenerate-index.sh`, `lint-memory.sh`, `archive-cleanup.sh`, `new-project.sh`, `memory-pin.sh`) plus the `scripts/tests/` suite; `chmod +x` all executables. Also create the `scripts/taskprovider/` Python package (stdlib-only task-provider layer — see [Task-provider layer](#task-provider-layer)). See [Scripts reference](#scripts-reference).
4. **Claude hooks** — symlink the four scripts in `claude/hooks/` (`inject_memory.sh`, `session_start_memory.sh`, `block_task_tools.sh`, and the sourced `memory_common.sh`) into `~/.claude/hooks/` (`chmod +x`), then register the three entries from `claude/settings.hooks.json` in `~/.claude/settings.json`. See [Hooks](#hooks).
5. **Claude slash commands & skills** — symlink the command files in `claude/commands/` into `~/.claude/commands/` (see [Slash commands](#slash-commands)) and link the bundled `skills/` into `~/.claude/skills/` via `scripts/link-skills.sh` (see [Skills](#skills)). Skills are auto-discovered by their `description`; the `brainstorming` gate is anchored by the `identity.md` Orchestration routing rule.
6. **Global rules** — symlink `claude/CLAUDE.md` → `~/.claude/CLAUDE.md` (maintenance rules, workflow tiers, file-as-page nudge).
7. **Codex bridge** — create `~/.codex/AGENTS.local.md` (can be empty), `~/.codex/prompts/checkpoint.md`, `~/.codex/skills/checkpoint/{SKILL.md,agents/openai.yaml}`, and `~/.codex/rules/default.rules` (the executor deny list). `AGENTS.md` is generated — do not author it. See [Codex CLI](#codex-cli).
8. **Verify** — run `scripts/lint-memory.sh` (expect exit 0), `scripts/regenerate-index.sh` (index matches frontmatter), launch a Claude session and confirm `<memory:*>` blocks inject, and confirm a `TaskCreate` call is blocked.

The `install.sh` route automates steps 4–6 (the `~/.claude/` symlinks) and the `~/.claude-memory` link; do them by hand only if you skip the installer. Per-engagement content (`projects/*`, `domain/*`) is user data and git-ignored — a clone gives you the scaffold (`projects/_template/`, the `*.template.md` files), not someone else's contents.

---

## Directory layout

```
~/.claude-memory/                      # the clone (default location; override with MEMORY_DIR)
├── install.sh                         # Links the claude/ wiring into ~/.claude (see Install)
├── LICENSE
├── .gitignore                         # Ships templates + engine; ignores your real memory data
├── identity.md                        # Hard rules, injected once per Claude session (git-tracked)
├── identity.template.md               # Generic starting point for identity.md
├── index.md                           # Lifecycle prose + AUTOGEN roster (git-ignored; regenerated)
├── index.template.md                  # Template for index.md
├── domain/                            # Cross-project knowledge (one file per topic)
│   ├── _template.md                   #   committed; real domain/<topic>.md files are git-ignored
│   └── <topic>.md                     #   your knowledge files (loaded on demand via index match)
├── claude/                            # Claude Code wiring — symlinked into ~/.claude by install.sh
│   ├── hooks/                         #   inject_memory.sh, session_start_memory.sh,
│   │                                  #   block_task_tools.sh, memory_common.sh (sourced)
│   ├── commands/                      #   the slash commands (/pin, /checkpoint, /new-project, …)
│   ├── statusline.sh                  #   context-bar status line (shows active memory project) → ~/.claude/statusline.sh
│   ├── settings.hooks.json            #   hook + statusLine entries to merge into ~/.claude/settings.json
│   └── CLAUDE.md                      #   global workflow rules → ~/.claude/CLAUDE.md
├── agents/                            # Bundled subagent definitions → ~/.claude/agents (link-agents.sh)
├── skills/                            # Bundled skills → ~/.claude/skills (link-skills.sh)
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
    ├── codex-mem.sh                   # Codex wrapper — builds AGENTS.md, exec codex
    ├── codex-mem-checkpoint.sh        # Companion for the /checkpoint Codex skill
    ├── regenerate-index.sh            # Rebuild index.md AUTOGEN block from frontmatter
    ├── lint-memory.sh                 # Mechanical content-quality checks
    ├── archive-cleanup.sh             # Prune archive/ files past retention threshold
    ├── new-project.sh                 # Bootstrap a new project from _template
    ├── taskctl                        # Bash wrapper → python3 -m taskprovider (used by /task, /start)
    └── taskprovider/                  # Python task-provider package (stdlib only):
        │                              #   contract.py, factory.py, __main__.py (JSON CLI),
        ├── providers/                 #   providers/{local,notion}.py
        └── tests/                     #   unittest suite (offline; Notion live smoke gated)
```

After `install.sh`, these `~/.claude/` paths are **symlinks into this repo** (`claude/`, `skills/`, `agents/`) — so editing them edits the repo, and `git pull` updates them:

```
~/.claude/
├── settings.json                      # Registers the three hooks (see below); NOT a symlink — you merge it
├── CLAUDE.md                          # → claude/CLAUDE.md  (global maintenance rules + file-as-page nudge)
├── hooks/                             # → claude/hooks/  (symlinks)
│   ├── inject_memory.sh               # UserPromptSubmit — injects <memory:*> blocks
│   ├── session_start_memory.sh        # SessionStart — full inject; arms post-compaction reload
│   ├── block_task_tools.sh            # PreToolUse — blocks TaskCreate/TaskUpdate
│   └── memory_common.sh               # Shared helpers, sourced by the hooks above
├── commands/                          # → claude/commands/  (slash commands, symlinked)
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
├── skills/                            # → repo skills/  (auto-discovered via description, symlinked)
│   └── <name>/SKILL.md                #   e.g. brainstorming, renovate-manager, grafana-oss, …
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

---

## Active-project detection

Both Claude's hook and the Codex wrapper resolve the project the same way:

1. Walk up from `$PWD` looking for `.claude/memory-project` (a one-line file naming the active project).
2. If no marker is found → no project context (generic Claude, memory system dormant). There is no global fallback, so concurrent sessions in different repos never collide.

Pin a repo to a project once:

```bash
cd /path/to/repo
mkdir -p .claude && echo my-project > .claude/memory-project
```

Any session — Claude or Codex — opened anywhere in that repo auto-loads `projects/my-project/`.

This is the **forward** map (checkout → project). The **reverse** map (project → checkout) is below.

---

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

It writes both directions in one action: the forward `.claude/memory-project` marker, and the reverse `repo` + `repo_path` fields into `projects/my-project/memory.md` frontmatter (body left byte-for-byte intact). The projects root is canonicalized before stripping (so a symlinked root like macOS `/var` → `/private/var` still matches git's physical toplevel); a checkout outside the root is stored as an absolute `repo_path` with a warning. In Claude, `/pin my-project` does the same. **Drift** (moved/missing checkout, mismatched back-pin) is caught by `lint-memory.sh`, not auto-repaired.

**Resolving in code.** `resolve_repo_path <project>` (in `_lib.sh`) prints the checkout dir and returns 0, else returns 1 — path-first, then the git-remote fallback. This is the single resolver used everywhere; the local path is **never** duplicated into a cross-project relationship table — a delegate reads it from the sibling's own frontmatter via the resolver.

---

## Claude Code

### Auto-injection

`~/.claude/hooks/inject_memory.sh` runs on every prompt as a `UserPromptSubmit` hook. It reads the hook's stdin JSON (for `session_id` and `cwd`) and emits the `<memory:*>` blocks via the `hookSpecificOutput.additionalContext` contract — **not** by appending to the user message:

```bash
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$esc"
```

`json_escape` falls back `jq -Rs .` → `python3 json.dumps` → a hand-rolled `sed`/`awk` escaper so the hook works without `jq`. If nothing would be injected it `exit 0`s with no output.

| Block | When |
|-------|------|
| `<memory:identity>` | First prompt of a session |
| `<memory:project name="...">` | First prompt of a session, if active project resolved |
| `<memory:index>` | First prompt of a session |
| `<memory:working>` | **Every prompt** if `projects/<active>/working.md` is non-empty |

Claude never has to "remember to read" memory — it arrives in-band. Domain files are *not* auto-injected; Claude reads them on demand when the index entry matches the task.

**Per-session markers.** "First prompt" is the absence of a per-session marker file at `~/.claude/memory_sessions/<session_id>` — not a single shared `memory_last_session` file. Concurrent sessions don't clobber each other's once-per-session injection. On the first-prompt branch the hook writes the marker (`: > "$marker"`) and opportunistically sweeps markers older than 2 days (`find "$MARKDIR" -type f -mtime +2 -delete`), keeping `memory_sessions/` self-maintaining off the hot path. The hook honors `MEMORY_DIR` and `MEMORY_SESSIONS_DIR` env overrides (used by the test suite to sandbox).

### Hooks

Three hooks, registered in `~/.claude/settings.json`. The scripts are symlinked from `claude/hooks/` by `install.sh`; `memory_common.sh` is sourced by the others, not registered.

| Hook | Event | Script | Effect |
|------|-------|--------|--------|
| Memory injection | `UserPromptSubmit` | `hooks/inject_memory.sh` | Emits the `<memory:*>` blocks above as `hookSpecificOutput.additionalContext`; otherwise the per-prompt breadcrumb. |
| Session start | `SessionStart` | `hooks/session_start_memory.sh` | Full injection once on session load; on `source=compact` arms a sentinel so the next prompt re-injects (compaction recovery). |
| Task-tool block | `PreToolUse` (matcher `TaskCreate\|TaskUpdate`) | `hooks/block_task_tools.sh` | Consumes stdin, writes the tier-classification reminder to stderr, `exit 2` — blocking the call. Forces all executable-work tracking into `projects/<active>/todo.md`. |

The three entries to merge into `settings.json` ship in `claude/settings.hooks.json`:

```json
{
  "SessionStart": [
    { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/session_start_memory.sh" }] }
  ],
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/inject_memory.sh" }] }
  ],
  "PreToolUse": [
    { "matcher": "TaskCreate|TaskUpdate",
      "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/block_task_tools.sh" }] }
  ]
}
```

All hook scripts must be `chmod +x` (`install.sh` does this). A setup that skips `block_task_tools.sh` leaves the harness free to call `TaskCreate` — the workflow rule "`todo.md` is the single source of truth" is *enforced* here, not just documented.

### Maintenance rules (from `~/.claude/CLAUDE.md`)

- **Update memory immediately** when you learn or decide something durable. Don't batch.
- **Project-specific** → `projects/<active>/memory.md` (place under the matching section).
- **Cross-project** → `projects/<active>/working.md` first, then `/promote-memory` later.
- **Checkpoint before pauses, tool switches, or session end** → `/checkpoint`.
- **Offer to file non-trivial synthesis as a wiki page** — Claude prompts at the end of substantial answers (architecture, comparisons, gotcha analyses). Skipped for short or code-only answers.

### Slash commands

| Command | Purpose |
|---------|---------|
| `/new-project <name>` | Copy `_template` into `projects/<name>` (scaffold only — pin a repo with `.claude/memory-project` to activate) |
| `/pin <name>` | From inside a checkout, run `memory-pin.sh <name>` — writes the forward `.claude/memory-project` marker and the reverse `repo`/`repo_path` frontmatter |
| `/checkpoint` | Synthesize task/done/next/blockers from session context (no questions); append a dated entry to `## Checkpoints` in `working.md` |
| `/new-plan <name>` | Scaffold a new plan file in `projects/<active>/plans/` with frontmatter and a required `## Success criteria` section (the [Task Contract](#task-contract)). Renamed from `/plan` to avoid colliding with the native `/plan` plan-mode command. |
| `/plan-done <name>` | Flip a plan's `status:` to `done` and stamp `completed:` date |
| `/plan-archive <name>` | Move a completed plan from `plans/` to `archive/plans/` |
| `/todo-archive [<slug>]` | Snapshot a fully-ticked `todo.md` to `archive/todos/` and reset. Auto-derives the slug when `todo.md` references exactly one plan and no `<slug>` was passed. |
| `/promote-memory` | Agent extracts candidate learnings from `working.md`, labels each with inferred destination (`[domain:<topic>]` or `[project]`); user multi-selects which to keep; archive `working.md`; regenerate `index.md` |
| `/archive-cleanup [--all-projects] [--days N]` | Dry-run first, then on confirmation delete `archive/{plans,todos,working}/` files older than retention threshold (default 30 days; override via `MEMORY_ARCHIVE_RETAIN_DAYS`). `.gitkeep` preserved. |
| `/reindex` | Run `regenerate-index.sh`, show diff |
| `/lint-memory` | Mechanical checks + LLM-judgment (contradictions, stale paths, broken refs) |
| `/task [verb] [@project] ...` | Capture/manage [task-provider](#task-provider-layer) backlog tasks (`add`/`list`/`done`/`archive`/`show`). Project defaults to the active marker; `@project` overrides. Capturing does **not** create a plan — that's `/start`. Thin wrapper over `scripts/taskctl`. |
| `/start [<ref>]` | Begin a captured task: pull it (project-agnostic by `ref`), run the [brainstorm gate](#skills) (feature-with-open-design → `brainstorming` skill; settled/quick → straight to plan), scaffold the linked plan in the task's project (`task_provider`/`task_ref` frontmatter), push the clarified Goal back via `update`, flip status to `started`. Bare `/start` lists the active backlog to pick. |

### Skills

Claude Code skills live under `~/.claude/skills/<name>/SKILL.md` — symlinked from this repo's `skills/` by `link-skills.sh` — and are auto-discovered by their frontmatter `description` (not listed in `index.md` — they are capabilities, not memory). Several ship in `skills/` (e.g. `renovate-manager`, `grafana-oss`, `prometheus`, `tempo`, `dashboarding`, `observability-check`, `terraform-example-gen`, `bkt`, `teach`, `excalidraw-diagram`). The one wired into the workflow is `brainstorming`:

| Skill | Gate | Effect |
|-------|------|--------|
| `brainstorming` | **Tier-3 feature tasks with open design questions only** — silent on Tier 1 (research/Q&A), Tier 2 (quick edits), and settled Tier-3 work (mechanical refactors, renames, migrations) | Runs the collaborative design pass (clarify → 2-3 approaches → sectioned design), then hands off to `/new-plan`, folding the approved design into the plan's `## Goal` / `## Success criteria` / `## Design` / `## Risks`. Never writes code or scaffolds the plan itself. |

The gate lives in two places that must agree: the skill's `description` (what Claude Code matches on) and the routing rule in `identity.md` → Orchestration (the injected-every-session anchor). The skill is **orchestrator-only** (Claude main session — Codex never brainstorms) and **seed-agnostic**: it accepts either a fresh user request or a pulled task summary, so a future `/start` can delegate to it without changing the skill.

#### Skill write boundary (`metadata.tier`)

Every skill declares one neutral frontmatter field under `metadata:`:

```yaml
metadata:
  tier: target-read-only   # or: target-write
```

`tier` is a **coarse label, not a tool list** — deliberately *not* Claude's `allowed-tools` (that's Claude-only; Codex ignores it). Enforcement stays harness-agnostic: the label is what *we* check, identically for Claude and Codex.

- **`target-read-only`** — the skill must not modify the thing it operates on (the project/repo under review). Review, analysis, planning, and reference skills: `renovate-manager`, `observability-check`, `prometheus`, `tempo`, `teach`, `brainstorming`.
- **`target-write`** — the skill may modify the target. Generators and action skills: `terraform-example-gen`, `dashboarding`, `excalidraw-diagram`, `fiter-infrastructure-analyzer`, `grafana-oss`, `bkt`.

The label resolves **three write zones**:

1. **Target tree** — the project/repo being worked on. Gated by `tier` (read-only ⇒ hands off).
2. **The skill's own folder** (`skills/<name>/`) — **always writable, at any time, regardless of tier**, with no declaration needed. This is where a read-only skill puts its output (e.g. `renovate-manager` writes review memory under `skills/renovate-manager/renovate-reviews/`). No `memory_store` field — the rule is universal, so there's nothing to declare.
3. **Everything else** (`projects/*/memory.md`, `working.md`, `index.md`, and *other* skills' folders) — **off-limits by default**, even though it's in the memory repo.

Enforcement is harness-agnostic and *detective* (a post-run check, layered under the codex execpolicy which prevents the destructive class) — see `projects/ai-memory/plans/skill-subsystem.md` for the `tier` schema (#10), the `validate-skills.sh` static check (#4), and the post-run git-diff boundary check (#11).

---

## Codex CLI

Codex has no native memory hook. The bridge is `scripts/codex-mem.sh`, a wrapper that rebuilds `~/.codex/AGENTS.md` from the memory tree and then `exec codex "$@"`.

### Daily use

```bash
# Instead of `codex`:
~/.claude-memory/scripts/codex-mem.sh

# Or alias it:
alias codex='~/.claude-memory/scripts/codex-mem.sh'

# Subcommands pass through:
codex-mem.sh exec --sandbox read-only "what does our terraform domain file say?"
codex-mem.sh review
```

### What lands in `~/.codex/AGENTS.md`

Built fresh on every invocation, in this order:

1. **`# === IDENTITY ===`** — `identity.md` verbatim.
2. **`# === PROJECT: <name> ===`** — `projects/<active>/memory.md`.
3. **`# === MEMORY INDEX ===`** — `index.md` (lifecycle prose + auto-generated catalog).
4. **`# === DOMAIN INDEX ===`** — table synthesized from frontmatter in each `domain/*.md` (file path, triggers, summary), with a lazy-load instruction: Codex reads the file with its shell tool when the user's request matches a topic's triggers.
5. **`# === WORKING MEMORY ===`** — `projects/<active>/working.md` if non-empty.
6. **`# === LOCAL OVERLAY ===`** — `~/.codex/AGENTS.local.md` if present.

### Local overlay — your permanent Codex instructions

`~/.codex/AGENTS.local.md` is **never** touched by the script. Edit it freely; it's concatenated at the bottom of the generated file every time. The Codex analogue of `~/.claude/CLAUDE.md`.

```bash
echo "Always run 'just lint' before suggesting commit messages." >> ~/.codex/AGENTS.local.md
```

### `/checkpoint` inside Codex

Captures the session into `projects/<active>/working.md`. Two trigger surfaces, same behavior:

- **Explicit slash command** — `~/.codex/prompts/checkpoint.md`. Type `/checkpoint` in the Codex TUI.
- **Autonomous skill** — `~/.codex/skills/checkpoint/SKILL.md`. Codex invokes the skill itself when the session is winding down or you say things like *"save state"*, *"let's pause here"*, *"before I close"*. Discovered via the SKILL's `description` field.

Either path runs:

1. `scripts/codex-mem-checkpoint.sh --for-codex` (prints active project, `working.md` path, recent-history snippet, scaffold).
2. Synthesizes Task/Done/Next/Blockers from this session's context (no questions asked).
3. Appends a `### YYYY-MM-DD — <task>` block at the end of `## Checkpoints` in `working.md` (newest last; prior entries preserved).
4. If applicable, appends a bullet to `## Cross-project learnings (pending promotion)`.

Net effect: typing `/checkpoint` or simply ending a session with "let's save state" captures the work back into memory. Same memory is visible to Claude next session.

### Adding a new domain topic (Codex picks it up automatically)

1. Drop a new file `domain/postgres.md` with frontmatter:

   ```yaml
   ---
   topic: postgres
   triggers: [pg, postgres, psql, plpgsql]
   summary: Postgres conventions, indexing rules, migration patterns
   ---
   ```

2. Next `codex-mem.sh` invocation regenerates `AGENTS.md` with a new row in the Domain Index.
3. No code change. Codex sees it on the next session.

### Standalone `codex-mem-checkpoint.sh`

Outside a Codex session — useful after exiting Codex while a session insight is still fresh:

```bash
~/.claude-memory/scripts/codex-mem-checkpoint.sh
```

Opens `$EDITOR` on `working.md` with a checkpoint scaffold appended. Fill in done/next/blockers, save, done.

---

## Orchestrator / Executor / Validator workflow

**Three task tiers — every request is classified first:**

| Tier | Example | What happens |
|------|---------|--------------|
| Research / explore / Q&A | "what does X do", "how should we approach Y" | Answer directly. No plan, no todo, no working memory, no executor. |
| Quick actionable item | one edit, a one-off command, a short fix | Just do it. No plan, no `todo.md` entry. |
| Large / non-trivial actionable task | multi-step, multiple files, real blast radius | Plan file + `todo.md` step tracking; flows through the role pipeline below. |

`todo.md` tracks **plan execution** — no plan means no `todo.md` entry. Only the third tier flows through the orchestrator/executor/validator roles. The orchestrator is Claude (main session); the executor is selectable (`claude-subagent` by default, or a configured CLI like `codex`); the validator is a Claude subagent invoked on judgment.

### Roles

| Role | Tool | Model | Responsibility |
|------|------|-------|----------------|
| Orchestrator | Claude main session | Opus | Plans, decomposes into `todo.md` items, delegates non-trivial work. **Handles short tasks directly when delegating would be more overhead than the work. Handles all research/exploration directly — no plan/todo/executor for read-only investigation.** |
| Executor | selectable via `AI_MEMORY_EXECUTOR` (see [Executor selection](#executor-selection)) | per executor | Writes code/config in the workspace; runs read-only commands; never applies/merges to infra. `claude-subagent` (in-harness Agent tool, `sonnet`/`haiku`) by default; `codex` or another CLI when configured. |
| Validator | Claude `Agent` subagent | `sonnet` | Independent check on executor output. Invoked on orchestrator's judgment when correctness matters: code writes, terraform changes, GitOps-visible ops, multi-step state. Verifies output against the plan's `## Success criteria` (see [Task Contract](#task-contract)) — each criterion pass/fail with evidence, scope capped to exactly those. |

### Task Contract

Every plan-tier task carries explicit **success criteria** — the observable, checkable conditions that define "done." This is the contract the validator checks against; without it, "done" is opinion. Defined in `identity.md` → `### Task Contract` (injected every session).

- **Plan-tier only.** Quick items and research/Q&A are exempt — no criteria for a one-line edit or a question.
- **Best-effort by default.** If the user doesn't state criteria, the orchestrator drafts them from session context and surfaces them before executing — never blank. **For feature-tier tasks routed through the `brainstorming` skill, this seam is tighter:** success criteria are derived *with* the user during the clarify pass, so they are collaboratively-agreed rather than orchestrator-guessed — an upgrade of this rule for the one tier where the design is worth examining, not a parallel mechanism.
- **Checkable, not aspirational.** Each criterion is verifiable by reading output, running a command, or inspecting state ("`terraform validate` passes and the module exposes output `X`", not "works well").
- **Lives in the plan.** Captured in the plan's `## Success criteria` section, scaffolded by `/new-plan`. The validator checks executor output against exactly these.

Enforcement is **template-only** — `/new-plan` scaffolds the section; no hook gates it. The best-effort-fill rule is what keeps a criteria-less plan from slipping through.

### File conventions

- `projects/<active>/plans/<name>.md` — one file per non-trivial plan. Frontmatter: `plan`, `status`, `created`, `owner`, plus optional `task_provider`/`task_ref` (written by the `/start` task-linking step when a plan is backed by a captured task — see [Task-provider layer](#task-provider-layer)). Body carries `## Goal`, a required `## Success criteria` (the Task Contract), the `## Design` section (populated by the [`brainstorming`](#skills) skill for feature-tier plans), `## Phases`, and `## Risks / open questions`. The frontmatter `task_*` fields and the body `## Design` section occupy different regions of the file and never conflict. Linked from `todo.md`.
- `projects/<active>/todo.md` — markdown-checkbox list. Large items reference a plan file. Small items inline. Tick boxes in place when done.
- `projects/<active>/archive/plans/<name>.md` — completed plans, moved when their referencing todo items all close.
- `projects/<active>/archive/todos/YYYY-MM-DD-<slug>.md` — snapshots of fully-ticked `todo.md`, taken when the file is rolled.

### Executor selection

The orchestrator delegates actionable work to a **selectable executor**, configured in `config.local.sh`:

| Key | Default | Meaning |
|-----|---------|---------|
| `AI_MEMORY_EXECUTOR` | `claude-subagent` | Preferred executor. Built-ins: `claude-subagent` (in-harness Agent tool), `codex` (CLI via `codex-mem.sh --executor`). Any other value names a generic CLI executor. |
| `AI_MEMORY_EXECUTOR_CMD_<key>` | — | Command template for generic CLI executor `<key>` (`{prompt}` substituted, already shell-quoted; `<key>` is `[A-Za-z0-9_]+`). |
| `AI_MEMORY_EXECUTOR_FALLBACK` | `claude-subagent` | Used when the preferred CLI binary is absent. Empty = hard-fail. |

To delegate, the orchestrator runs `scripts/executor.sh --which`, which resolves config + availability and prints `subagent` or `cli:<key>`:

- `subagent` → use the Claude `Agent` tool.
- `cli:<key>` → run `scripts/executor.sh --run "<prompt>"`, which execs the CLI executor (for `codex`, `codex-mem.sh --executor "<prompt>"`); if it prints `EXECUTOR_USE_SUBAGENT` (exit 3), use the Agent tool instead.

`--show` prints the resolved selection for debugging. A missing CLI binary auto-falls-back to `AI_MEMORY_EXECUTOR_FALLBACK` (default `claude-subagent`), so an unconfigured machine always has a working executor.

### Hard rules

- **No `TaskCreate`.** `todo.md` is the single source of truth for executable work.
- **Archive is never read unless the user explicitly asks.** Don't load it, grep it, or quote from it.
- **Executors never apply or merge to running infrastructure.** Enforced by restating the deny-list in every delegation prompt (both planes) and in `identity.md`; for the `codex` CLI executor, `~/.codex/rules/default.rules` is optional defense-in-depth if installed: `terraform apply`, `terraform destroy`, `kubectl apply`, `kubectl delete`, `gh pr merge`, `helm install`, `helm upgrade`. Generic principle: any destructive or additive action directly to running infrastructure is off-limits to executors.

---

## Cross-project relationships

Projects map one-to-one to repositories, but some repos relate: a single unit of work spans several, sometimes with ordering (e.g. infra in one repo must apply before deployment in another). Relationships are **distributed** — they live in the project where the work starts, not in an umbrella.

**The map — `## Related Projects`.** A project that reaches into others carries an optional `## Related Projects` table in its `memory.md`:

| Project | When it's involved | It owns / entry point |
|---------|--------------------|------------------------|
| <other> | <trigger condition> | <what it owns — entry file/path> |

Because `memory.md` is injected wholesale on the first prompt (Claude) and built into `AGENTS.md` on every launch (Codex), this table is always in context — so the active project *knows* its relationships before anything else is loaded. The "When it's involved" column is the trigger; "It owns / entry point" gives the sibling's starting file so a delegate lands somewhere concrete.

The table deliberately carries **no on-disk path**. A delegate that needs to inspect the sibling's *code* resolves the checkout with `resolve_repo_path <sibling>`, which reads `repo_path`/`repo` from the sibling's own frontmatter (see [Reverse map](#reverse-map-project--checkout)). The path lives in one place — the sibling's `memory.md` — and is resolved per environment, so it is never duplicated into (and never goes stale in) the relationship table.

**The hop — delegate, don't load.** When a task matches a row, the orchestrator (Claude main session) does **not** load the sibling's `memory.md` into its own thread (that would bloat context, especially across several siblings). Instead it delegates the sibling-scoped work to an **executor** (selected via `AI_MEMORY_EXECUTOR` — `claude-subagent` by default, or a CLI like `codex`). The `identity.md` rule makes this dependable.

**Delegation contract:**
- *Dispatch* — the prompt is self-contained, because the delegate does not inherit the orchestrator's context: it points at `identity.md` (hard rules / executor deny-list) and `projects/<sibling>/memory.md`, states the task, and sets the default deliverable to **plan only** (no edits to the sibling repo).
  - *Codex caveat:* a `codex-mem.sh` launch builds `AGENTS.md` from the **active** project, not the sibling. So when the executor is Codex, either (a) pin the sibling repo (`.claude/memory-project`) and launch Codex there so its `AGENTS.md` resolves to the sibling, or (b) pass the sibling's `memory.md` path explicitly in the prompt for Codex to read with its shell tool. A Claude `Agent` subagent has no such caveat — it just reads the files named in the prompt.
- *Work* — the delegate produces the core plan and persists it to `projects/<sibling>/plans/<name>.md` (frontmatter `plan`, `status: active`, `created`, `owner`).
- *Return* — a compact, structured summary: `project`, `goal` (one line), `plan` (ordered core steps), `entry points`, `depends on / ordering`, `plan file` (path), `blockers`.

The orchestrator keeps only the summary in context and re-opens the plan file on demand if it needs the detail — which is how the main thread coordinates a multi-repo sequence without resident sibling memory. Implementation is a separate, explicit delegation later. For a trivial one-line touch, the orchestrator just reads the single relevant file instead of delegating.

**Executing a plan set.** Planning and execution are separate. To *execute* persisted plans (e.g. the set an onboarding produces), the orchestrator walks them in their documented order and delegates **each** plan to an executor — Codex via `codex-mem.sh --executor`, or a Claude `Agent` subagent as fallback — with a self-contained prompt pointing at `identity.md`, the plan file, and the project `memory.md`; the executor implements the edits in the repo and returns a compact summary (changed files + the PR/apply action needed). A validator subagent optionally checks correctness-sensitive edits (e.g. Terraform). The orchestrator keeps only the summaries, so execution stays context-lean, and it **pauses at human/CI gates** — PR merges and `terraform`/`kubectl` applies, which executors are forbidden to perform — resuming the next phase on the user's confirmation. This is generic: any multi-repo plan set is executed this way.

---

## Knowledge lifecycle

```
                                          ┌──▶ domain/<topic>.md      cross-project
projects/<active>/working.md  ─/promote-──┤    [+ index.md regen]
   [per-project scratchpad]               └──▶ projects/<active>/memory.md ## Decisions Log
                                               project-specific
```

- **Working memory** — per-project scratchpad. Injected on every prompt while non-empty. Each project has its own — concurrent sessions on different projects don't collide.
- **Direct project memory updates** — for engagement-specific decisions, edit `projects/<active>/memory.md` directly (Architecture Decisions / Known Constraints / Current State / Current Goal).
- **Checkpoint discipline** — before pauses, tool switches, or session end. `/checkpoint` in Claude; `/checkpoint` in Codex. Both write to the same `working.md`.
- **Promotion** — `/promote-memory` reads `working.md`, asks domain-or-project, captures a one-line summary, archives the old `working.md`, regenerates `index.md`.
- **Graduation** — manual. When a domain file matures into a reusable pattern, package it as a Claude Code skill.

### Domain vs. skill

A **domain file is knowledge** (something an agent *knows*); a **skill is a capability** (something an agent *does*).

| | `domain/<topic>.md` | Skill |
|---|---|---|
| Purpose | Durable cross-project knowledge — conventions, gotchas, decisions | A repeatable procedure/capability |
| Content | Descriptive markdown + frontmatter | Procedural instructions, often with bundled scripts/templates |
| How it's reached | Lazy read — its row in `index.md` (Claude) / the Domain Index in `AGENTS.md` (Codex) matches your request's triggers, then the agent opens the file | Invoked — auto-discovered via its `description`, or called explicitly; its instructions are loaded and followed |
| Lives in | The memory tree (`domain/`) | The agent's skill system — Claude Code skills, or Codex `~/.codex/skills/` (e.g. the `checkpoint` skill) |

They sit on one maturation path: `working.md` (scratch) → `domain/*.md` (stable knowledge) → skill (reusable procedure). Not every domain file graduates — most stay as reference; graduation is deliberate, since a skill is heavier (structured, versioned, broadly triggered). Often the two coexist and point at each other: a short `domain/<topic>.md` records the facts and *points to* the skill(s) that hold the detailed procedure. **Rule of thumb:** a *fact you want to recall* → domain file; a *procedure you want to re-run* → skill. Because skills are per-agent, a cross-agent procedure may need both a Claude skill and a Codex skill sharing the same domain file as source of truth.

Not every skill graduates from a domain file, either. The `brainstorming` skill (see [Skills](#skills)) was authored directly as a Claude-only, orchestrator-only capability — it encodes a procedure (the Tier-3-feature design pass) that never existed as cross-project *knowledge*, so it has no `domain/*.md` source and gets no index row. Authoring a skill outright is fine when the thing is a procedure from the start; the maturation path is the common case, not the only one.

---

## Task-provider layer

A small Python (stdlib-only) subsystem that lets the memory system **capture tasks, track coarse status, and execute them later**, with a swappable storage backend behind a fixed, backend-neutral interface. It lives at `scripts/taskprovider/` and is reached only through a JSON CLI, so bash and future slash commands call it without knowing the implementation language. **It is opt-in: nothing runs it unless invoked** — `inject_memory.sh` and the offline hot path never touch it.

### The model — backend is a projection, not a co-source-of-truth

The memory tree owns all detail: the **plan file** and its `todo.md` checkboxes. The task backend owns only **intent + coarse status** — a thin record of `title + summary + status + project`. Sync is at the **plan level** (one backend task ↔ one plan file), **push-dominant** (the memory system drives status), and **never bidirectional field-by-field**. A genuine conflict is *flagged*, not auto-resolved — the same posture as repo-path drift in lint.

**Nothing is materialized in the memory tree until `start`.** A captured task is backend-resident only (no plan stub, no `todo.md` row, no index entry). The backlog lives in the backend; the memory tree holds only started-or-later work.

```
backlog ──start──▶ started ──▶ done ──▶ archived      (canonical statuses)
CAPTURED (backend only, no plan yet)   STARTED (plan file exists, linked)
```

### The contract

`TaskProvider` (`contract.py`) is an ABC speaking **only the memory system's vocabulary** — `project, title, summary, canonical status, ref`. It never mentions any backend's concepts (page ids, query shapes, workflow transitions). Members:

| Member | Role |
|--------|------|
| `capture(project, title, summary) -> ref` | Create a backlog task; returns an opaque `ref`. |
| `list(project, status) -> [Task]` | Tasks for a project in a canonical status. |
| `get(ref) -> Task` | One task, all fields. |
| `update(ref, *, title=None, summary=None)` | **Title/summary only** — the narrow channel for refining the thin record (e.g. pushing the sharpened summary at `/start`). Deliberately *not* a general field writer. |
| `set_status(ref, status)` | Move along the lifecycle; non-canonical status is rejected **before** any provider dispatch. |
| `ping() -> bool` | Backend reachable? |
| `status_map` (seam) | canonical ↔ native status. Identity for local; option names for Notion; **workflow transitions** for Jira. |
| `resolve_project(name) -> handle` (seam) | memory project → native handle. Local checks `projects/<name>/`; Notion uses a text property; Jira a pre-existing key that may legitimately fail. |
| `add_progress(ref, note)` | **Designed, not wired.** Non-abstract **default no-op** so backends opt in. A one-directional, append-only, *summary-level* digest pushed outward at `/checkpoint` (never the full Done/Next/Blockers — those stay in `working.md`). Implemented with the checkpoint wiring later. |

`Task` is an immutable dataclass: `ref, project, title, summary, status, created`. The canonical status set `{backlog, started, done, archived}` is defined once. `task_ref` is **opaque to the core** — never parsed.

The two seams (`status_map`, `resolve_project`) are where backends genuinely differ — near-zero for local, heavy for Jira. Keeping them explicit members is what makes the abstraction real rather than cosmetic.

### Choosing a backend

`MEMORY_TASK_PROVIDER` selects the backend (default `local`). This is a **deliberate per-machine choice, never auto-failover** — a machine without Notion configured runs local, full stop; silently falling back Notion→local would re-create the split-brain this design exists to avoid. The factory is a generic registry: the env value *is* the provider module name under `taskprovider.providers.*`, instantiated via its module-level `PROVIDER` class — so adding a backend needs **no factory edit**.

### Local store (`FileTaskProvider`)

The always-available default. Tasks are **flat** at `$MEMORY_DIR/tasks/<slug>.md` (not per-project — mirrors one Notion database with a `Project` property), each carrying `project`, `status`, `created` frontmatter and the summary as body. **Status lives only in frontmatter — no status-named subfolders** (encoding status in the path duplicates the fact and invites drift). `done` is an in-place frontmatter flip; **only `archived` moves the file** (to `$MEMORY_DIR/archive/tasks/`) — mirroring `/plan-done` vs `/plan-archive`. `MEMORY_DIR` is the only location knob.

### Notion provider (`NotionProvider`)

The first remote backend, same contract, **zero changes** to the contract/CLI/factory/local code (proven by checksum). Uses `urllib.request` only (no `requests`), `Notion-Version: 2025-09-03` (data-source query `POST /v1/data_sources/{id}/query`, page create `POST /v1/pages` parented by `data_source_id`, status/field via `PATCH /v1/pages/{id}`). Reads `NOTION_TOKEN` + `NOTION_DATA_SOURCE_ID` from env — **no secrets in code or the tree**. All backend-specific strings are isolated to `providers/notion.py` (verifiable by grep).

#### Notion setup

**1. The database schema the provider expects.** The target Notion data source must carry these properties (names are the constants in `providers/notion.py`):

| Property | Type | Role |
|----------|------|------|
| `Name` | title | task title |
| `Summary` | rich text | the thin summary (refined Goal at `/start`) |
| `Project` | rich text (**not** select) | the memory project name — text so unknown projects validate rather than failing silently |
| `Status` | status **or** select | lifecycle — option names must match the `status_map` (see below) |
| `Claude` | checkbox | the **consume tag** — `list` only returns `Claude = true` rows, so your own cards stay invisible to the provider |
| `Created` | created time | optional — falls back to the page's `created_time` if absent |

**2. `data_source_id`, not database id.** In the 2025-09-03 API a database is a *container* of data sources; pages live in a data source. Resolve it once:
```bash
curl -s https://api.notion.com/v1/databases/<DATABASE_ID> \
  -H "Authorization: Bearer $NOTION_TOKEN" -H "Notion-Version: 2025-09-03" \
| python3 -c 'import sys,json; print([(x["id"],x.get("name")) for x in json.load(sys.stdin)["data_sources"]])'
```
Take the inner id → `NOTION_DATA_SOURCE_ID`. (Get the database id from the DB URL; share the database with your integration first.)

**3. Status mapping + `NOTION_STATUS_KIND`.** `status_map` maps canonical → native option names: `backlog→Backlog`, `started→In-progress`, `done→Done`, `archived→Archived` (edit the map in `notion.py` to match your board's option labels). If your `Status` property is a **select** (not a Notion *status*-type), set `NOTION_STATUS_KIND=select` (default `status`) — it drives both the write value shape and the query-filter key; the read side handles either. **Notion API limitation:** you can *add* and *reorder* select options but **cannot rename or delete** them via the API (rename = add new + reorder + leave the old vestigial; delete is UI-only).

**4. Env, and the `.zshenv` gotcha.** Selecting Notion is a per-machine env choice:
```bash
# put these in ~/.zshenv (NOT ~/.zshrc)
export MEMORY_TASK_PROVIDER=notion
export NOTION_STATUS_KIND=select          # only if Status is a select
export NOTION_DATA_SOURCE_ID=<data source id>
export NOTION_TOKEN=<integration secret>
```
**Must be `~/.zshenv`, not `~/.zshrc`:** `/task` and `/start` run through Claude's Bash tool, a *non-interactive* zsh, which sources `.zshenv` only (`.zshrc` is interactive-only) — env in `.zshrc` is invisible to the commands. Verify with `scripts/taskctl ping` → `{"ok": true}`.

### CLI boundary

```bash
PYTHONPATH=$MEMORY_DIR/scripts python3 -m taskprovider <verb> ...
# verbs: capture | list | get | update | set-status | ping
```

Prints **JSON to stdout**, signals errors via **exit code** (+ a JSON `{"error": ...}` object). This language-agnostic seam means the Python layer is itself swappable later without touching any caller. The `scripts/taskctl` bash wrapper removes the `PYTHONPATH`/`-m` boilerplate (`taskctl <verb> ...`) and is what the `/task` and `/start` commands call — note it sets `PYTHONPATH` to the package dir while `MEMORY_DIR` stays the independent data root, so a temp/synced data root still imports the real package.

### Adding a provider

Implement the five methods + the two seams in `scripts/taskprovider/providers/<name>.py`, expose `PROVIDER = <YourClass>`, keep all backend vocabulary inside that one file. **Nothing else changes** — not the contract, not the CLI, not the factory. Set `MEMORY_TASK_PROVIDER=<name>`.

**Design check — Jira fits unchanged.** Jira's status change is a *workflow transition*, which `set_status` already allows (it may be more than a field write internally — that's the `status_map` seam's job); its project is a *pre-existing key* that cannot be created on the fly and may legitimately fail — exactly what `resolve_project` is allowed to do. No contract change needed. **A `dropped` status** would be added as one more canonical entry + one `status_map` row per provider — also no contract change.

### `/start` — capture-to-plan, with the brainstorm gate

Tasks reach the memory tree through two commands above the CLI: **`/task`** captures/manages backlog tasks (thin record only); **`/start`** turns a captured task into real plan + todo. The tier classification runs **at start time** against the pulled summary (a captured task carries no tier yet):

- Captured **feature with open design** → `/start` hands the pulled summary to the [`brainstorming`](#skills) skill as its seed (clarify → approaches → sectioned design); the design folds into the plan's `## Goal`/`## Design`/`## Success criteria`/`## Risks`; the linking step writes `task_provider`/`task_ref` into the plan frontmatter, pushes the brainstorm's clarified **`## Goal`** back as the refined summary via `update`, and flips status `backlog → started`.
- Captured **quick/settled** task → skip the brainstorm, scaffold the plan directly.

`/start` is **project-agnostic** — a `ref` is globally unique in the flat store, so it reads the task's own `project` from `get` and scaffolds the plan into *that* project (not the active one), which is why it owns plan placement rather than calling `/new-plan` (which targets the active project). The provider layer stays **oblivious** to all of this — nothing in the contract, CLI, factory, or any provider references brainstorming, tiers, or plans. The seam lives entirely in the `/task`/`/start` command instructions + the `scripts/taskctl` wrapper.

### Testing

`scripts/taskprovider/tests/` (Python `unittest`, temp-dir fixtures) covers the contract, the full local lifecycle (`capture→update→started→done→archived`), and Notion offline (canned fixtures, monkeypatched HTTP). A **gated live Notion smoke** runs the same lifecycle against a real scratch data source only when `NOTION_TOKEN` + `NOTION_TEST_DATA_SOURCE_ID` are set, and is **skipped (not failed)** otherwise. A bash CLI integration test (`scripts/tests/test_taskprovider_cli.sh`) runs in the existing harness. Everything offline passes with **no network and no credentials**.

## Scripts reference

| Script | Purpose | Common invocations |
|--------|---------|---------------------|
| `codex-mem.sh` | Build AGENTS.md + run codex | `codex-mem.sh`, `codex-mem.sh exec --sandbox read-only "..."` |
| `codex-mem-checkpoint.sh` | Emit checkpoint scaffold | TTY → opens `$EDITOR`; `--for-codex` → stdout for Codex to consume |
| `regenerate-index.sh` | Rebuild `index.md` AUTOGEN block | `regenerate-index.sh` (idempotent) |
| `lint-memory.sh` | Mechanical lint | exit 0 if clean, 1 if any WARN/ERROR |
| `archive-cleanup.sh` | Prune old `archive/` files | `archive-cleanup.sh [--all-projects] [--days N]` (dry-run, then confirm) |
| `new-project.sh` | Scaffold a new project (pin a repo with `.claude/memory-project` to activate) | `new-project.sh <name>` |
| `memory-pin.sh` | Pin a checkout ↔ project (forward marker + reverse `repo`/`repo_path`) | `memory-pin.sh <name>` (run from inside the checkout) |
| `_lib.sh` | Shared helpers (sourced) | `detect_active_project`, `extract_fm_field`, `projects_root`, `resolve_repo_path` |
| `taskctl` | Bash wrapper for the task-provider CLI (used by `/task`, `/start`) | `taskctl <capture\|list\|get\|update\|set-status\|ping> ...` |
| `taskprovider/` | Python (stdlib-only) task-provider CLI — see [Task-provider layer](#task-provider-layer) | `PYTHONPATH=$MEMORY_DIR/scripts python3 -m taskprovider <verb>`; tests: `cd scripts && python3 -m unittest discover -s taskprovider/tests -t .` |
| `tests/*` | Dependency-free shell tests (bash 3.2) | `for t in scripts/tests/test_*.sh; do bash "$t"; done` |

All scripts target macOS `bash` 3.2 (no `mapfile`, no associative arrays) and resolve the memory tree via `MEMORY_DIR`. Each test sets `MEMORY_DIR` (and, for the hook, `MEMORY_SESSIONS_DIR`) to a `mktemp -d` sandbox so the suite never touches real memory.

Environment overrides:

| Var | Default | Used by |
|-----|---------|---------|
| `MEMORY_DIR` | repo root (self-locating); `~/.claude-memory` when installed | All scripts |
| `AI_MEMORY_PROJECTS_ROOT` | `$HOME/Projects` | `memory-pin.sh`, `resolve_repo_path`, `lint-memory.sh` |
| `config.local.sh` (file, not a var) | unset — copy from `.example` | Sourced by `_lib.sh` + `taskctl` for per-env overrides |
| `CODEX_INSTRUCTIONS_FILE` | `~/.codex/AGENTS.md` | `codex-mem.sh` |
| `CODEX_OVERLAY_FILE` | `~/.codex/AGENTS.local.md` | `codex-mem.sh` |
| `CODEX_HISTORY_FILE` | `~/.codex/history.jsonl` | `codex-mem-checkpoint.sh` |
| `CODEX_HISTORY_LINES` | `20` | `codex-mem-checkpoint.sh` |
| `MEMORY_STALE_DAYS` | `30` | `lint-memory.sh` |
| `MEMORY_ARCHIVE_RETAIN_DAYS` | `30` | `archive-cleanup.sh` |
| `MEMORY_SESSIONS_DIR` | `~/.claude/memory_sessions` | `inject_memory.sh` |
| `MEMORY_TASK_PROVIDER` | `local` | task-provider factory (`local`/`notion`) — see [Task-provider layer](#task-provider-layer) |
| `NOTION_TOKEN` | — | `NotionProvider` (integration secret; set in `~/.zshenv`) |
| `NOTION_DATA_SOURCE_ID` | — | `NotionProvider` (the data-source id, not the database id) |
| `NOTION_STATUS_KIND` | `status` | `NotionProvider` — set `select` if the board's `Status` is a select property |

---

## File format conventions

### Frontmatter (required on every domain + project memory file)

**Domain file:**

```yaml
---
topic: terraform
triggers: [tf, hcl, terraform, module, state, provider, fmt, validate]
summary: Module conventions, state backend gotchas, fmt/validate workflow
---
```

**Project memory file:**

```yaml
---
topic: <project-name>
scope: project
summary: One-line description for the index
repo: git@github.com:org/repo.git    # optional — git remote (portable fallback id)
repo_path: repo                      # optional — checkout path relative to AI_MEMORY_PROJECTS_ROOT (may be absolute)
tags: [terraform, aws, eks]          # optional — recall hints; live in memory.md, not the index
---
```

`topic`/`scope`/`summary` are required; `lint-memory.sh` flags files missing any of them. `repo`/`repo_path`/`tags` are optional — validated only when present (absence is never an error), and normally written by `memory-pin.sh`, not by hand. `summary` stays the index description; there is no separate `description` field.

### Project memory sections (required)

The template enforces five sections; lint complains if any is missing:

```
## What It Is             — what the project is, stack, ownership, scale
## Current State          — deployed/stable vs in-flight (last ~30 commits)
## Architecture Decisions — locked-in choices and explicit non-goals
## Known Constraints / Gotchas — landmines, load-bearing hacks
## Current Goal           — active milestone, one thing only
```

`## Decisions Log` is appended by `/promote-memory` when promoting to a project (not in the template).

**Optional `## Related Projects`.** The template carries a commented-out `## Related Projects` block after the five required sections. Uncomment it only when this project's work spans into others; it holds the relationship table described in [Cross-project relationships](#cross-project-relationships). Because it's HTML-commented in the template, it stays inert for the lint section check until you uncomment it.

```markdown
<!-- Uncomment only if this project's work spans into other projects.
## Related Projects

| Project | When it's involved | It owns / entry point |
|---------|--------------------|------------------------|
| <other-project> | <trigger condition> | <what it owns — entry file/path> |

> Ordering: <cross-repo sequencing, if any>
-->
```

### Domain file body

Just `## Knowledge`. Entries append as `**[YYYY-MM-DD]** what — why it matters`.

### `working.md` shape

```markdown
# Working — <project>

## Cross-project learnings (pending promotion)

- <rule or fact>
  - **Why:** <reason>
  - **How to apply:** <when this kicks in>

## Checkpoints

### YYYY-MM-DD — <task summary>

**Task:** <one sentence>

**Done:**
- <bullet>

**Next:**
- <bullet>

**Blockers:**
- <bullet or None>
```

New checkpoints append at the bottom of `## Checkpoints` (newest last). `/checkpoint` synthesizes all four fields from the current session's context — it does not interview you. If a session produced no artifacts, the entry should say so honestly (e.g. `**Done:** Discussion only — no artifacts produced`).

---

## Common workflows

### Start a new engagement

```bash
~/.claude-memory/scripts/new-project.sh acme-migration
# Pin a repo to it:
cd ~/code/acme-migration && mkdir -p .claude && echo acme-migration > .claude/memory-project
# Edit projects/acme-migration/memory.md — replace template placeholders.
```

### Switch / set the global fallback explicitly

Pin-first is the recommended model — pin a repo once and any session opened anywhere in it auto-loads the project:

```bash
cd /path/to/repo && mkdir -p .claude && echo fiter-charts > .claude/memory-project
```

There is no global active-project fallback. An unpinned cwd loads no project, so multiple sessions in different repos run concurrently without colliding on a shared default. Pin each repo you want memory in.

### Capture a learning mid-session

- **Claude**: just say "remember that X" — maintenance rules route it.
- **Codex**: `/checkpoint` (captures plus pulls cross-project learnings out into the right section).

### Promote a learning

```
/promote-memory
```

Asks: domain or project? If "new" domain, prompts for triggers + summary, seeds a properly frontmatter'd file. Archives `working.md` and regenerates `index.md`.

### Periodic maintenance

Run when memory feels dusty (monthly, or before a long break):

```
/lint-memory       # Content quality: contradictions, stale paths, orphans, template gaps
/reindex           # Rebuild the index from frontmatter (also runs after /promote-memory)
```

For deeper cleanup (dedup, merge, split files): tell Claude "reorganize memory" — see the procedure in `~/.claude/CLAUDE.md`.

---

## Troubleshooting

| Symptom | Cause / Fix |
|---------|-------------|
| Memory not injected in Claude session | Hook didn't fire. Check `~/.claude/settings.json` registers it and `~/.claude/hooks/inject_memory.sh` is executable. Confirm output is `hookSpecificOutput.additionalContext` JSON. Working memory only injects when non-empty. |
| Identity re-injected every prompt | The per-session marker isn't being written. Confirm `~/.claude/memory_sessions/` is writable and the hook can parse `session_id` from stdin. |
| Codex doesn't see project memory | `codex-mem.sh` couldn't resolve the project. Pin the repo with `.claude/memory-project` (launch from inside the repo tree). |
| Cross-project delegate (Codex) sees the wrong project | A `codex-mem.sh` executor resolves `AGENTS.md` from the *active* project. Pin the sibling repo before launching, or pass the sibling `memory.md` path in the prompt. |
| `~/.codex/AGENTS.md` looks stale | It's only regenerated when you launch via `codex-mem.sh`. Plain `codex` reads the existing file as-is. |
| Local Codex instructions vanished | You edited `~/.codex/AGENTS.md` (generated, overwritten). Move your additions to `~/.codex/AGENTS.local.md`. |
| `index.md` doesn't reflect a new file | Frontmatter missing or malformed. Run `lint-memory.sh`. Then `regenerate-index.sh`. |
| Bash heredoc fails under Codex `read-only` sandbox | Heredocs need writable `/tmp`. Use `printf` + double-quoted strings in any script that may run under restrictive sandboxes. |
| Slash command not autocompleting | Restart the Claude session — slash commands in `~/.claude/commands/` are indexed at session start. |
| `TaskCreate`/`TaskUpdate` not blocked | `block_task_tools.sh` missing from `settings.json` `PreToolUse`, not executable, or matcher typo. The matcher must be `TaskCreate\|TaskUpdate`. |

---

## Memory governance

- `archive/` is the audit trail (plans, todos, working-memory snapshots). **Never delete it** during a "reorganize memory" pass.
- The directory is **not git-managed** by design — treat as personal, never commit secrets.
- `_template` is excluded from index, lint, and regeneration. Edit it when changing the project scaffold.
- Frontmatter is the contract. Skipping it breaks the index and the Codex Domain Index. Lint catches it.

---

## Design rationale

- **Markdown over a DB:** every editor, every diff tool, every grep works on it. No infra.
- **Hook-injected, not retrieved:** Claude doesn't need to "remember to look" — context arrives in-band via `additionalContext` on the first prompt of each session. Codex gets the equivalent via a generated `AGENTS.md`.
- **Per-session injection markers:** once-per-session blocks are tracked per `session_id` under `memory_sessions/`, so concurrent Claude sessions don't re-inject, and dead markers self-expire after 2 days.
- **Distributed cross-project relationships:** a relationship lives in the project where the work starts (`## Related Projects`), and siblings are delegated to executors, never preloaded — so a multi-repo sequence is coordinated without resident sibling memory.
- **Enforced, not just documented, where it matters:** the task-tool block is a real `PreToolUse` deny and the executor infra-deny is a real codex execpolicy rule — load-bearing conventions are backed by mechanism.
- **Tested scaffolding:** the `scripts/tests/` suite pins script behavior (index-regen idempotence, lint failure modes, scaffold-only new-project, hook output contract, AGENTS.md build order) so a rebuild can be verified, not assumed.
- **Frontmatter-driven catalog:** the index never lags behind the files. Adding a new domain file is one drop + one regen.
- **Index is a path-less roster:** `index.md` carries only names/topics + summaries — no file paths, no per-project metadata. Paths are derivable (`projects/<name>/memory.md`, `domain/<topic>.md`), and metadata (`tags`/`repo_path`/`repo`, domain `triggers`) lives in the source file. The active project's memory is auto-injected; everything else is loaded on demand by deriving its path. (Codex's `AGENTS.md` domain index keeps absolute paths — its shell tool reads by path.)
- **Lazy domain loads in Codex:** the index is in the system prompt; the bodies are read on demand. Scales as `domain/` grows without bloating every Codex session.
- **One-way reverse sync from Codex:** the `/checkpoint` skill captures Codex session takeaways back into `working.md`, so insights don't die in `logs_2.sqlite`.
- **Two operations distinguished:** *reorganize* is structural (dedup, merge, split). *Lint* is content-quality (contradictions, staleness, orphans). They live separately because they fail differently.
