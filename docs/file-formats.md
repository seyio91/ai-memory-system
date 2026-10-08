# File format conventions

## Root instruction files

`identity.md` is a per-instance file seeded by `install.sh` when missing.
Workflow doctrine is split into a tracked core plus a per-instance overlay:

| File | Seed template | Purpose | Tracked? |
|------|---------------|---------|----------|
| `identity.md` | `templates/identity.template.md` | Role, stack, communication style, defaults, and hard rules | no |
| `doctrine/orchestrator.md` | n/a — ships with the clone | Workflow doctrine: task tiers, brainstorm gate, orchestrator/executor/validator roles, Task Contract, and cross-project rules | yes — updated on every sync |
| `orchestrator.local.md` | none — seeded empty by `install.sh` | Personal additions to the core doctrine, additive | no |

Existing files are never overwritten (an empty overlay is only seeded when absent).
Precedence is:
`identity.md` hard rules > `orchestrator.local.md` overlay > `doctrine/orchestrator.md` core > project memory.

A pre-1.6.0 instance may still have a root `orchestrator.md`. It is never deleted
automatically — migration `1.6.0-orchestrator-core-overlay.sh` backs it up to
`orchestrator.md.pre-1.6.0` and seeds the empty overlay. Until that migration runs,
the root file keeps being injected (as `orchestrator-local`) when the overlay is
blank, with a deprecation notice. A root file that is not injected — shadowed by a
non-blank overlay, or a stale re-seed once the `.pre-1.6.0` backup exists — is named
as `orchestrator-ignored` in the breadcrumb (harnesses that emit one; Copilot does
not). See [UPGRADING.md](../UPGRADING.md#160).

## Frontmatter (required on every domain + project memory file)

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
category: acme-corp                  # optional — client/group this project belongs to (PERSONAL, gitignored)
---
```

`topic`/`scope`/`summary` are required; `lint-memory.sh` flags files missing any of them. `repo`/`repo_path`/`tags`/`category` are optional — validated only when present (absence is never an error). `summary` stays the index description; there is no separate `description` field.

**`category`** groups a project under a client/group for `/state` (grouped view + `/state <category>` filter) and `/activity` (plans created per category over a window). It is **per-instance personal data** — the field is supported by the engine, but its value lives only in the gitignored project `memory.md` and never enters git history. Set it with `/pin <project> --category <client>` (from inside the checkout), during `/new-project`, or by hand. One flat category per project.

## Project memory sections

`memory.md` is injected whole into every session for its project, so it plays the role a
`CLAUDE.md` plays. The test for every line: **would removing it cause Claude to make a
mistake?** If not, cut it.

| Include | Leave out |
|---|---|
| Commands Claude can't guess (build, test, lint, render, release) | Anything readable from the code (inventories, pins, defaults, layout trees) |
| Style rules that differ from defaults | Standard language conventions |
| Test instructions and the preferred runner | Detailed API/reference docs — link them |
| Branch naming, commit and PR conventions | Information that changes often — status, versions, counts, PR numbers, SHAs, dates |
| Project-specific architectural decisions (with the why) | File-by-file descriptions |
| Gotchas and non-obvious behaviour | Self-evident advice |

Sections, in template order (**required** ones are checked by `lint-memory`):

```
## What It Is                  — required: what the project is, stack, ownership
## Commands                    — optional: commands Claude can't guess
## Conventions                 — optional: branch/commit/PR/style rules that differ from defaults
## Architecture Decisions      — required: locked-in choices (with the why) and non-goals
## Known Constraints / Gotchas — required: landmines, load-bearing hacks
## Pointers                    — optional: links to the repo's README/CLAUDE.md, docs, wikis, skills
## Related Projects            — optional: cross-project relationship table (below)
```

`## Current State` and `## Current Goal` are retired: `lint-memory` WARNs when either is present
and names the new home. Status and session history go in `working.md`; the active goal is the
first plan heading under `## Active` in `todo.md`, which is where `/state` reads it.
`/promote-memory` writes project decisions into `## Architecture Decisions`.

**Size budgets.** `memory.md` also carries a byte/line budget: `lint-memory` (rule 16) and the
write guard WARN past 16 KB per file and 400 B per line — a long file or a wall-of-prose line
reads more slowly every session. Separately, the *rendered session payload* for a project (this
file plus identity/orchestrator/index/working, per harness format) is ERROR when it would need
more delivery chunks than a harness's `session_chunks` cap — that one truncates silently rather
than just reading slowly. Both checks are `check-memory-size.sh --file`/`--payload`; see
[scripts.md](scripts.md). No budget applies to `domain/*.md` (lazy-loaded, never injected).

**Optional `## Related Projects`.** The template carries a commented-out `## Related Projects` block after the other sections. Uncomment it only when this project's work spans into others; it holds the relationship table described in [Cross-project relationships](workflow.md#cross-project-relationships). Because it's HTML-commented in the template, it stays inert for the lint section check until you uncomment it.

```markdown
<!-- Uncomment only if this project's work spans into other projects.
## Related Projects

| Project | When it's involved | It owns / entry point |
|---------|--------------------|------------------------|
| <other-project> | <trigger condition> | <what it owns — entry file/path> |

> Ordering: <cross-repo sequencing, if any>
-->
```

## Plan frontmatter (`projects/<project>/plans/<slug>.md`)

```markdown
---
plan: <slug>                  # matches the filename
status: draft                 # draft | in_progress | done — nothing else
created: YYYY-MM-DD
owner: <who>
completed: YYYY-MM-DD         # written by /plan-done, alongside status: done
task_provider: notion         # optional — written by /start when a task backs the plan
task_ref: <full task id>      # optional — full id, never an 8-char prefix
---
```

**`status:` takes exactly one of `draft`, `in_progress`, `done`.** That is what the tooling
produces: `/new-plan` scaffolds `draft`, `/plan-done` writes `done`, and `in_progress` is the
in-flight value between them. There is no synonym — not `active`, not `complete`, not `closed`,
and not a hyphenated `in-progress`. `/state` and `/activity` render the value **verbatim**, so a
synonym silently splits one column into two and a missing `status:` renders blank.
`lint-memory` rule 8 enforces this; it is the enforcement, not the source of truth — this table is.

> `/plan-archive` *tolerates* reading `complete` or `closed` when deciding whether to prompt, but
> those are not values to write. Use `done`.

## Domain file body

Just `## Knowledge`. Entries append as `**[YYYY-MM-DD]** what — why it matters`.

## `working.md` shape

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

### Per-worktree overlays (`working.<key>.md`)

Two concurrent sessions on one repo run in separate git worktrees (a checkout has one HEAD, so concurrency *requires* it). They would otherwise share one `working.md` and clobber each other's checkpoints. To prevent that, the scratchpad is resolved per session: in a **linked git worktree** the working file becomes `working.<worktree-name>.md`; in the main checkout it stays `working.md`. `memory.md`, `todo.md`, `index`, and `plans/` are always shared — only the volatile scratchpad splits.

The key is chosen with precedence **explicit marker > worktree > none**:
- Drop a `.agents/memory-session` file in the checkout (sibling to `.agents/memory-project`) to name the overlay explicitly — its content is sanitized to `[a-z0-9-]`, so `feature-x` → `working.feature-x.md`. Use this to label a split, or to force one without a worktree.
- Otherwise a linked worktree auto-keys on its own name; the main checkout gets the base file.

The resolver (`resolve_working_file` in `scripts/content-core.sh`) is shared by every harness's read and write path, so the injected `<memory:active>` breadcrumb, the full payload, and `/checkpoint` all agree on the same file. Overlays are gitignored (`working*.md`) like the base scratchpad.
