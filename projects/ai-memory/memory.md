---
topic: ai-memory
scope: project
summary: The markdown-only Claude Code memory system itself — hooks, slash commands, scripts, and the schema/wiki/scratchpad tree (this repo is the source copy)
repo_path: $MEMORY_DIR
repo: https://github.com/seyio91/ai-memory-system.git
---

## What It Is
The markdown-only memory system: files + hooks + macOS-`bash`-3.2 scripts, no DB, daemon or MCP server. A **meta-project** — the tracked project *is* the tooling, and this checkout is the public source copy. Spec: `README.md` + `docs/` (`docs/harnesses/<name>.md` per harness). Single owner.

Three layers: **schema** (`identity.md`, doctrine — outranks everything), **wiki** (`domain/*.md`, `projects/*/memory.md`), **scratchpad** (`projects/*/working.md`, matured via `/promote-memory`). The engine is harness-agnostic (manifest-driven `install.sh`; claude, codex, copilot, antigravity) and versioned: consumers sync to `v*` tags, never a moving `main`.

## Commands
- `bash scripts/run-tests.sh` — the gate: tests, python, lint, skills, doc-vs-code, shellcheck. `--only PAT` / `--changed [REF]` are iteration only and print `NOT A FULL RUN`; `--tests-only` prints no banner, only marks the other stages skipped — never gate on it.
- Locally, run the suite with signing off or the release/sync fixtures fail spuriously: `GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=commit.gpgsign GIT_CONFIG_VALUE_0=false GIT_CONFIG_KEY_1=tag.gpgsign GIT_CONFIG_VALUE_1=false`.
- `bash scripts/lint-memory.sh` — memory lint; `bash scripts/check-memory-size.sh --file <memory.md>` — size budget.
- `bash scripts/check-docs.sh` — `docs/scripts.md` env-var table vs code.
- `bash scripts/assemble-changelog.sh` — fragments → CHANGELOG section + next version (run by `release-pr.yml`, rarely by hand).

## Conventions
- **Commit route is decided by what changed, not size.** `projects/**` → `git-cli commit --all` + push to `main`. Everything that reaches users (`scripts/`, `harnesses/`, `install.sh`, `docs/`, `.github/`, skills, the tracked `domain/` files) → `git-cli ship --intent "…"`. Full table: `CONTRIBUTING.md`.
- **The tracked `domain/` files are `_template.md`, `agent-tooling.md`, `codex.md`** — they ship in every tag, so edits need a PR; every other `domain/` file is gitignored and personal.
- **`git-cli commit --all` skips untracked files** — `git add` new files explicitly first.
- Conventional commits with a scope: `feat(lint):`, `fix(guard):`, `docs(codex):`; housekeeping is `chore(ai-memory):`.
- **Every user-visible PR drops `changelog.d/<id>.<kind>.md`** (`breaking`/`feature`/`fix`/`upgrade`); the kinds derive the version. A new `migrations/<v>-*.sh` needs a matching `UPGRADING.md` section (test-enforced).
- Testing discipline (mutation testing, hermetic fixtures, live-exercising prose commands): `CONTRIBUTING.md` → Testing discipline.

## Architecture Decisions
- **Markdown is the database** — editor, diff, grep and git are the interface; every mutating script has a hand-editable equivalent (Two-Path).
- **Hook-injected, not retrieved** — full payload on `SessionStart`, `@memory` and the first post-compaction prompt; breadcrumbs otherwise; domain files lazy-load. `SessionStart` is the once-per-session guarantee; only compaction uses a sentinel.
- **Project detection walks up from cwd to `.agents/memory-project`** (legacy `.claude/memory-project` fallback); no marker means memory is dormant. `repo`/`repo_path` frontmatter is the reverse map.
- **`index.md` is generated from frontmatter** inside the AUTOGEN fence and lists names + summaries only — frontmatter is the contract for catalog, lint and regeneration.
- **Orchestrator / executor / validator.** Roles resolve through harness manifests + `config.local.sh`; read-only roles never fall back to a write-capable executor. The validator defaults to the orchestrator's plane so validation is cross-model.
- **Task Contract at plan and phase level** — a plan-only check let a phase-2 defect surface after phases 3–6 were built on it. Phase dependencies are declared (`**Depends:**`, mirrored as `(needs: Pn)` in `todo.md`) because `todo.md` is what is read on resume.
- **Decomposition rules live inline in `/new-plan`**, not by reference to `superpowers:writing-plans` — that would bind us to an ungated plugin version, and its TDD loop doesn't fit Terraform/GitOps work.
- **Task providers are a push-dominant projection** (local or Notion). Task `summary` is capped at 500 chars; long-form lives in a named investigation. Notion refs are always the full page UUID.
- **`add_progress` stays an unwired no-op on purpose** — the only concrete method on the provider ABC, so backends opt in. `/checkpoint` is project-scoped, not task-scoped, so wiring it has no ref to use. Don't "clean up" the method.
- **Both plan entry points share one task-linking partial** (`scripts/partials/task-link.md`) with a byte-for-byte drift gate. Lint rule 12 flags plans with no `task_ref`; `task_ref: none` marks deliberate plan-only work.
- **The drift gate's carrier count is a hardcoded literal on purpose** — marker discovery fails open when a carrier loses its block. Bump it when adding a carrier; never make it dynamic.
- **`design-brainstorm` is the Tier-3 gate**, renamed from `brainstorming` to stop colliding with the `superpowers:brainstorming` plugin (which writes plans outside the memory tree). The *activity* is still "brainstorming".
- **An investigation is an artifact; a brainstorm is an activity.** Investigations archive with their task.
- **Durable memory names artifacts, never paths** — paths rot on archive; only live machine-consumed fields hold paths.
- **Skills are owned by memory and symlinked into harnesses** by `link-skills.sh`; remote skills are declared in `skills.toml`, lock-pinned and materialized into `.skill-cache/`.
- **Hook layer: share the isomorphic, special-case the divergent** — no universal adapter over a bounded harness set. Codex gets a static base + chunked live injection; Antigravity a static base + whole-payload live injection.
- **Release = a git tag; no build step.** Changelog fragments are written per PR while the *why* is live — a model is kept off the CI critical path, because drafting notes at release time reconstructs intent from commit subjects.
- **CI skips the suite only for the four root community files, via a gate job, not `paths-ignore`.** `paths-ignore` reports no status and would deadlock a required check. The match is anchored (`grep -vxE`) and fails closed; `docs/` is never exempt.
- **Initiatives are root-level `initiatives/<slug>.md`, and the decision stream is the record (stream-first).** Plans, runbooks and memory cite stream ids. Staleness alerts persist until a stream append or `--ack` — a self-silencing warning recreates the omission it exists to catch.
- **Instance config never lives in tracked memory** — channel, provider and executor choices go in gitignored `config.local.sh`, and tracked memory ships to every consumer.
- **Open-sourcing removed content going forward, never by scrubbing history.**

## Known Constraints / Gotchas
- **A branch switch here is a live downgrade of the running harness.** Use `git switch -C main origin/main` or `merge --ff-only origin/main`; local `main` has been 182 commits stale. Check the channel before authoring — `release`-pinned instances get yanked back by `/sync-system`. Re-run `install.sh` after a version hop.
- **Housekeeping created on a feature branch rides that branch** — `main` has never seen branch-born files, and most of `projects/*` and `initiatives/*` is gitignored with no commit route at all. Check `git check-ignore --no-index` first.
- **A worktree forks the memory tree but `MEMORY_DIR` stays pinned to the main checkout.** Keep plan/todo bookkeeping in main; the isolation guard blocks `projects/**` edits, `rtk git` and `GIT_CONFIG_COUNT` overrides inside a worktree.
- **For a deny-list/guard change, a green suite is where validation starts** — probe for bypasses, and check every false-positive fix for a new false negative.
- **Adding a value to a shared frontmatter field widens every rule that reads it** — enumerate them and decide per rule (`task_ref: none` is valid for rule 12, rejected by rule 9).
- **`git branch --contains` lists branches containing a commit, not branches that exist** — a stale branch is absent because it's stale. Use `git for-each-ref refs/heads/`.
- **A silent failure that exits 0 (or dies silently under `set -e`) reads as "nothing to do"** and gets blamed on whatever looks suspicious nearby. Bisect the environment; check that functions used in `$(…)` end with `return 0`.
- **`ls`/glob output is not evidence for counts or absence** — corroborate with `find` or `git ls-files`.
- **Hook entries for the same event run concurrently on Claude and are concatenated in completion order** — fanned-out payloads must self-order (`<memory:chunk index of>`).
- **Claude caps `additionalContext` at ~10,000 chars; copilot and antigravity take the payload whole.** Verify the payload's tail (`working` renders last), not just presence.
- **`config.local.sh` overrides process env** — change instance settings there, not in the shell.
- **`v1.0.0` is a trap tag** that predates `identity.md` untracking and can clobber it; `v1.1.0` is the first safe one. `--to <branch>` checks out the ref as-is without fast-forwarding.
- **A tracked user-editable file bricks the release channel**, and anything tracked ships in every tag — `export-ignore` doesn't affect clone or checkout.
- **A GitHub force-push removes nothing** — PR refs keep scrubbed commits; only deleting the repo does.
- **Removing a workflow's push trigger freezes its badge** — the tests badge needs `?event=pull_request`.
- **`domain/<topic>-cache/` subdirs are invisible to the catalog and to git** (`-maxdepth 1`, gitignored) — look them up by path and never reindex for them.
- **Plan-mode artifacts go to `projects/<active>/plans/`**, not the harness default plan directory.
- **Slash commands are indexed at session start** — a new command needs a restart to autocomplete.

## Related Projects

| Project | When it's involved | It owns / entry point |
|---------|--------------------|------------------------|
| `agent-skills` | Any change to a remote-referenced skill's own content (`SKILL.md`, process, frontmatter). | The authored source of every remote skill, e.g. `renovate-manager/SKILL.md`. Not `design-brainstorm` — that is in-engine under `skills/`. |
| *(initiative)* `memory-md-hygiene` | Memory lint, the write guard, the project template, or a `memory.md` trim. | `initiatives/memory-md-hygiene.md`; contract in wiki `memory-md-content-contract`. |

> **This tree can only reference remote skills, never fix them** — edits under `.skill-cache/` are discarded on the next resolve. A content change is a delegated PR against `agent-skills`, and contradictions across the repo boundary are invisible to every check here.
