# Task-provider layer

A small Python (stdlib-only) subsystem that lets the memory system **capture tasks, track coarse status, and execute them later**, with a swappable storage backend behind a fixed, backend-neutral interface. It lives at `scripts/taskprovider/` and is reached only through a JSON CLI, so bash and future slash commands call it without knowing the implementation language. **It is opt-in: nothing runs it unless invoked** — `scripts/hooks/inject.sh` and the offline hot path never touch it.

## The model — backend is a projection, not a co-source-of-truth

The memory tree owns all detail: the **plan file** and its `todo.md` checkboxes. The task backend owns only **intent + coarse status** — a thin record of `title + summary + status + project`. Sync is at the **plan level** (one backend task ↔ one plan file), **push-dominant** (the memory system drives status), and **never bidirectional field-by-field**. A genuine conflict is *flagged*, not auto-resolved — the same posture as repo-path drift in lint.

**No plan, no `todo.md` row, and no index entry exists until `start`.** A captured task is backend-resident: nothing that makes work *live* is materialized ahead of it. A **brainstorm may exist before `start`** — it is a design input, not live work, and it is where a long-form design lives while its task summary stays thin (see [Summary is a gate](#summary-is-a-gate)). The backlog lives in the backend; the memory tree holds only started-or-later work plus the design inputs feeding it.

```
backlog ──start──▶ started ──▶ done ──▶ archived      (canonical statuses)
CAPTURED (backend only, no plan yet)   STARTED (plan file exists, linked)
```

## The contract

`TaskProvider` (`contract.py`) is an ABC speaking **only the memory system's vocabulary** — `project, title, summary, canonical status, ref`. It never mentions any backend's concepts (page ids, query shapes, workflow transitions). Members:

| Member | Role |
|--------|------|
| `capture(project, title, summary) -> ref` | Create a backlog task; returns an opaque `ref`. **`summary` is capped at 500 chars** — see [Summary is a gate](#summary-is-a-gate). |
| `list(project, status) -> [Task]` | Tasks for a project in a canonical status. |
| `get(ref) -> Task` | One task, all fields. |
| `update(ref, *, title=None, summary=None)` | **Title/summary only** — the narrow channel for refining the thin record (e.g. pushing the sharpened summary at `/start`). Deliberately *not* a general field writer. A non-`None` `summary` is capped at 500 chars; `summary=None` means *leave unchanged* and is not gated. |
| `set_status(ref, status)` | Move along the lifecycle; non-canonical status is rejected **before** any provider dispatch. |
| `delete(ref)` | **Remove** the task — distinct from `set_status(archived)`, which retires it but keeps the record. Notion trashes the page (`PATCH {archived:true}`, recoverable in Notion's trash); local **hard-unlinks** the live `tasks/<ref>.md`. Acts on the live task only — an unknown or already-archived ref raises. |
| `ping() -> bool` | Backend reachable? |
| `status_map` (seam) | canonical ↔ native status. Identity for local; option names for Notion; **workflow transitions** for Jira. |
| `resolve_project(name) -> handle` (seam) | memory project → native handle. Local checks `projects/<name>/`; Notion uses a text property; Jira a pre-existing key that may legitimately fail. |
| `add_progress(ref, note)` | **Designed, not wired.** Non-abstract **default no-op** so backends opt in. A one-directional, append-only, *summary-level* digest pushed outward at `/checkpoint` (never the full Done/Next/Blockers — those stay in `working.md`). Implemented with the checkpoint wiring later. |

`Task` is an immutable dataclass: `ref, project, title, summary, status, created`. The canonical status set `{backlog, started, done, archived}` is defined once. `task_ref` is **opaque to the core** — never parsed.

The two seams (`status_map`, `resolve_project`) are where backends genuinely differ — near-zero for local, heavy for Jira. Keeping them explicit members is what makes the abstraction real rather than cosmetic.

## Summary is a gate

`summary` is capped at **500 characters**, enforced on write. Over-cap `capture` or `update` raises:

```
summary is 4824 chars; maximum is 500. Write the long form to an investigation in the
task's project (projects/<project>/investigations/<slug>.md), then reference it from
the summary by name — <slug>, not a path: paths move when work is archived, and
the task already carries its project.
```

**Long-form goes in the tree, not the backend.** A design, a rationale, a comparison — write it to `projects/<project>/investigations/<slug>.md`. The investigation is git-tracked, diffable, and reviewable; a 4800-character property is none of those.

An **investigation** is the findings artifact produced while exploring, *before* a task exists. It is conditional — it exists only when an investigation was actually done and its output is too large for the summary. It serves two readers: the task summary points at it by name, and `/start` hands it to the `brainstorming` skill as the seed. It is **not** the brainstorm's output — that goes into the plan (`## Goal`, `## Success criteria`, `## Design`, `## Risks`), never a sibling file.

**Reference it by name, not by path.** A summary says `` design: `release-automation` ``, not `projects/ai-memory/investigations/release-automation.md`. A path moves the moment the work is archived, so a stored path is a latent lie with a timer on it; a name survives the move, and the reader resolves it in the live dir, then `archive/`. The task record already carries its `project`, so a bare slug is unambiguous. Durable memory (`projects/<project>/memory.md`) follows the same rule: name the artifact, never store its path.

**Why a cap, and why *there*.** The backend is a projection (see [The model](#the-model--backend-is-a-projection-not-a-co-source-of-truth)): it owns intent + coarse status, and the memory tree owns all detail. Nothing structural enforced that — so designs got crammed into `summary` until Notion rejected one at 4824 chars. The cap makes the thin record *actually* thin.

The gate lives in `contract.py` (`validate_summary`, applied by `__init_subclass__` to `capture` and `update`, exactly as `validate_status` guards `set_status`). Three consequences follow from that placement:

- It is **backend-neutral**. A `local`-only task obeys it too. The rule descends from *our* model, not from Notion's per-element limit — inheriting a constraint from a backend you don't use would be incoherent.
- It fires **before provider dispatch**, so an over-cap Notion capture never issues an HTTP request.
- A new provider **cannot forget it**. It is not something each backend re-implements.

**Reads are never gated.** Tasks captured before the cap existed keep loading through `get()` / `list()`; they are only forced into compliance the next time someone writes to them. There is no migration.

**Notion's own limit is a red herring.** Notion caps a `rich_text` *element* at 2000 chars and allows 100 of them per array, so chunking would have made the 4824-char write succeed. That fixes the symptom and keeps the disease. At ≤500 chars a summary always fits one element, so the chunking question never arises.

## Choosing a backend

`MEMORY_TASK_PROVIDER` selects the backend (default `local`). This is a **deliberate per-machine choice, never auto-failover** — a machine without Notion configured runs local, full stop; silently falling back Notion→local would re-create the split-brain this design exists to avoid. The factory is a generic registry: the env value *is* the provider module name under `taskprovider.providers.*`, instantiated via its module-level `PROVIDER` class — so adding a backend needs **no factory edit**.

## Local store (`FileTaskProvider`)

The always-available default. Tasks are **flat** at `$MEMORY_DIR/tasks/<slug>.md` (not per-project — mirrors one Notion database with a `Project` property), each carrying `project`, `status`, `created` frontmatter and the summary as body. **Status lives only in frontmatter — no status-named subfolders** (encoding status in the path duplicates the fact and invites drift). `done` is an in-place frontmatter flip; **only `archived` moves the file** (to `$MEMORY_DIR/archive/tasks/`) — mirroring `/plan-done` vs `/plan-archive`. **`delete` hard-unlinks the live `tasks/<ref>.md`** (no recoverable trash — `tasks/` is gitignored, so a deleted task is gone; `archive/tasks/` already serves the "retire but keep" case via `archived`). `MEMORY_DIR` is the only location knob.

## Notion provider (`NotionProvider`)

The first remote backend, same contract, **zero changes** to the contract/CLI/factory/local code (proven by checksum). Uses `urllib.request` only (no `requests`), `Notion-Version: 2025-09-03` (data-source query `POST /v1/data_sources/{id}/query`, page create `POST /v1/pages` parented by `data_source_id`, status/field via `PATCH /v1/pages/{id}`). Reads `NOTION_TOKEN` + `NOTION_DATA_SOURCE_ID` from env — **no secrets in code or the tree**. All backend-specific strings are isolated to `providers/notion.py` (verifiable by grep).

### Notion setup

**1. The database schema the provider expects.** The target Notion data source must carry these properties (names are the constants in `providers/notion.py`):

| Property | Type | Role |
|----------|------|------|
| `Name` | title | task title |
| `Summary` | rich text | the thin summary (refined Goal at `/start`) |
| `Project` | rich text (**not** select) | the memory project name — text so unknown projects validate rather than failing silently |
| `Status` | status **or** select | lifecycle — option names must match the `status_map` (see below) |
| `Claude` | checkbox | the **consume tag** — `list` only returns `Claude = true` rows, so your own cards stay invisible to the provider |
| `Created` | created time | optional — falls back to the page's `created_time` if absent |

**The Notion page *body* is not part of the contract.** The provider reads and writes **properties only** — it never touches page children (no `children` anywhere in `providers/notion.py`). Anything you type into the body of a task page is **silently ignored**: it will not reach `get()`, and it will not reach the plan at `/start`. This is deliberate, not an omission. Reading the body would make the page a second home for detail, which is exactly the split-brain [the projection model](#the-model--backend-is-a-projection-not-a-co-source-of-truth) exists to prevent. When hand-capturing a task with a real design behind it, put the design in `projects/<project>/investigations/<slug>.md` and name it from `Summary` — `` design: `<slug>` `` — the same rule `/task` follows (see [Summary is a gate](#summary-is-a-gate)).

**2. `data_source_id`, not database id.** In the 2025-09-03 API a database is a *container* of data sources; pages live in a data source. Resolve it once:
```bash
curl -s https://api.notion.com/v1/databases/<DATABASE_ID> \
  -H "Authorization: Bearer $NOTION_TOKEN" -H "Notion-Version: 2025-09-03" \
| python3 -c 'import sys,json; print([(x["id"],x.get("name")) for x in json.load(sys.stdin)["data_sources"]])'
```
Take the inner id → `NOTION_DATA_SOURCE_ID`. (Get the database id from the DB URL; share the database with your integration first.)

**3. Status mapping + `NOTION_STATUS_KIND`.** `status_map` maps canonical → native option names: `backlog→Backlog`, `started→In-progress`, `done→Done`, `archived→Archived` (edit the map in `notion.py` to match your board's option labels). If your `Status` property is a **select** (not a Notion *status*-type), set `NOTION_STATUS_KIND=select` (default `status`) — it drives both the write value shape and the query-filter key; the read side handles either. **Notion API limitation:** you can *add* and *reorder* select options but **cannot rename or delete** them via the API (rename = add new + reorder + leave the old vestigial; delete is UI-only).

**4. Env, and the `.zshenv` gotcha.** Selecting Notion is a per-machine env choice:
```bash
# put these in ~/.zshenv (NOT ~/.zshrc)
export MEMORY_TASK_PROVIDER=notion
export NOTION_STATUS_KIND=select          # only if Status is a select
export NOTION_DATA_SOURCE_ID=<data source id>
export NOTION_TOKEN=<integration secret>
```
**Must be `~/.zshenv`, not `~/.zshrc`:** `/task` and `/start` run through Claude's Bash tool, a *non-interactive* zsh, which sources `.zshenv` only (`.zshrc` is interactive-only) — env in `.zshrc` is invisible to the commands. Verify with `scripts/taskctl ping` → `{"ok": true}`.

## CLI boundary

```bash
PYTHONPATH=$MEMORY_DIR/scripts python3 -m taskprovider <verb> ...
# verbs: capture | list | get | update | set-status | delete | ping
```

Prints **JSON to stdout**, signals errors via **exit code** (+ a JSON `{"error": ...}` object). This language-agnostic seam means the Python layer is itself swappable later without touching any caller. The `scripts/taskctl` bash wrapper removes the `PYTHONPATH`/`-m` boilerplate (`taskctl <verb> ...`) and is what the `/task` and `/start` commands call — note it sets `PYTHONPATH` to the package dir while `MEMORY_DIR` stays the independent data root, so a temp/synced data root still imports the real package.

## Adding a provider

Implement the five methods + the two seams in `scripts/taskprovider/providers/<name>.py`, expose `PROVIDER = <YourClass>`, keep all backend vocabulary inside that one file. **Nothing else changes** — not the contract, not the CLI, not the factory. Set `MEMORY_TASK_PROVIDER=<name>`.

**Design check — Jira fits unchanged.** Jira's status change is a *workflow transition*, which `set_status` already allows (it may be more than a field write internally — that's the `status_map` seam's job); its project is a *pre-existing key* that cannot be created on the fly and may legitimately fail — exactly what `resolve_project` is allowed to do. No contract change needed. **A `dropped` status** would be added as one more canonical entry + one `status_map` row per provider — also no contract change.

## `/start` — capture-to-plan, with the brainstorm gate

Tasks reach the memory tree through two commands above the CLI: **`/task`** captures/manages backlog tasks (thin record only); **`/start`** turns a captured task into real plan + todo. The tier classification runs **at start time** against the pulled summary (a captured task carries no tier yet):

- Captured **feature with open design** → `/start` hands the pulled summary to the [`brainstorming`](harnesses/claude.md#skills) skill as its seed (clarify → approaches → sectioned design); the design folds into the plan's `## Goal`/`## Design`/`## Success criteria`/`## Risks`; the linking step writes `task_provider`/`task_ref` into the plan frontmatter, pushes the brainstorm's clarified **`## Goal`** back as the refined summary via `update`, and flips status `backlog → started`.
- Captured **quick/settled** task → skip the brainstorm, scaffold the plan directly.

`/start` is **project-agnostic** — a `ref` is globally unique in the flat store, so it reads the task's own `project` from `get` and scaffolds the plan into *that* project (not the active one), which is why it owns plan placement rather than calling `/new-plan` (which targets the active project). The provider layer stays **oblivious** to all of this — nothing in the contract, CLI, factory, or any provider references brainstorming, tiers, or plans. The seam lives entirely in the `/task`/`/start` command instructions + the `scripts/taskctl` wrapper.

## Testing

`scripts/taskprovider/tests/` (Python `unittest`, temp-dir fixtures) covers the contract, the summary gate, the full local lifecycle (`capture→update→started→done→archived`), and Notion offline (canned fixtures, monkeypatched HTTP). A **gated live Notion smoke** runs the same lifecycle against a real scratch data source only when `NOTION_TOKEN` + `NOTION_TEST_DATA_SOURCE_ID` are set, and is **skipped (not failed)** otherwise. A bash CLI integration test (`scripts/tests/test_taskprovider_cli.sh`) runs in the existing harness. Everything offline passes with **no network and no credentials**.

`scripts/run-tests.sh` runs this Python suite as its own `== taskprovider (python) ==` stage (under the same hermetic env scrub as the bash suite) and **gates its exit code on the result**. Until 2026-07-09 it did not: the runner globbed only `scripts/tests/test_*.sh`, so the Python suite never executed and the reported pass count was bash-only.

The same stage enforces a **provider ↔ test pairing**: every `providers/<name>.py` must have a matching `tests/test_<name>.py`, or the suite fails. Adding a provider needs no factory edit *by design* — so without this check, nothing would ever notice a provider shipping with no tests.
