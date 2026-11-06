# Memory System

[![tests](https://github.com/seyio91/ai-memory-system/actions/workflows/tests.yml/badge.svg?event=pull_request)](https://github.com/seyio91/ai-memory-system/actions/workflows/tests.yml)

A markdown-only memory tree shared by **Claude Code**, **OpenAI Codex CLI**, **GitHub Copilot CLI**, and **Antigravity** — no vector DB, no daemons, no MCP servers, just files, hooks, and short shell scripts. Insight captured in one agent is visible to the others on the next session, and it compounds: every non-trivial synthesis gets offered for filing.

## Mental model

Three layers, mirroring Karpathy's LLM Wiki pattern:

1. **Schema** — hard rules and behavioral conventions. `identity.md`, `orchestrator.local.md`, the tracked `doctrine/orchestrator.md` core (`~/.claude/CLAUDE.md` is only a hook-failure fallback stub). Outranks everything.
2. **Wiki** — durable, LLM-readable knowledge. `domain/*.md` (cross-project) + `projects/*/memory.md` (per-engagement).
3. **Scratchpad** — in-flight, per-project. `projects/*/working.md`. Matures into the wiki via `/promote-memory`.

Every harness reads memory in-band through native hooks: the full tree injects as `<memory:*>` blocks at session start, and a per-turn hook (`UserPromptSubmit` on Claude and Codex, `PreInvocation` on Antigravity) keeps a breadcrumb live; Copilot gets the session-start payload plus compaction recovery. `~/.codex/AGENTS.md` is a hand-owned static base the system never writes. The index is auto-generated from frontmatter, so it can't lag the files.

> **Two-Path principle.** The store is plain markdown first; scripts are conveniences, never the only way in. Every script action has a hand-editable equivalent producing the same on-disk result — `/checkpoint` writes `working.md`, but so can you. Never invent a format only a tool can read.

## Install

This repo **is** the memory tree. Clone it and run the installer — a generic, **manifest-driven** engine that wires whichever harness you name (`--harness claude | codex | copilot | antigravity`) or auto-detects one, and points `~/.claude-memory` at the clone. It's agent-runnable: an agent inside any harness can run it to wire that harness up.

```bash
git clone https://github.com/seyio91/ai-memory-system.git ~/.claude-memory
cd ~/.claude-memory
./install.sh
```

`install.sh` is idempotent, backs up anything it overwrites, and needs `python3` 3.9 or later. Any step it leaves to you is printed at the end; the full breakdown is in **[docs/install.md](docs/install.md)**. Then edit `identity.md` and, for any personal workflow rules, `orchestrator.local.md`; pin a repo with `/pin <project>`, and start a session.

Upgrade instances with `scripts/sync-system.sh`. It syncs to the latest stable `v*` tag by default (`AI_MEMORY_CHANNEL=release`), runs pending migrations, and re-runs `install.sh`. Set `AI_MEMORY_CHANNEL=dev` in `config.local.sh` on the source checkout, otherwise it too defaults to `release` and will detach at the latest tag. Converting an existing instance: **[UPGRADING.md](UPGRADING.md#converting-an-existing-instance-to-the-release-channel)**.

## Features

Everything below ships in this repo. Slash commands (`/name`) live in `commands/`, work natively in Claude, and are mirrored to Codex, Copilot and Antigravity as skills; the scripts behind them live in `scripts/`.

### Memory model

- **Markdown-only store** — memory is plain files, not a DB or daemon. Edit, `grep`, `diff`, back up, and recover it with ordinary git and file tools.
- **Three layers** — *schema* (`identity.md` hard rules) → *wiki* (`domain/*.md` cross-project + `projects/*/memory.md` per-engagement) → *scratchpad* (`working.md` in-flight). Each has a defined promotion path upward.
- **Auto-generated index** — `index.md` is rebuilt from frontmatter (`/reindex`), so the catalog of projects and domains can never lag the files.
- **Lazy domain loading** — domain bodies load only when a task's keywords match their frontmatter triggers, so context stays small as knowledge grows.
- **File-format contract** — required frontmatter and sections per file type, checked by `/lint-memory` (contradictions, stale paths, broken repo pins, changelog drift).
- **Archive audit trail** — completed plans, rolled todos, and promoted snapshots move to `archive/` for history; never loaded unless you ask.
- **Two-Path principle** — every scripted action has a hand-editable file equivalent producing the same on-disk result. Never a format only a tool can read.

### One memory, every agent

- **Four harnesses, one tree** — **Claude Code**, **OpenAI Codex CLI**, **GitHub Copilot CLI**, and **Antigravity** read and write the same memory. Insight captured in one is visible to the next.
- **Live injection** — every harness injects `<memory:*>` blocks via native hooks: full payload on session start, a lightweight breadcrumb on ordinary turns. Payloads that exceed a harness's per-hook cap fan out as ordered chunks, and overflow is loud, never silent.
- **Post-compaction recovery** — a per-session sentinel deterministically re-injects the full payload once after a context compaction, on Claude, Codex and Copilot.
- **Manual reload** — `@memory` re-injects the full payload mid-session after you edit memory files.
- **Newest checkpoints first** — the session payload carries only the newest `AI_MEMORY_CHECKPOINT_WINDOW` (default 5) `working.md` checkpoints plus a count of the rest, so truncation can never drop the latest state.
- **Per-worktree overlay** — concurrent sessions in different git worktrees each get their own `working.<key>.md` scratchpad instead of racing on one file.
- **Memory-aware statusline** — Claude, Copilot and Antigravity show active project + folder + git/model/context state right in the prompt.

### Install & harness engine

- **Manifest-driven installer** — `install.sh` reads `harnesses/<name>/manifest` and wires that harness with generic drivers (context, commands, skills, agents, statusline, config). Idempotent; backs up anything it overwrites.
- **Auto-detect or pick** — installs a detected harness or a named one (`--harness claude|codex|copilot|antigravity`); `--list` shows what's registered.
- **Add a harness by manifest** — new harnesses are a manifest + optional wrapper/hook adapter + detection signal, not engine edits. `hook` vs `file` archetype decides live-inject vs generated-context-file.
- **Repo pinning** — `/pin <project>` writes both directions of the map: `.agents/memory-project` in the repo, `repo`/`repo_path` in project memory. Sessions auto-load the right project; tools resolve a project back to its checkout.

### Workflow & orchestration

- **Three-tier routing** — every request is classed research/Q&A, quick edit, or plan-tier. Only plan-tier work gets a plan file, `todo.md`, and delegation — no ceremony on small work.
- **Plan files** — `/new-plan` scaffolds a plan with goal, **success criteria**, design, decisions, phases, and risks: the durable contract for non-trivial work.
- **`todo.md` execution tracking** — the single source of truth for plan-step checkboxes (harness-native task tools are blocked to enforce this).
- **Plan lifecycle** — `/plan-done`, `/plan-archive`, `/todo-archive` move plans and todos through completion into the archive, with guards against archiving unfinished work.
- **Orchestrator / Executor / Validator** — the main agent plans and delegates; executors do scoped work; validators independently check output against the plan's success criteria.
- **Selectable executor backends** — `executor.sh` resolves `task` (write), `explore` (read-only scout), and `validate` (read-only check) roles to the calling harness's subagent plane, Codex, Copilot, Antigravity, or a generic CLI, per harness manifest.
- **Cross-model validation** — the `validate` role defaults to a *different* model from the executor, so CLI-executor output is checked by an independent, read-only invocation by default.
- **Cross-project relationships** — a project can declare related repos; the orchestrator delegates sibling-scoped work rather than loading every sibling's memory into the main thread.
- **Initiatives** — decision streams plus cross-project Targets, with local derived readiness and dependency order rather than another authored status record.
- **Bundled agents** — the `validator` and `auditor` role briefs, plus ready Claude subagents for Azure, DevOps, Kubernetes, and Terraform work.

### Capture → plan → execute

- **`/task` capture** — record intent into a backlog with no plan/todo/index churn; it becomes real work only when you `/start` it.
- **`/start` design gate** — pulls a captured task, classifies it, and for feature-sized work routes through the `design-brainstorm` skill (clarify → compare approaches → fold the approved design into the plan) before scaffolding.
- **Repo-grounded onboarding** — `/new-project` runs the `project-scan` skill read-only against the checkout and drafts `memory.md` from it: links to the repo's own docs, only the commands and conventions no doc states, and cited candidate decisions and gotchas you confirm line by line.
- **Investigations** — long-form pre-start findings live in `projects/<project>/investigations/<slug>.md`, referenced by name so backend task records stay thin, and archived with their task.
- **Feature isolation** — `/start --worktree` routes a feature into its own git worktree so its execution doesn't collide with other in-flight work.

### Task management

- **Pluggable provider** — a backend-neutral interface (capture/list/get/update/status/delete/ping) behind a JSON CLI; add a backend as a self-contained folder under `providers/<name>/` (code + README + setup image), no central switch to edit.
- **Local + Notion backends** — default flat-markdown store in `tasks/`, or a Notion data source mapped to the same contract (properties only, never the page body).
- **Thin task model + summary gate** — backends store only title/summary/status/project/ref/created, with summaries capped at 500 chars; detail belongs in plans and investigations.

### Skills

- **Authored skills** — your own skills in `skills/<name>/`, scaffolded (`new-skill.sh`), imported (`--from`), validated, and linked into each harness.
- **Remote skills** — reference external git-hosted skills in `skills.toml`; content is fetched into a lockfile-pinned `.skill-cache/` (offline replay), never committed. `recurse = true` expands every `SKILL.md` under one repo subpath into separate cached skills.
- **Project-scoped skills** — fan skills from `projects/<project>/skills/` into that project's checkout for Claude and/or Codex.
- **Self-rating loop** — workflow skills can carry a managed self-rating block; `skill-ratings.sh` aggregates scores and improvement notes so skills can be tuned over time.
- **Provenance & listing** — `/list-skills` shows every installed skill with source, synced state, and pin.

### Knowledge lifecycle

- **Checkpoint** — `/checkpoint` (in any harness) captures task/done/next/blockers/resume into the active project's working memory for the next session or agent. One living entry per piece of work: a later session on the same plan, task or PR rewrites it in place and carries every open item forward.
- **Checkpoint archive** — `/checkpoint-archive` rolls superseded and closed entries into `archive/working/`, keeps in-flight ones in place, and flags open items no todo, task or plan tracks.
- **Promote** — `/promote-memory` graduates a scratchpad learning into a domain file, project memory, or a project wiki page (`projects/<project>/wikis/<slug>.md`, linked from `memory.md` Pointers), archives the old note, and reindexes.
- **Maintenance** — `/lint-memory` (mechanical + LLM checks), `/lint-memory --audit <project>` (a read-only agent verifies every `memory.md` claim against the repo and writes a verdict report to `audits/`), `/archive-cleanup` (confirmed, dry-run-first pruning), and `/reindex`.

### Enforcement & safety gates

- **Real gates, not docs** — Claude's `PreToolUse` hook blocks `TaskCreate`/`TaskUpdate` to enforce the `todo.md` rule, and a `PostToolUse` write guard reports memory-file drift after every `Write`/`Edit`.
- **Executor infra-deny** — executors are blocked from destructive/additive infra (`terraform apply`, `kubectl delete`, `helm upgrade`, PR merges) via a shared `scripts/deny-list.txt` and a tokenizing matcher that resists flag/wrapper/quoting bypasses; instance-local rules are additive. `executor.sh --run` prepends the list to every CLI executor prompt and refuses to run without one.
- **Per-harness enforcement** — Claude, Codex, Copilot and Antigravity `PreToolUse` guards apply the same deny list to delegated runs; Antigravity's also adds a read-only allowlist for `explore`/`validate`. On Claude, `AI_MEMORY_GUARD_SCOPE=all` extends the guard to every session: subagents are denied, and the main session is asked to confirm in `default`/`plan`/`acceptEdits` mode and denied in `bypassPermissions` or any other mode, where Claude shows no prompt. Guards **fail closed** for executors and subagents — a missing parser or deny-list is treated as unsafe. A missing `jq`/`python3` denies in every context, the main session included; only a missing or empty deny-list lets Claude's main session fail open, with a visible warning.
- **Protected paths** — guarded contexts (executor roles, Claude subagents) cannot write guard config or plan files (`scripts/protected-paths.txt`, across Bash, `Write`/`Edit`/`NotebookEdit` and Codex `apply_patch`); the deny tells the executor to report instead. The main session is unaffected.
- **Release/sync guards** — `release.sh` refuses to run under an executor role; `sync-system.sh` refuses to change versions on a dirty tracked tree.

### Derived views

- **`/state`** — an on-demand, cross-project table of category, project, last-touched, current goal, and open todos (derived, gitignored, never auto-injected).
- **`/threads`** — the active project's open threads: last checkpoint's next steps and blockers, unclosed open threads, unticked todos, open PRs.
- **`/activity`** — plans created within a time window, grouped by category — useful for review or invoicing since the unit is the plan, not task status.

### Release & upgrade engineering

- **Versioned channel** — `sync-system.sh` upgrades instances to the latest stable `v*` tag (`release`) or fast-forwards `main` (`dev`); `--to <ref>` pins one-shot without changing the channel.
- **Migration runner** — forward-only, idempotent, resumable migrations run in semver order between checkout and reinstall; every version is gated to have an `UPGRADING.md` note.
- **Changelog fragments** — every user-visible PR drops `changelog.d/<id>.<kind>.md` (`breaking`/`feature`/`fix`/`upgrade`); the kinds compute the next version and `assemble-changelog.sh` turns them into the release section deterministically — no notes reconstructed from `git log`.
- **Automated release pipeline** — fragments landing on `main` open a "Release vX.Y.Z" PR (`release-pr.yml`); merging it tags, pushes and publishes the GitHub Release (`release-publish.yml`). The human merge is the only authorization gate. `release.sh --prepare` / `--publish` stay the single implementation — guarded (clean tree, origin agreement, monotonic semver, passing suite) and idempotent on re-run.

### Tooling & quality

- **Dependency-free** — shell + Python stdlib, targeting macOS Bash 3.2, so the system runs as a plain cloned tree. It needs `python3` 3.9 or later (stdlib only, no pip); `jq` is optional. Remote skill resolution (`skills.toml`, `sync-system.sh --update`) needs 3.11+ for `tomllib`. `install.sh` and `sync-system.sh` check this up front.
- **Hermetic test suite** — `run-tests.sh` runs bash tests, Python provider tests, memory lint, skill validation, a doc-vs-code gate, and shellcheck under a scrubbed environment; `/test-system` runs it read-only from Claude.
- **Drift gates** — a doc-vs-code check keeps the `docs/scripts.md` env table honest against the code, and manifest validation runs before any harness is wired.

## Docs

| Page | What's in it |
|------|--------------|
| [docs/install.md](docs/install.md) | Install, rebuilding the wiring by hand, directory layout, project detection & the reverse (project→checkout) map |
| [docs/harnesses/claude.md](docs/harnesses/claude.md) | Claude Code: auto-injection, hooks, slash commands, skills, the skill self-rating loop |
| [docs/harnesses/codex.md](docs/harnesses/codex.md) | Codex CLI: live hook injection (chunked past the per-hook cap), the hand-owned `AGENTS.md` base, the `codex-mem.sh` executor/validator launcher, `/checkpoint` in Codex |
| [docs/harnesses/copilot.md](docs/harnesses/copilot.md) | GitHub Copilot CLI: `sessionStart`/`preToolUse`/`preCompact`/`postToolUse` hooks, the guarded executor face with read-only mode, the statusline |
| [docs/harnesses/antigravity.md](docs/harnesses/antigravity.md) | Antigravity (`agy`): live `PreInvocation` injection, the `PreToolUse` enforcement guard + read-only executor, skills/commands via `~/.agents/skills`, the memory-aware statusline |
| [docs/harnesses/adding-a-harness.md](docs/harnesses/adding-a-harness.md) | Register a new harness by manifest — archetype, surfaces, launch wrapper, detection |
| [docs/workflow.md](docs/workflow.md) | Orchestrator / Executor / Validator roles, the Task Contract, executor selection, cross-project relationships |
| [docs/initiatives.md](docs/initiatives.md) | Cross-project initiative format, lifecycle, readiness derivation, and deferred controls |
| [docs/task-provider.md](docs/task-provider.md) | The pluggable task backend (local + Notion), the contract, `/start`, adding a provider |
| [docs/file-formats.md](docs/file-formats.md) | Frontmatter, the required project-memory sections, `working.md` shape, domain-file body |
| [docs/scripts.md](docs/scripts.md) | Every script + its invocations, and the environment-override table |
| [docs/knowledge-lifecycle.md](docs/knowledge-lifecycle.md) | working → domain → skill maturation, domain-vs-skill, governance, design rationale |
| [docs/workflows.md](docs/workflows.md) | Common workflows (new engagement, capture, promote, maintenance) and troubleshooting |
| [docs/showcase.md](docs/showcase.md) | Guided tour for evaluators — the story of memory compounding across sessions and repos, pointing into the reference pages |
| [docs/demo-runbook.md](docs/demo-runbook.md) | Presenter script for the 60-minute live demo, run against a real tree |
| [CHANGELOG.md](CHANGELOG.md) | Release notes |
| [UPGRADING.md](UPGRADING.md) | Channel model, rollback behavior, semver, and migration notes |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Commit routes, the test gate, changelog fragments, and testing discipline |
| [SECURITY.md](SECURITY.md) | How to report a vulnerability |

## Layout at a glance

```
identity.md              Hard rules (injected once per session) — per-instance, git-ignored
doctrine/orchestrator.md Tracked workflow doctrine core, updated every sync
orchestrator.local.md    Personal doctrine overlay, additive — per-instance, git-ignored
index.md                 Auto-generated roster of projects + domains
domain/<topic>.md        Cross-project knowledge (lazy-loaded on trigger match)
projects/<name>/         memory.md · working.md · todo.md · plans/ · investigations/ · wikis/ · audits/ · archive/
initiatives/<slug>.md    Cross-project initiatives: decision stream + Targets — per-instance, git-ignored
commands/                Slash commands (/checkpoint, /start, …) → ~/.claude/commands, mirrored as skills elsewhere
harnesses/<name>/        Per-harness wiring + manifest (claude · codex · copilot · antigravity)
skills/  ·  agents/       Authored + in-engine skills, bundled subagents (→ ~/.claude, ~/.agents/skills)
templates/               Seed files install.sh copies when a target is missing (identity, index, skills.toml, config)
migrations/              Forward-only instance migrations
changelog.d/             Per-PR changelog fragments, assembled at release
scripts/                 Bash engine (install · drivers · formatters · hooks) + Python task-provider
CHANGELOG.md             Release notes
UPGRADING.md             Upgrade contract + per-version notes
install.sh               Manifest-driven, agent-runnable installer
```

Full tree and the `~/.claude` / `~/.codex` symlink maps: **[docs/install.md](docs/install.md#directory-layout)**.

---

*Committed: the engine (`scripts/`, `harnesses/` wiring, `commands/`, `agents/`, `doctrine/`, `templates/`, `migrations/`, `changelog.d/`, `install.sh`), the in-engine skills (`design-brainstorm`, `project-scan`, `skill-audit`), the tooling domains (`domain/agent-tooling.md`, `domain/codex.md`) and the self-documenting `projects/ai-memory` meta-project. Git-ignored: your data (`identity.md`, `orchestrator.local.md`, `index.md`, the rest of `domain/*` and `skills/*`, `projects/*` except `_template/` and `ai-memory`, `initiatives/*` except the template, `skills.toml`, `.skill-cache/`, `config.local.sh`, `tasks/`, `archive/`). See `.gitignore`.*
