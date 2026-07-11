# File format conventions

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

## Project memory sections (required)

The template enforces five sections; lint complains if any is missing:

```
## What It Is             — what the project is, stack, ownership, scale
## Current State          — deployed/stable vs in-flight (last ~30 commits)
## Architecture Decisions — locked-in choices and explicit non-goals
## Known Constraints / Gotchas — landmines, load-bearing hacks
## Current Goal           — active milestone, one thing only
```

`## Decisions Log` is appended by `/promote-memory` when promoting to a project (not in the template).

**Optional `## Related Projects`.** The template carries a commented-out `## Related Projects` block after the five required sections. Uncomment it only when this project's work spans into others; it holds the relationship table described in [Cross-project relationships](workflow.md#cross-project-relationships). Because it's HTML-commented in the template, it stays inert for the lint section check until you uncomment it.

```markdown
<!-- Uncomment only if this project's work spans into other projects.
## Related Projects

| Project | When it's involved | It owns / entry point |
|---------|--------------------|------------------------|
| <other-project> | <trigger condition> | <what it owns — entry file/path> |

> Ordering: <cross-repo sequencing, if any>
-->
```

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
