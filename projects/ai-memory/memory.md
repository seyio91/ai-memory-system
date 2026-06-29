---
topic: ai-memory
scope: project
summary: The markdown-only Claude Code memory system itself — hooks, slash commands, scripts, and the schema/wiki/scratchpad tree (this repo is the source copy)
repo_path: ai-memory
repo: https://github.com/seyio91/ai-memory-system.git
---

## What It Is
The markdown-only memory system for Claude Code that lives at `~/Projects/ai-memory` — no vector DB, no daemons, no MCP server, just files + hooks + macOS-`bash`-3.2 shell scripts. This is a **meta-project**: the project being tracked *is* the memory tooling. Authoritative spec is the repo `README.md`.

Three layers (Karpathy LLM-Wiki pattern):
- **Schema** — `identity.md` (hard rules, injected once/session), `~/.claude/CLAUDE.md`. Outranks everything.
- **Wiki** — `domain/*.md` (cross-project) + `projects/*/memory.md` (engagement-specific). Durable.
- **Scratchpad** — `projects/*/working.md`, injected every prompt while non-empty; matures into the wiki via `/promote-memory`.

Moving parts: one `UserPromptSubmit` hook (`~/.claude/hooks/inject_memory.sh`) emits `<memory:*>` blocks; 10 slash commands in `~/.claude/commands/`; 5 scripts in `scripts/` (`_lib.sh`, `regenerate-index.sh`, `lint-memory.sh`, `archive-cleanup.sh`, `new-project.sh`) with dependency-free tests under `scripts/tests/`.

## Current State
Functional and in daily use across the real engagements indexed in `index.md` (tpe-stacks, tpe-kubernetes, tpe, eks, services, k8s-addons + the kyverno domain file). Git history is short and structural:
- `781d3db` Initial commit: core memory system
- `da94f0e` Add cross-project relationships (the `## Related Projects` table + delegate-don't-load contract)
- `10e9835` Add plan-set execution rule to cross-project transport

Top-level also carries a `docs/` dir, a root `plan.md`, and `.claude/`.

## Architecture Decisions
- **Markdown over a DB** — every editor/diff/grep works; zero infra.
- **Hook-injected, not retrieved** — context arrives in-band on the first prompt; Claude never has to "remember to look." Domain files are the exception: lazy-read on trigger match, not auto-injected.
- **Frontmatter-driven catalog** — `index.md` AUTOGEN block is regenerated from frontmatter (`/reindex`), so it can't lag the files.
- **Per-session injection markers** (`~/.claude/memory_sessions/<session_id>`) — once-per-session blocks don't re-inject; concurrent sessions don't collide; markers self-expire after 2 days.
- **Distributed cross-project relationships** — a relationship lives in the project where the work *starts* (`## Related Projects`), never in an umbrella. Siblings are **delegated to subagents, never loaded** into the orchestrator thread.
- **User-selectable executor** (2026-06-29, branch `feat/selectable-executor`) — the orchestrator's executor is no longer hardcoded to Codex. `scripts/executor.sh` resolves `AI_MEMORY_EXECUTOR` (from `config.local.sh`; default `claude-subagent`) and prints which *plane* to use: `--which` → `subagent` (use the Agent tool) or `cli:<key>` (run `--run "<prompt>"`, which execs the CLI or prints `EXECUTOR_USE_SUBAGENT`/exit 3 to bounce back to the Agent tool). Built-in types: `claude-subagent` (in-harness) and `codex` (CLI via `codex-mem.sh --executor`); generic CLIs via `AI_MEMORY_EXECUTOR_CMD_<key>` (`{prompt}` substituted, key `[A-Za-z0-9_]+`); missing CLI binary auto-falls-back per `AI_MEMORY_EXECUTOR_FALLBACK`. The plane-split is the key design point: CLI executors are shell-invokable, the subagent executor is a harness tool — `--which` is the single source of truth for routing, the shell never spawns a subagent. **This machine: `codex` is not installed and `~/.codex/rules/default.rules` never existed**, so `AI_MEMORY_EXECUTOR=claude-subagent` is set in `config.local.sh`. The codex deny-rules file is now documented as *optional* codex-only hardening, not a load-bearing guarantee; the deny-list is restated in every delegation prompt instead.
- **This meta-project is tracked in-repo** (2026-06-29) — unlike every other project (which maps to an external repo + holds client data → gitignored, kept local), `projects/ai-memory` documents *this* repo and carries no secrets, so its durable artifacts are version-controlled here via a `.gitignore` carve-out: **tracked** = `memory.md`, `plans/`, `todo.md`; **ignored** = `working.md` (per-machine in-flight scratch — would conflict across machines) and `archive/` (audit noise). Consequence: routine `memory.md`/`todo.md` edits become git changes on the live checkout — version them through the normal branch→PR flow (or commit directly). Repo is **private** (`seyio91/ai-memory-system`), so the internal repo/org names this file references are acceptable to track. The design spec under `docs/superpowers/` stays gitignored (per earlier decision) — the `plans/` file is the tracked record.
- **Non-goals:** no `PreToolUse` deny enforcing `todo.md` (would break other tooling — it's a documented convention only); no bootstrap script (README is the source of truth for rebuilding).

## Known Constraints / Gotchas
- **This repo IS under git, but personal content is `.gitignore`d.** Authoritative list is `.gitignore` — verify there, don't trust this summary. Tracked (distributable source): `scripts/`, `claude/`, `agents/`, generic `skills/`, `install.sh`, `README.md`, `identity.md`, `config.local.sh.example`, `projects/_template`, `domain/_template.md`. Ignored (personal/runtime): `.DS_Store`, `.claude/`, `.sessions/`, `__pycache__/`, `/index.md`, `/domain/*` (except `_template.md`), `/projects/*` (except `_template` **and `ai-memory`** — see the meta-project note above), `/tasks/`, `/archive/`, `/config.local.sh`, `/skills/fiter-infrastructure-analyzer/`, and `/docs/superpowers/` (brainstorm specs/plans — rule added 2026-06-29). This checkout is the distributable *source copy*; live per-engagement memory never gets committed **except this `ai-memory` meta-project**. Never commit secrets.
  - *Corrected 2026-06-29:* earlier this gotcha claimed `.active_project`, root `plan.md`, and `domain/.gitkeep` were ignored — all stale. `.active_project` and root `plan.md` no longer exist (removed in the github-core migration); the domain ship-file is `domain/_template.md`. And `docs/superpowers/*` was claimed ignored but wasn't until the rule was actually added 2026-06-29.
- **`archive/` is never read unless the user explicitly asks** — and never deleted during a "reorganize memory" pass (it's the audit trail).
- **Scripts target macOS `bash` 3.2** — no `mapfile`, no associative arrays. Resolve the tree via `MEMORY_DIR`.
- **Frontmatter is the contract** — missing/malformed fields break the index; `lint-memory.sh` catches it.
- **`_template/` is excluded** from index, lint, and regeneration — edit it to change the project scaffold.
- Slash commands are indexed at session start — a new command needs a session restart to autocomplete.
- **Global fallback is deliberately disabled.** Per user decision, `.active_project` is kept **empty** so detection is purely per-repo `.claude/memory-project` pins — an unpinned directory yields *no* project context (explicit) rather than silently loading a default. Pinned repos (git roots): `ai-memory`, `tpe-stacks`, `tpe-kubernetes`, `tpe`, `eks`, `services`, `k8s-addons`. `new-project.sh` was modified to **no longer write `.active_project`** (scaffold-only) — after creating a project, activate it by pinning a repo, not via the fallback. The `.active_project` machinery still exists in `_lib.sh`/the hook for anyone who wants it; it's just left empty here.

## Related Skills / Tooling
- **`review-terraform-pr`** (`~/.claude/skills/review-terraform-pr/SKILL.md`) — reviews module-change Terraform PRs (resolve source → cache-first version diff → classify resource add/change/replace/remove → static safety verdict). Reads + writes a **module version-comparison cache** at `domain/terraform-module-cache/<module>.md`. Spec/plan: `docs/superpowers/specs/2026-06-22-review-terraform-pr-design.md`, `docs/superpowers/plans/2026-06-22-review-terraform-pr.md`.
- **`domain/terraform-module-cache/` convention** — a **path-addressed** cache keyed on module short name (one file per module, a `## Version Comparisons` table). It is NOT part of the `index.md` catalog (`regenerate-index.sh` only globs top-level `domain/*.md`), and `domain/*` is already `.gitignore`d — so cache files are local, untracked, and looked up by direct path. No reindex needed when writing them.

## Current Goal
Onboarding the memory system as a tracked project (just scaffolded). No locked milestone beyond keeping the tooling, README, and `identity.md` in sync as conventions evolve.
