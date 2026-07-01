# Memory System

A markdown-only memory tree shared by **Claude Code** and **OpenAI Codex CLI** — no vector DB, no daemons, no MCP servers, just files, hooks, and short shell scripts. Insight captured in one agent is visible to the other on the next session, and it compounds: every non-trivial synthesis gets offered for filing.

## Mental model

Three layers, mirroring Karpathy's LLM Wiki pattern:

1. **Schema** — hard rules and behavioral conventions. `identity.md`, `~/.claude/CLAUDE.md`. Outranks everything.
2. **Wiki** — durable, LLM-readable knowledge. `domain/*.md` (cross-project) + `projects/*/memory.md` (per-engagement).
3. **Scratchpad** — in-flight, per-project. `projects/*/working.md`. Matures into the wiki via `/promote-memory`.

Claude reads memory in-band (a `UserPromptSubmit` hook injects `<memory:*>` blocks); Codex reads the same files via a generated `~/.codex/AGENTS.md`. The index is auto-generated from frontmatter, so it can't lag the files.

> **Two-Path principle.** The store is plain markdown first; scripts are conveniences, never the only way in. Every script action has a hand-editable equivalent producing the same on-disk result — `/checkpoint` writes `working.md`, but so can you. Never invent a format only a tool can read.

## Install

This repo **is** the memory tree. Clone it and run the installer — it links the Claude Code wiring (hooks, slash commands, skills, agents) into `~/.claude/` and points `~/.claude-memory` at the clone.

```bash
git clone https://github.com/seyio91/ai-memory-system.git ~/.claude-memory
cd ~/.claude-memory
./install.sh
```

`install.sh` is idempotent and backs up anything it overwrites. Two steps it leaves to you (merge hook settings; symlink `CLAUDE.md`) and the full breakdown are in **[docs/install.md](docs/install.md)**. Then edit `identity.md`, pin a repo with `/pin <project>`, and start a session.

## What you get

- **Context on tap** — active project's memory, hard rules, and index arrive automatically each session; domain knowledge loads lazily when your task matches its triggers.
- **One memory, two agents** — Claude and Codex read and write the same tree; `/checkpoint` in either captures state for the other.
- **A capture→plan→execute workflow** — capture tasks (`/task`), turn them into plans through a design gate (`/start` → `brainstorming`), and run them through an orchestrator/executor/validator loop with a selectable executor backend.
- **Enforced conventions** — the `todo.md`-only rule and the executor infra-deny are real hooks/execpolicy, not just documentation.
- **Tested, dependency-free scaffolding** — bash-3.2 scripts with a `scripts/tests/` suite, so a rebuild can be verified.

## Docs

| Page | What's in it |
|------|--------------|
| [docs/install.md](docs/install.md) | Install, rebuilding the wiring by hand, directory layout, project detection & the reverse (project→checkout) map |
| [docs/harnesses/claude.md](docs/harnesses/claude.md) | Claude Code: auto-injection, hooks, slash commands, skills, the skill write-boundary & self-rating loop |
| [docs/harnesses/codex.md](docs/harnesses/codex.md) | Codex CLI: the `codex-mem.sh` bridge, what lands in `AGENTS.md`, the local overlay, `/checkpoint` in Codex |
| [docs/workflow.md](docs/workflow.md) | Orchestrator / Executor / Validator roles, the Task Contract, executor selection, cross-project relationships |
| [docs/task-provider.md](docs/task-provider.md) | The pluggable task backend (local + Notion), the contract, `/start`, adding a provider |
| [docs/file-formats.md](docs/file-formats.md) | Frontmatter, the required project-memory sections, `working.md` shape, domain-file body |
| [docs/scripts.md](docs/scripts.md) | Every script + its invocations, and the environment-override table |
| [docs/knowledge-lifecycle.md](docs/knowledge-lifecycle.md) | working → domain → skill maturation, domain-vs-skill, governance, design rationale |
| [docs/workflows.md](docs/workflows.md) | Common workflows (new engagement, capture, promote, maintenance) and troubleshooting |

## Layout at a glance

```
identity.md              Hard rules (injected once per session)
index.md                 Auto-generated roster of projects + domains
domain/<topic>.md        Cross-project knowledge (lazy-loaded on trigger match)
projects/<name>/         memory.md · working.md · todo.md · plans/ · archive/
claude/                  Claude Code wiring (hooks, commands, CLAUDE.md) → ~/.claude
skills/  ·  agents/       Bundled skills + subagents → ~/.claude
scripts/                 Bash engine + the Python task-provider package
```

Full tree and the `~/.claude` / `~/.codex` symlink maps: **[docs/install.md](docs/install.md#directory-layout)**.

---

*Committed: the engine (`scripts/`, `claude/` wiring, `skills/`, `agents/`, `*.template.md`). Git-ignored: your data (`index.md`, `domain/*`, `projects/*` except `_template/`, `tasks/`, `archive/`). See `.gitignore`.*
