---
plan: project-categories-activity
status: active
created: 2026-07-02
owner: claude (orchestrator)
task_provider: notion
task_ref: 391f6850-c619-811d-a312-c30ecc123d5f
---

## Goal

Add a **category** (client) grouping to projects — one client per project, declared in the
project's `memory.md` frontmatter — so work can be viewed and reported per client. Two
capabilities ride on it: category-aware `/state` (in-flight work grouped by category, plus a
per-category filter) and an **activity report** (`/activity`) that lists the **plans created
within a time window** (default last 30 days) for a category's projects — useful for reviewing
output or invoicing a client, without presuming either. Category values are **per-instance
personal data**: the mechanism ships in the engine, but the values live only in gitignored files
and never enter git history.

## Success criteria

- [ ] A project can declare `category: <client>` in `memory.md` frontmatter. It can be set via
      `/new-project` (prompt on creation), `/pin <project> --category <client>` (existing project),
      or by hand-editing the frontmatter — all three produce the same on-disk result.
- [ ] `lint-memory.sh` validates `category` **only when present** and **never requires it** (same
      posture as `repo`/`tags`).
- [ ] **No category value appears in any git-tracked file** — verified: real project `memory.md`
      is gitignored; the tracked `ai-memory` meta-project `memory.md` carries no client category;
      `_template` ships an empty placeholder; the activity output artifact is gitignored.
- [ ] `/state` (default) shows every project grouped by category, uncategorized last (system-wide
      view); `/state <category>` filters to that category's projects.
- [ ] `/activity <category> [--since 30d]` lists plans **created in the window** for that category's
      projects — scanning both `plans/` and `archive/plans/` — grouped, showing
      `project · plan title · created · status`. `/activity --all` covers every category.
- [ ] The date window is correct at its boundaries (inclusive cutoff), pinned by a test.
- [ ] Full test suite (`scripts/run-tests.sh`) green, including new/extended state + activity tests.

## Design

**Report unit = plans created in the window, grouped by category — NOT completed tasks.**
Plans already carry `created:` frontmatter, so no task `completed` timestamp is needed and the
report is fully decoupled from the task-provider backend (works regardless of Notion/local).
Rejected alternatives for the "what did I do this period" signal:
- *Completed-task tracking* (add `completed` to the task contract / stamp on Notion done) — more
  plumbing, backend-dependent, and misses the user's actual unit of work (a plan = a unit of work).
  **Deferred/optional**, explicitly out of scope here.
- *Derive from backend metadata* (Notion `last_edited_time` / local mtime) — imprecise; later edits
  move the date.

**Naming:** the report is `/activity`, not `/billing` — the projection (plans per category over a
window) is neutral and serves both contractors invoicing and anyone reviewing output; "billing"
presumed a use case.

### 1 — Category data model + how it's set
- Optional `category:` **string** in `projects/<name>/memory.md` frontmatter (one client per
  project; absent = uncategorized). Single flat value — no nesting, no multi-category (YAGNI).
- **Personal-by-construction:** real project `memory.md` files are already gitignored; only the
  `ai-memory` meta-project is tracked and it carries **no** client category. `_template/memory.md`
  gets an empty `category:` placeholder (tracked, valueless).
- `lint-memory.sh`: accept `category` when present, never error on absence (mirror `repo`/`tags`).
- **Setting it (three equivalent paths — Two-Path honored):**
  - **New project** — `/new-project` interview gains a `category?` question; the answer is written
    into the scaffolded `memory.md` frontmatter (blank = skip).
  - **Existing project** — `/pin <project> --category <client>` — `memory-pin.sh` gains a
    `--category` flag that writes the `category:` frontmatter field (it already writes
    `repo`/`repo_path` to the same file; body left byte-for-byte intact).
  - **Always** — hand-edit the `category:` line in `memory.md`.

### 2 — Category-aware `/state`
- `regenerate-state.sh` already builds the In-Flight table (`project | last touched | current goal
  | open todos`). Add a `category` column (from frontmatter) and **group rows by category**,
  uncategorized last.
- Default `/state` = system-wide, grouped. `/state <category>` = filter to one category's projects.
- Output stays the gitignored, on-demand `state.md` (never auto-injected).

### 3 — Activity report (`/activity`)
- New `scripts/regenerate-activity.sh` + `claude/commands/activity.md` (`/activity`).
- Invocations: `/activity <category> [--since <N>d]`, `/activity --all [--since <N>d]`; default
  window 30 days. *Easy later add:* `--month YYYY-MM`.
- Logic: enumerate `projects/*` → read `category` → for matches (or `--all`), scan `plans/*.md`
  **and `archive/plans/*.md`**, read `created:`, keep plans created within the window → group by
  category → emit `project · plan title · created · status`.
- **Archive read is allowed here** — the "never auto-read `archive/`" rule is about background
  loading, not an explicit user-invoked report command.
- Output is **gitignored** (personal data) — write to stdout and/or a gitignored artifact.

### 4 — Personal-data guarantee
- Category values only in gitignored project `memory.md`; activity artifact gitignored.
- Audit that no client name leaks into a tracked file (`_template`, `ai-memory/memory.md`, decisions,
  test fixtures use fake client names).

## Decisions (locked)
- Category stored as `category:` **frontmatter in `projects/<name>/memory.md`** (gitignored values;
  engine supports the field). Chosen over a central `categories.local.md` map (frontmatter is
  colocated and already parsed by index/state).
- One flat category per project (string), no nesting/multi-category.
- **Category is set via `/new-project` prompt, `/pin --category`, or hand-edit** — the setter is
  in scope (not deferred), reusing `memory-pin.sh` which already writes project frontmatter.
- **Report counts plans by `created` date in the window** — no `completed` field; decoupled from
  the task backend.
- Report command is **`/activity`** (neutral), not `/billing`.
- Query surface: **extend `/state`** (grouping + `<category>` filter + system view) **and add a
  separate `/activity`** command (historical/plans projection ≠ live in-flight projection).
- Category values + activity output are **personal/gitignored**; the mechanism is shipped/tracked.

## Risks / open questions
- **bash-3.2 / macOS date math** for the `--since Nd` window (`date -v-Nd +%F`) is a portability
  gotcha — pin boundary behavior with a test; keep comparisons on `YYYY-MM-DD` string form.
- **`ai-memory` meta-project in `/state`/`/activity`** — it's tracked and category-less; ensure it
  renders under "uncategorized" and never invites a real client label.
- **Deferred:** task `completed`-timestamp tracking (a separate future task if ever wanted);
  `--month YYYY-MM` window selector for `/activity`.

## Phases

Ordered foundation-first (data model + setter → read surfaces → guarantees). Every phase gates on
`scripts/run-tests.sh` staying green.

### Phase 1 — Category field, setter, and lint (data model)
- [x] Add an empty `category:` placeholder to `projects/_template/memory.md` frontmatter (tracked,
      valueless); document the field in `docs/file-formats.md`.
- [x] `lint-memory.sh`: accept `category` when present, never require it (mirror `repo`/`tags`).
- [x] Confirm `extract_fm_field` (in `_lib.sh`) reads `category` — reuse, no new parser.
- [x] `memory-pin.sh`: add a `--category <client>` flag that writes/updates the `category:`
      frontmatter field (body preserved byte-for-byte); surface it as `/pin ... --category`.
- [x] `/new-project` (`claude/commands/new-project.md`): add a `category?` question to the interview;
      write the answer into the scaffolded `memory.md` (blank = skip).
- [x] Tests: extend `test_lint_memory.sh` (present/absent category both pass); extend
      `test_memory_pin.sh` (`--category` writes the field, preserves body).
- **Gate:** lint green with/without `category`; `--category` round-trips; suite green.

### Phase 2 — Category-aware `/state`
- [x] `regenerate-state.sh`: add a `category` column (from frontmatter) to the In-Flight table and
      **group rows by category**, uncategorized last.
- [x] Support `/state <category>` = filter to that category's projects; bare `/state` = system-wide,
      grouped. Update the `/state` command definition accordingly.
- [x] Extend `test_regenerate_state.sh`: grouping order, `<category>` filter, uncategorized bucket.
- **Gate:** grouped + filtered output correct on fixtures; suite green.

### Phase 3 — Activity report (`/activity`)
- [x] New `scripts/regenerate-activity.sh`: `<category>` or `--all`, `--since <N>d` (default 30).
      Enumerate `projects/*` → read `category` → scan `plans/*.md` **and `archive/plans/*.md`**,
      read `created:`, keep in-window → group by category → emit `project · plan title · created ·
      status`. Window via `date -v-Nd +%F`, compared on `YYYY-MM-DD` string form.
- [x] `claude/commands/activity.md` (`/activity`) wraps the script.
- [x] Gitignore the activity output artifact (personal data); write stdout + optional gitignored file.
- [x] New `test_activity.sh`: window boundary (inclusive cutoff), archive-plans inclusion, `--all`
      vs single category, uncategorized excluded from a named-category run, empty-window result.
- **Gate:** report correct incl. boundary + archive; output path gitignored; suite green.

### Phase 4 — Personal-data audit + docs
- [ ] Verify `.gitignore` keeps all category values + activity output out of git; add the artifact
      path if not already covered by an existing glob.
- [ ] Audit: no client name in any tracked file — `_template`, `ai-memory/memory.md`, plan/decisions,
      and test fixtures use fake client names only.
- [ ] Docs: `docs/file-formats.md` (the `category` field + how to set it), `docs/scripts.md`
      (`regenerate-activity.sh` + `/activity`, `/state` category flags, `/pin --category`, new
      env/artifact rows), `docs/workflows.md` (a "review a client's work for the month" workflow),
      `docs/harnesses/claude.md` command table.
- **Gate:** `git grep` over tracked files shows no real client value; docs updated; full suite green.
