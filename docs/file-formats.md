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
## Pointers                    — optional: links to the repo's README/CLAUDE.md, docs, skills, and project wiki pages (`wikis/<slug>.md`)
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

**Duplicates and markers.** Across project `memory.md` files and `domain/*.md` (templates exempt),
`lint-memory` WARNs on a line that appears verbatim in two or more files (rule 17 — one fact, one
home) and on unresolved `NEEDS REVIEW` / `TODO` markers (rule 18). Both skip frontmatter, fenced
code and HTML comments; rule 18 also ignores markers inside inline code, and rule 17 skips headings,
lines under 40 bytes and table headers.

**Audits.** `/lint-memory --audit <project>` checks every claim in a project's `memory.md`
against its repo and read-only APIs, using the brief in [`agents/auditor.md`](../agents/auditor.md),
and writes `projects/<project>/audits/audit-YYYY-MM-DD.md`: one verdict per claim (Wrong / Stale /
Derivable / Move / Keep / Unverified), each with the command and output behind it. An audit edits
nothing; acting on it is a separate trim. Reports live in `audits/`, not `investigations/`, because
they are not tied to a task.

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

### Plan body (verification contract)

The body template lives once in `scripts/partials/plan-scaffold.md` (the *Plan scaffold* section of `/new-plan` and `/start`); this section is the grammar it follows and the lint that reads it. Shape, in order: `## Goal` (with `**Before:**` and `**After:**` lines), `## Non-goals`, `## Success criteria`, `## Design` (ending in a `**Builds on:**` line of references, never a dependency declaration), `## Security` (only when needed), `## Decisions (locked)`, `## Phases`, `## Risks / open questions`.

Grammar — what lint rule 20, the drift script and the feasibility brief parse; none changes it without a plan edit:

- **Criterion:** `^- R[0-9]+ \[(acceptance|parity)\] ` at the start of a line under `## Success criteria`; one line per criterion.
- **Parity reference**, within the `[parity]` line: ``vs `<git-ref>` `` (re-run the check at that ref and compare) or ``baseline `plans/<slug>.baseline/<path>` `` (compare against a snapshot kept on disk).
- **Phase heading:** `^### Phase [0-9]+ — `; any other `###` (such as `### Checkpoint`) is not a phase.
- **Phase fields**, each on its own line: `**Files touched:**` (comma-separated backticked repo-relative paths or globs; a file the phase creates is suffixed ` (new)` after its closing backtick), `**Risk:** low|medium|high`, `**Depends:** none | Phase N[, Phase N…]` (phase numbers only), `**Verify:** R<n>[, R<n>…] — <condition>` (R-ids before the em dash; single line).
- **Sections:** `## Non-goals` and `## Security` are exact headings; `**Before:**` / `**After:**` sit under `## Goal`.
- **Path patterns:** bash `case` semantics — `*` matches across `/` (`scripts/*` covers subdirectories); a path ending in `/` means the whole directory. `**Files touched:**` lines inside fenced code blocks are not phase fields; a phase ends at the next `### ` or `## ` heading.

**Baseline dir.** A `baseline` parity reference points at `plans/<slug>.baseline/` beside the plan, on disk in the memory tree, created by a `### Phase N — Baseline`. `/plan-archive` moves it to `archive/plans/<slug>.baseline/` with the plan. Prefer `vs <git-ref>` when the check can be re-run at a ref; a stored snapshot drifts with the tree.

**Lint rule 20** (`lint-memory.sh`; WARN only, every line prefixed `plan-contract:`) applies to plans with `status: draft` or `in_progress` and `created:` on or after the cutover `2026-11-08` (`PLAN_CONTRACT_SINCE` in `scripts/_lib.sh`, the one definition read by rule 20 and `check-plan-drift.sh`). Plans created earlier are not linted. Checks:

| | Check |
|---|---|
| a | at least one `R` criterion line |
| b | every `R` line carries a tag; a line starting `- R<n>` or `- **R<n>` that is not `- R<n> [acceptance\|parity] ` is malformed |
| c | every `**Verify:**` cites at least one existing R-id |
| d | every R-id is cited by at least one `**Verify:**` |
| e | every `### Phase N` has `Files touched`, `Risk` and `Depends` matching the grammar, and exactly one `**Verify:**` citing at least one R-id; a `### Phase <n>` line not in the em-dash form, or a field line outside any `###` section, also warns |
| f | `## Non-goals` is present |
| g | every `[parity]` line names `vs` or `baseline` as above; a `baseline` form requires a `### Phase N — Baseline` |
| h | any `Risk: high` phase requires `## Security` |
| i | `**Before:**` and `**After:**` are present under `## Goal` |
| j | a live plan with no `created:`, or one not matching `YYYY-MM-DD`, warns rather than falling out of scope |

Rule 20 checks shape, not truth: whether a `Verify` line actually proves the R-id it cites is the validator's judgement.

## Domain file body

Just `## Knowledge`. Entries append as `**[YYYY-MM-DD]** what — why it matters`.

## Project wiki pages (`projects/<project>/wikis/<slug>.md`)

Reference detail too large for `memory.md` — a TLS chain, an audit baseline, a component design — goes in a
wiki page. Wiki pages are never injected, indexed or triggered: the only way one loads is Claude following a
link to it, so **every page is linked from its project's `memory.md` `## Pointers`** as `wikis/<slug>.md`.
Wiki pages are not archived, so the path stays stable.

```yaml
---
topic: rabbitmq-pas-service TLS configuration
scope: project
summary: One line — what the page covers, specific enough to decide whether to open it
reviewed: 2026-10-17                  # date the page was last checked against its source
repo: git@github.com:org/repo.git     # optional — the repo the page describes
category: platform                    # optional
---
```

`topic`/`scope`/`summary`/`reviewed` are required; `repo`/`category` are optional. Bump `reviewed` when the
page is re-verified, not on every edit. Nothing lints wiki pages — the convention is held by review.
A wiki page holds what stays true; findings gathered before a task exists are an investigation instead.

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
- [YYYY-MM-DD] <bullet>

**Next:**
- <bullet>

**Blockers:**
- <bullet or None>

**Resume:** <one line — file to open, where to start>
```

`## Checkpoints` is the last section of the file, so an end-of-file append lands inside it; lint rule 19 warns on a checkpoint entry outside it. An entry has five fields (Task, Done, Next, Blockers, Resume) and there is one living entry per piece of work, matched by the identifiers (`plan <slug>`, `task <ref>`, `PR #<n>`) in its `**Task:**` paragraph. A continuation rewrites the entry in place and moves it to the bottom: the heading keeps its start date, Done gains one dated `- [YYYY-MM-DD]` group per run (older groups untouched), and Next/Blockers/Resume are replaced. Section order is therefore last-touched, not start-date; work that matches no entry appends a new one. `/checkpoint` synthesizes all five fields from the current session's context — it does not interview you. If a session produced no artifacts, the entry should say so honestly, with a Done bullet like:

```markdown
**Done:**
- [YYYY-MM-DD] Discussion only — no artifacts produced
```

### Why the `/checkpoint` rules

`commands/checkpoint.md` states the rules; this is why they are shaped that way, with the examples that settled them.

- **Plan slug outranks task and PR.** When both sides name a plan, the plan is the piece of work: a shared task or PR never folds a session into an entry about a different plan. The rank matters for legacy entries: one whose Task names only `#147` must not win over the entry that names the plan, even when it sits lower in the file.
- **PR numbers in legacy lines.** Older Task lines list PRs bare, `(#125, #126)`; a `#<n>` counts only where it reads as a PR, not an issue number or a count. New Task lines write `PR #<n>`. Identifiers compare literally, so `plan X` and `task X` never match each other — name both when both apply.
- **The Task paragraph is the only key.** An entry whose Task names no identifier can never be matched again. That is deliberate for a session with no piece of work: its entry is a one-off.
- **Matches are computed before any write.** A rewritten entry moves to the bottom; matching again after a write would let it become another piece's bottom-most match.
- **Several pieces in one session.** A session that closes plan A and runs phase 4 of plan B updates A's entry and B's entry separately, and `plan A` never appears on B's Task. Work that belongs to no piece (housekeeping such as pruning symlinks) and side items go into the last entry written.
- **Step 3a runs once per session**, not per piece, because it asks a whole-session question.
- **Lookups annotate; only the session closes.** Five validation rounds each found a phrasing where a terminal tracker state closed an item that was still live: a precondition mention ("rebase once PR #50 merges" — #50 merging does not mean the rebase happened), a plan not yet created, a same-named box in another plan's section. With annotate-only, an unforeseen phrasing leaves an item open (a nudge), never loses it; `/checkpoint-archive` checks open items again at roll time.
- **Moves are recorded, not performed.** `moved to task <ref>` is right after the user ran `/task add` for the item this session; a plan that exists but does not name the item is not a home.
- **Pointers, not copies.** What `todo.md`, a plan or an initiative tracks lives there. A prior Next bullet "Phases 3–4; also bump CHANGELOG" becomes two Next items: "remaining phases: todo.md" and "bump CHANGELOG".
- **Same-day groups.** Every run appends its own `[today]` group, so older groups stay byte-identical. A second run on the same day appends more `- [today]` bullets with no separator, so the two groups read as one; that is accepted.
- **Side items are nudged, never captured.** In an entry about plan foo, "mark the Notion project-scan task done" is a side item and gets a task-candidate line; foo's phases, PR and close-out close with the entry and need no other home. Capturing the task automatically would be a backend write the user never approved.
- **Resume** points a cold session at a spot, e.g. "open `scripts/foo.sh`; `parse()` is stubbed at L40 — wire it to `_lib.sh:bar` next". The report's per-entry summary is one line, e.g. "agent-friendly Terraform refactor — Track A files ready, awaiting go-ahead".

### Per-worktree overlays (`working.<key>.md`)

Two concurrent sessions on one repo run in separate git worktrees (a checkout has one HEAD, so concurrency *requires* it). They would otherwise share one `working.md` and clobber each other's checkpoints. To prevent that, the scratchpad is resolved per session: in a **linked git worktree** the working file becomes `working.<worktree-name>.md`; in the main checkout it stays `working.md`. `memory.md`, `todo.md`, `index`, and `plans/` are always shared — only the volatile scratchpad splits.

The key is chosen with precedence **explicit marker > worktree > none**:
- Drop a `.agents/memory-session` file in the checkout (sibling to `.agents/memory-project`) to name the overlay explicitly — its content is sanitized to `[a-z0-9-]`, so `feature-x` → `working.feature-x.md`. Use this to label a split, or to force one without a worktree.
- Otherwise a linked worktree auto-keys on its own name; the main checkout gets the base file.

The resolver (`resolve_working_file` in `scripts/content-core.sh`) is shared by every harness's read and write path, so the injected `<memory:active>` breadcrumb, the full payload, and `/checkpoint` all agree on the same file. Overlays are gitignored (`working*.md`) like the base scratchpad.
