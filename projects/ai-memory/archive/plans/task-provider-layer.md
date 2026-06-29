---
plan: task-provider-layer
status: done
created: 2026-06-12
completed: 2026-06-12
owner: claude (orchestrator)
task_provider: local
task_ref: <none — meta-project build, not itself a captured task>
---

# Plan — Pluggable task-provider layer

## Goal
Add a `TaskProvider` abstraction to the memory system so tasks can be captured, status-tracked, and executed later, with a swappable storage backend (local filesystem default, Notion remote, Jira-ready) behind a fixed, backend-neutral interface reached only through a JSON-over-stdout CLI. The memory tree stays the source of truth for all detail (plan body + `todo.md`); the backend holds only intent + coarse status (push-dominant from the memory side).

## Success criteria
- `MEMORY_TASK_PROVIDER` (default `local`) selects backend; `local`↔`notion` swap with zero changes to contract/CLI/factory/callers.
- `grep -ri 'page_id\|data_source\|jql\|transition\|notion\|jira'` over contract+CLI+factory files returns nothing; all backend vocab isolated to its provider module.
- Instantiating `TaskProvider` raises `TypeError`; subclass missing any abstract method fails to instantiate.
- CLI exposes `capture|list|get|update|set-status|ping`, prints JSON to stdout, errors via exit code; unknown verb → non-zero + JSON error; non-canonical status rejected before any provider call; `update` accepts only title/summary.
- Local store: flat `$MEMORY_DIR/tasks/<slug>.md`, `project` frontmatter, status in frontmatter only (no status subfolders); `done` flips in place; `archived` moves to `$MEMORY_DIR/archive/tasks/` and leaves `list`.
- Full offline lifecycle test passes (capture→list→update→started→done→archived) for local; Notion offline unit tests pass with canned fixtures; Notion live smoke is **skipped** (not failed) without creds. Whole suite green with no network/creds.
- README documents the provider layer coherently with the brainstorming changes (one pass): dir layout, `MEMORY_TASK_PROVIDER`, local store, how to add a provider, plan frontmatter (`task_provider`/`task_ref`) vs body (`## Design`).
- Documented design checks: a Jira provider fits unchanged (status map→transitions, resolver→pre-existing keys); a `dropped` status adds as one canonical entry without contract change.
- `/start` delegation contract documented, not implemented; nothing in provider layer references brainstorming/tiers/plans.

## Design
Settled shape (build prompt is the design doc). Python 3 stdlib-only package at `scripts/taskprovider/` (`contract.py` = `TaskProvider` ABC + `Task` dataclass + canonical status set; `factory.py` = env-driven selection; `providers/local.py` = `FileTaskProvider`; `providers/notion.py` = `NotionProvider`; `__main__.py` = JSON CLI). Tests under `scripts/taskprovider/tests/` (unittest, temp-dir fixtures) + an optional bash CLI integration test in `scripts/tests/`. Two explicit contract seams (`status_map`, `resolve_project`) carry the only real per-backend variation. CLI is the language-agnostic boundary (JSON stdout + exit codes). `update` is deliberately title/summary-only (the channel for the brainstorm's clarified Goal at `/start`). Alternatives rejected: bidirectional sync (split-brain — rejected for push-dominant projection); status-named subfolders (path/frontmatter drift — rejected); third-party deps like requests/PyYAML (breaks python-optional/no-infra — rejected for stdlib urllib + hand-rolled frontmatter parse).

## Decisions (locked)
- Python 3 **stdlib only** (urllib.request, hand-rolled frontmatter parse, unittest). Bash stays the glue; `inject_memory.sh` never calls the task layer.
- Provider is a per-machine choice via `MEMORY_TASK_PROVIDER`; **no auto-failover** Notion→local.
- Local store flat at `$MEMORY_DIR/tasks/`, each file `project:` frontmatter; status only in frontmatter; `done` flips in place, only `archived` moves (to `archive/tasks/`).
- `MEMORY_DIR` is the only location knob. Secrets (`NOTION_TOKEN`, data-source id) from env only.
- Contract speaks memory vocab only (project/title/summary/canonical-status/ref); `task_ref` opaque to core; provider stored per-plan in frontmatter.
- `add_progress` designed as non-abstract default no-op (not wired this build). Jira + slash-command wiring (`/capture`,`/tasks`,`/start`) out of scope; CLI must be cleanly scriptable for them.

## Phases
### Phase 1 — Contract + CLI boundary
- `TaskProvider` ABC (`capture/list/get/update/set_status/ping` + `status_map`, `resolve_project`), `Task` dataclass, canonical status set, `add_progress` default no-op, factory, `python3 -m taskprovider` JSON CLI. No backend.

### Phase 2 — Local provider (`FileTaskProvider`)
- All methods + both seams against `$MEMORY_DIR/tasks/`; capture/list/get/update/set_status semantics per spec; doubles as test fixture (no separate mock).

### Phase 3 — Test local provider
- `unittest` temp-dir lifecycle test (capture→update→started→done→archived) + field round-trip; optional bash CLI integration test in `scripts/tests/`.

### Phase 4 — Notion provider (`NotionProvider`)
- `urllib`-only, 2025-09-03 API (data_sources query, pages create, page PATCH); `status_map` + text-property `resolve_project`; env creds. Zero changes to Phases 1–3.

### Phase 5 — Test Notion provider
- Offline unit tests with canned fixtures (request bodies, response→Task, status_map round-trips, monkeypatched HTTP) + gated live smoke (skipped without `NOTION_TOKEN`/`NOTION_TEST_DATA_SOURCE_ID`).

### Phase 6 — Docs + design checks (DoD §5–7)
- README provider section (coordinated with brainstorming changes, one coherent pass); documented Jira-fit + `dropped`-status checks; documented `/start` delegation contract (not implemented).

## Risks / open questions
- `python3 -m taskprovider` import path: package at `scripts/taskprovider/`, invoked with `PYTHONPATH=$MEMORY_DIR/scripts` (or cwd=scripts) — document and bake into tests/wrapper.
- README must not contradict the brainstorming-skill README edits (dir layout, slash commands, plan frontmatter vs body, Task Contract) — write as one pass.
- Codex executor writes into the memory tree (workspace-write) — verify no deny-list trip; validate boundary grep-cleanliness independently.
