---
topic: ai-memory
scope: project
summary: The markdown-only Claude Code memory system itself — hooks, slash commands, scripts, and the schema/wiki/scratchpad tree (this repo is the source copy)
repo_path: $MEMORY_DIR
repo: https://github.com/seyio91/ai-memory-system.git
---

## What It Is
The markdown-only memory system for Claude Code — no vector DB, no daemons, no MCP server, just files + hooks + macOS-`bash`-3.2 shell scripts. This is a **meta-project**: the project being tracked *is* the memory tooling. Single owner (Seyi). Authoritative spec is the repo `README.md` (a lean landing page) plus the deep-reference pages under `docs/` — `docs/harnesses/<name>.md` per harness, mirroring the multi-harness direction.

Three layers (Karpathy LLM-Wiki pattern):
- **Schema** — `identity.md` (hard rules, injected once/session), `~/.claude/CLAUDE.md`. Outranks everything.
- **Wiki** — `domain/*.md` (cross-project) + `projects/*/memory.md` (engagement-specific). Durable.
- **Scratchpad** — `projects/*/working.md`, injected with the full payload at session start (re-injected on `@memory`/after compaction) while non-empty — **not** every prompt; matures into the wiki via `/promote-memory`.

Moving parts: one `UserPromptSubmit` hook (the shared `scripts/hooks/inject.sh`, format-parameterized) emits `<memory:*>` blocks; slash commands in `~/.claude/commands/`; scripts in `scripts/` (`_lib.sh`, `regenerate-index.sh`, `lint-memory.sh`, `archive-cleanup.sh`, `new-project.sh`, `memory-pin.sh`, `link-skills.sh`, `executor.sh`, `codex-mem.sh`, the `taskprovider/` package + `taskctl`) with dependency-free bash-3.2 tests under `scripts/tests/`.

## Current State
Functional and in daily use across the real engagements indexed in `index.md`. This checkout is the distributable **source copy** and the dev instance: `origin = seyio91/ai-memory-system` (private, headed public), `AI_MEMORY_CHANNEL=dev` so a sync never flips it onto a tag.

The engine is **harness-agnostic** (`install.sh` is a generic manifest-driven installer; `claude`/`codex`/`antigravity` are registered harnesses; the marker is `.agents/memory-project`; the executor resolves roles from the manifest) and **versioned**: consumer instances sync to stable `v*` tags, never to a moving `main`. Latest tag `v1.1.0`; `v1.0.0` is a trap tag (see Gotchas). Design records live in Architecture Decisions below.

## Architecture Decisions
- **Markdown over a DB** — markdown files are the durable store; normal editor, diff, grep, and git workflows are the database interface.
- **Hook-injected, not retrieved** — context is delivered in-band: full payload on session start, `@memory`, and first post-compaction prompt; breadcrumbs otherwise; domain files stay lazy-loaded.
- **Frontmatter-driven catalog** — `index.md` is regenerated from frontmatter inside the `<!-- BEGIN AUTOGEN -->` / `<!-- END AUTOGEN -->` fence; retired fences are ignored, and scaffold files stay out of the catalog.
- **Lean index** — `index.md` lists names and summaries only; paths are derivable, while repo metadata and domain triggers remain in the source files.
- **No per-session marker; `SessionStart` is the once-per-session guarantee** — initial full injection relies on the hook event itself; only compaction recovery uses a per-session sentinel.
- **Compaction recovery** — compaction rehydration is a sentinel handoff from `SessionStart source=compact` to the next `UserPromptSubmit`, which emits the full payload once.
- **Project detection per-prompt** — active project resolution walks up from `cwd` to `.agents/memory-project`; no marker means memory is dormant, with legacy `.claude/memory-project` read only as fallback.
- **Bidirectional repo↔project map** — `.agents/memory-project` is the forward map and `repo`/`repo_path` frontmatter is the reverse map; `repo_path` is relative except the `$MEMORY_DIR` self-reference for `ai-memory`.
- **Distributed cross-project relationships** — related-project knowledge lives where the work starts; sibling work is delegated rather than loaded, and plan-set execution pauses at human or CI gates.
- **Orchestrator / Executor / Validator workflow** — the main session orchestrates, executors implement, and the read-only validator role checks plan success criteria; `todo.md` remains the plan tracker and destructive executor actions stay forbidden.
- **Executor: two roles, manifest-resolved.** `executor.sh` resolves `task` and `explore` through harness manifests and config-local executor settings; read-only roles never fall back to write-capable execution.
- **Task-provider layer + `/task`/`/start`** — tasks are a pluggable, push-dominant projection over local or Notion backends; `/task` captures intent and `/start` turns it into a plan.
- **Task `summary` is a capped thin record; long-form lives in the tree by pointer** — task summaries are capped at 500 characters, while detailed pre-plan material lives as named investigations in the project tree; Notion page bodies are outside the provider contract.
- **Brainstorming skill (gated Tier-3 design pass)** — only Tier-3 feature work with open design questions runs the brainstorming pass; its output is folded into the plan, not a separate spec.
- **An investigation is an artifact; a brainstorm is an activity** — investigations are optional long-form findings artifacts consumed by tasks and `/start`; brainstorms are the dialogue that produces the plan, and investigations archive with their task.
- **Task Contract — success criteria** — plan-tier tasks must carry explicit, checkable success criteria before execution; the validator checks exactly that contract.
- **Multi-git-provider support** — repository provider is inferred from the remote host, and PR/repo tooling routes through GitHub, Bitbucket, or Azure DevOps while preserving the no-merge guardrail.
- **Skills owned by memory, symlinked into harnesses** — skills live in memory-owned stores and runtime skill directories receive symlinks from `scripts/link-skills.sh`.
- **Skill subsystem — validation + on-request self-rating; no write boundary.** Skills have schema validation and optional self-rating, but no declared write-boundary mechanism; execution policy and the validator are the enforcement layers.
- **Skill source model** — authored skills are local, remote skills are manifest-declared and lock-pinned, skill state lives under a separate data root, and enumeration is centralized across source roots.
- **Doc-vs-code gate — the `docs/scripts.md` env-var table is machine-checked** — documented script environment variables are checked against code and transitive sourcing paths; the gate is scoped to symbol drift, not semantic prose.
- **A control is not trusted until it has been watched to fail.** Controls must be mutation-tested or otherwise observed failing on known defects before their green result is trusted.
- **Knowledge lifecycle** — working memory matures into domain/project memory and, when reusable enough, into packaged skills.
- **Derived state snapshot (`/state`)** — `/state` is an on-demand derived projection of active work across projects and is never auto-injected.
- **Project categories + activity report** — projects may carry one flat category for grouped `/state` and `/activity` reporting; the report groups plans by creation window.
- **Durable memory names artifacts; it does not store their paths** — durable memory references artifacts by name, not path; only live machine-consumed fields may hold paths.
- **Wikis document existing system components, not plan references** — `wikis/` records durable system components; comparison, triage, and backlog material belongs to plan inputs and archives after use.
- **This meta-project is tracked in-repo** — `projects/ai-memory` is the tracked dogfood project for this repo, with durable memory artifacts versioned and `working.md` left local-only. Commit routine memory/todo/plan-archival edits **directly to `main` (no PR)**; reserve a branch + PR for features and substantive code changes.
- **Open-sourcing: remove content going forward, never scrub** — the public transition removes live personal/client content from current tracked files but does not rewrite published history or archive audit trail.
- **Per-environment config loader; instance config never in tracked memory** — instance choices live in gitignored `config.local.sh`, with tracked examples only; scripts and orchestration read runtime config from there.
- **Harness-agnostic, manifest-driven engine** — harnesses are registered by manifests with delivery and execution faces; `install.sh` drives shared installation through manifest data and common content formatting.
- **Codex adapter — hook-base, chunked (the Antigravity model)** — Codex uses a hand-owned static base plus live chunked hook injection for dynamic memory; `codex-mem.sh` remains only as the executor wrapper.
- **Antigravity harness — hook archetype, live injection + enforced executor** — Antigravity uses hook-time XML memory injection, an enforced guarded executor mode, and its own memory-aware statusline.
- **Hook layer — declarative, manifest-driven, shared where isomorphic** — hook roles are declared in manifests; Claude and Codex share behavioral hook scripts where their contracts match, while harness-specific registration remains allowed.
- **Hook layer — share the isomorphic, special-case the divergent; don't abstract over a bounded harness set.** Shared hook abstractions stop at genuinely common contracts; divergent harnesses keep thin local paths rather than forcing a universal adapter.
- **Versioned release channel — a git tag IS the release; no zip, no separate engine root** — consumers sync to stable tags or dev refs; migrations are forward-only/idempotent and releases are guarded, resumable tag cuts.
- **Non-goals:** no runtime deny hook enforces `todo.md`; `install.sh` is the supported agent-runnable bootstrap.

## Known Constraints / Gotchas
- **This repo IS under git, but personal content is `.gitignore`d.** The tracked source tree is distributable, personal/runtime memory is ignored, and only the `ai-memory` meta-project is intentionally versioned.
- **Scripts target macOS `bash` 3.2** — scripts must remain compatible with Bash 3.2 and resolve the memory tree through `MEMORY_DIR`.
- **`archive/` is never read unless the user explicitly asks** — archive content is audit trail, not working context, and is not deleted during reorganization.
- **Frontmatter is the contract** — catalog, lint, and regeneration depend on valid frontmatter; templates are excluded.
- **Working memory is per-project; its content rides the full payload injected once per session (and on `@memory`/post-compaction), NOT every prompt.** Keep `working.md` short; concurrent sessions on the same checkout are last-write-wins.
- Slash commands are indexed at session start — a new command needs a session restart to autocomplete.
- Oversized hook stdout is routed to a `<persisted-output>` file with a 2KB preview, but bloated `working.md` still expands full-payload injection.
- **For a security control, a green test suite is where validation STARTS, not ends.** Security controls need adversarial validation beyond the normal suite; false-positive fixes must be checked for false negatives.
- **A test file the runner's glob doesn't reach is silently ungated — the suite reports green and proves nothing.** New test locations must be wired into the runner or they are not part of the gate.
- **A recorded measurement is where planning STARTS, not ends — re-measure before you act on it, especially when it is the fact that justifies the work.** Planning baselines must be re-derived before execution, and each proposed control must be matched empirically to the bug class it claims to catch.
- **Codex execpolicy** `decision` must be `"forbidden"`; invalid values fail at `codex exec` time, and executor runs outside git repos need `--skip-git-repo-check`.
- **A git worktree on this self-referential meta-project forks the memory tree, but `MEMORY_DIR` stays pinned to the main checkout.** In `ai-memory`, plan/todo/memory bookkeeping stays canonical in main; worktrees are for engine code only unless isolated with their own `MEMORY_DIR`.
- **Codex `exec` (headless) fires `SessionStart(source=startup)` AND injects its `additionalContext` into model context — verified by live probe (2026-07-16, codex 0.144.4; floor 0.135.0).** Startup injection is proven for headless Codex; compaction survival is still unproven and must not be assumed.
- **Notion provider:** Notion can add/reorder select/status options but cannot rename/delete them; non-interactive routing requires credentials and provider env in `.zshenv`.
- **Notion refs are ALWAYS the full page UUID, never the 8-char prefix.** Short refs are ambiguous and API-invalid; local-provider slug refs do not change this Notion rule.
- **Plan-mode plan path:** plan-mode artifacts belong under `projects/<active>/plans/<name>.md`, not the harness default plan directory.
- **`config.local.sh` beats the environment.** Values exported from gitignored `config.local.sh` override process env, so instance channel/provider/executor changes must be made there.
- **`git tag -a -m` strips every line starting with `#`** — annotated release tags must preserve markdown messages with verbatim cleanup/file input. `git tag -l -n` reformats the message and hides the loss; only `git cat-file tag` shows the raw object.
- **`--to <branch>` checks out that ref as-is and does not fast-forward it.** Use an up-to-date remote ref when dogfooding or syncing to a branch.
- **`v1.0.0` is a trap tag — never point an instance at it.** It predates `identity.md` untracking and can clobber personalized identity data; `v1.1.0` is the first safe release tag.
- **Docs rot within hours when phases ship serially.** Runtime changes require rereading command docs as well as reference docs.
- **A tracked `identity.md` bricks the release channel.** User-editable files must not be tracked; untracking a previously tracked file can delete local data during checkout transitions.
- **A git tag ships a whole tree, and there is no build step to filter it.** Under tag-based distribution, tracking a file publishes it in every release; `.gitattributes export-ignore` is no defence — `git archive` honours it, `git clone`/`git checkout <tag>` do not.
- **A GitHub force-push does not remove anything.** GitHub-controlled PR refs can preserve scrubbed history; deleting/recreating the remote is the only complete removal path.

## Related Projects

| Project | When it's involved | It owns / entry point |
|---------|--------------------|------------------------|
| `agent-skills` | Any change to a **remote-referenced** skill's own content — `SKILL.md` prose, its process, its frontmatter. Triggered whenever a skill this instance consumes needs an edit. | The authored source of every remote skill (`brainstorming`, `renovate-manager`, `excalidraw-diagram`, …). Entry point: the skill's own directory in that repo, e.g. `brainstorming/SKILL.md`. |

> **This tree can only *reference* those skills, never fix them.** `skills.toml` declares them; `resolve-skills.sh` materializes them into the gitignored `.skill-cache/`, which is *referenced, not forked* — so an edit under `.skill-cache/<name>/` is silently discarded on the next resolve. A skill's content change is a **PR against `agent-skills`**, delegated (never loaded). Consequence, learned 2026-07-10: a doctrine contradiction between this tree's `memory.md` and a remote skill's `SKILL.md` is **structurally invisible** to any check that runs here — the doc-vs-code gate cannot see across the repo boundary.

## Related Skills / Tooling
- **`renovate-manager`** (remote-referenced from the `agent-skills` repo → materialized in `.skill-cache/`) — read-only Renovate-PR review dispatcher: routes by Renovate manager type to per-domain reviewers (helm vs terraform), runs heavy work (diff/clone/validate/release-notes) in parallel subagents, keeps review memory in the per-instance skill-data root (so re-resolving the remote never touches its data), resolves the project from the PR repo URL via the reverse-map. Skill specifics live with the skill, not in Architecture Decisions.
- **`domain/terraform-module-cache/` convention** — a path-addressed cache keyed on module short name (one file per module). Not in the `index.md` catalog (regenerate-index only globs top-level `domain/*.md`), and `domain/*` is gitignored — local, untracked, looked up by direct path. No reindex when writing them.

## Current Goal
**Prepare to open-source.** The repo goes public with its history intact; content is removed going forward, never scrubbed (see the open-sourcing decision above). `identity.md` and live client references are already out of the tracked tree.

Open build threads, all captured as backlog tasks:
- **Release automation** — replace `release.sh`'s release-time `git log` drafting with per-PR changelog fragments, then let GitHub Actions assemble and publish. Design in the `release-automation` investigation. Would also make branch protection on `main` possible, which `release.sh` currently forbids by pushing `main` itself.
- **`@`-sign section-level context loading** — pull a named file or section instead of injecting whole files.

**Versioned-release-channel thread — DONE** (the `versioned-release-channel` plan). Its design record is the `versioned-release-packaging` wiki; §7 there holds the deferred external-user zip thread, which untracking personal content would make cheap (`git archive` becomes a valid build primitive once nothing personal is tracked).
