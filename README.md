# Memory System

A markdown-only memory tree shared by **Claude Code**, **OpenAI Codex CLI**, and **Antigravity** — no vector DB, no daemons, no MCP servers, just files, hooks, and short shell scripts. Insight captured in one agent is visible to the other on the next session, and it compounds: every non-trivial synthesis gets offered for filing.

## Mental model

Three layers, mirroring Karpathy's LLM Wiki pattern:

1. **Schema** — hard rules and behavioral conventions. `identity.md`, `~/.claude/CLAUDE.md`. Outranks everything.
2. **Wiki** — durable, LLM-readable knowledge. `domain/*.md` (cross-project) + `projects/*/memory.md` (per-engagement).
3. **Scratchpad** — in-flight, per-project. `projects/*/working.md`. Matures into the wiki via `/promote-memory`.

Claude and Antigravity read memory in-band — a `UserPromptSubmit` / `PreInvocation` hook injects `<memory:*>` blocks live each turn; Codex reads the same files via a generated `~/.codex/AGENTS.md`. The index is auto-generated from frontmatter, so it can't lag the files.

> **Two-Path principle.** The store is plain markdown first; scripts are conveniences, never the only way in. Every script action has a hand-editable equivalent producing the same on-disk result — `/checkpoint` writes `working.md`, but so can you. Never invent a format only a tool can read.

## Install

This repo **is** the memory tree. Clone it and run the installer — a generic, **manifest-driven** engine that wires whichever harness you name (`--harness claude | codex | antigravity`) or auto-detects one, and points `~/.claude-memory` at the clone. It's agent-runnable: an agent inside any harness can run it to wire that harness up.

```bash
git clone https://github.com/seyio91/ai-memory-system.git ~/.claude-memory
cd ~/.claude-memory
./install.sh
```

`install.sh` is idempotent and backs up anything it overwrites. Two steps it leaves to you (merge hook settings; symlink `CLAUDE.md`) and the full breakdown are in **[docs/install.md](docs/install.md)**. Then edit `identity.md`, pin a repo with `/pin <project>`, and start a session.

Upgrade instances with `scripts/sync-system.sh`; it syncs to the latest stable tag by default and aborts until the first stable `v*` tag exists. Set `AI_MEMORY_CHANNEL=dev` in `config.local.sh` on the source checkout, otherwise that checkout also defaults to `release` and will detach at the latest tag once one exists.

## What you get

- **Context on tap** — active project's memory, hard rules, and index arrive automatically each session; domain knowledge loads lazily when your task matches its triggers.
- **One memory, every agent** — Claude, Codex, and Antigravity read and write the same tree; `/checkpoint` in any captures state for the others.
- **A capture→plan→execute workflow** — capture tasks (`/task`), turn them into plans through a design gate (`/start` → `brainstorming`), and run them through an orchestrator/executor/validator loop with a selectable executor backend (write `task` and read-only `explore` roles, resolved per harness).
- **Enforced conventions** — the `todo.md`-only rule (a Claude PreToolUse hook) and the executor infra-deny (Codex execpolicy, Antigravity `PreToolUse` guard) are real gates, not just documentation.
- **Memory-aware statusline** — Claude and Antigravity show the active project + folder + git/model/context state right in the prompt.
- **Tested, dependency-free scaffolding** — bash-3.2 scripts with a `scripts/tests/` suite, so a rebuild can be verified.

## Docs

| Page | What's in it |
|------|--------------|
| [docs/install.md](docs/install.md) | Install, rebuilding the wiring by hand, directory layout, project detection & the reverse (project→checkout) map |
| [docs/harnesses/claude.md](docs/harnesses/claude.md) | Claude Code: auto-injection, hooks, slash commands, skills, the skill self-rating loop |
| [docs/harnesses/codex.md](docs/harnesses/codex.md) | Codex CLI: the `codex-mem.sh` bridge, what lands in `AGENTS.md`, the local overlay, `/checkpoint` in Codex |
| [docs/harnesses/antigravity.md](docs/harnesses/antigravity.md) | Antigravity (`agy`): live `PreInvocation` injection, the `PreToolUse` enforcement guard + read-only executor, skills/commands via `~/.agents/skills`, the memory-aware statusline |
| [docs/harnesses/adding-a-harness.md](docs/harnesses/adding-a-harness.md) | Register a new harness by manifest — archetype, surfaces, launch wrapper, detection |
| [docs/workflow.md](docs/workflow.md) | Orchestrator / Executor / Validator roles, the Task Contract, executor selection, cross-project relationships |
| [docs/task-provider.md](docs/task-provider.md) | The pluggable task backend (local + Notion), the contract, `/start`, adding a provider |
| [docs/file-formats.md](docs/file-formats.md) | Frontmatter, the required project-memory sections, `working.md` shape, domain-file body |
| [docs/scripts.md](docs/scripts.md) | Every script + its invocations, and the environment-override table |
| [docs/knowledge-lifecycle.md](docs/knowledge-lifecycle.md) | working → domain → skill maturation, domain-vs-skill, governance, design rationale |
| [docs/workflows.md](docs/workflows.md) | Common workflows (new engagement, capture, promote, maintenance) and troubleshooting |
| [CHANGELOG.md](CHANGELOG.md) | Release notes |
| [UPGRADING.md](UPGRADING.md) | Channel model, rollback behavior, semver, and migration notes |

## Layout at a glance

```
identity.md              Hard rules (injected once per session)
index.md                 Auto-generated roster of projects + domains
domain/<topic>.md        Cross-project knowledge (lazy-loaded on trigger match)
projects/<name>/         memory.md · working.md · todo.md · plans/ · archive/
harnesses/<name>/        Per-harness wiring + manifest (claude · codex · antigravity)
skills/  ·  agents/       Bundled skills + subagents (→ ~/.claude, ~/.agents/skills)
migrations/              Forward-only instance migrations
scripts/                 Bash engine (install · drivers · formatters) + Python task-provider
CHANGELOG.md             Release notes
UPGRADING.md             Upgrade contract + per-version notes
install.sh               Manifest-driven, agent-runnable installer
```

Full tree and the `~/.claude` / `~/.codex` symlink maps: **[docs/install.md](docs/install.md#directory-layout)**.

---

*Committed: the engine (`scripts/`, `harnesses/` wiring, `skills/`, `agents/`, `install.sh`, `*.template.md`) plus the self-documenting `projects/ai-memory` meta-project. Git-ignored: your data (`index.md`, `domain/*`, `projects/*` except `_template/` and `ai-memory`, `config.local.sh`, `tasks/`, `archive/`). See `.gitignore`.*
