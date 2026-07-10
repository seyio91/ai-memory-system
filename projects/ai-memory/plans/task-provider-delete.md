---
plan: task-provider-delete
status: in_progress
created: 2026-07-10
owner: claude (orchestrator)
task_provider: notion
task_ref: 38ef6850-c619-8126-a5b1-ece8fd5412e5
---

# Task-provider delete interface

## Goal

Give the task provider a first-class `delete` — distinct from `set_status(archived)`, which
only retires a task (Notion: flips the Status property, page persists; local: moves the file to
`archive/tasks/`). `delete` **removes** the task: Notion trashes the page (`PATCH {archived:true}`,
recoverable in Notion's trash); local **hard-unlinks** `tasks/<ref>.md` (decision A, 2026-07-10 —
`archive/tasks/` already covers "retire but keep", so delete earns its name by being gone; `tasks/`
is gitignored, so there is no git safety net and none is emulated).

## Scope note — one cited sub-item is already done

The task summary asks to "make `test_taskctl` hermetic (unset `MEMORY_TASK_PROVIDER`) so tests
never touch the real backend." **Already true**: `test_taskctl.sh:12` unsets
`MEMORY_TASK_PROVIDER NOTION_STATUS_KIND NOTION_TOKEN NOTION_DATA_SOURCE_ID`, and
`test_taskprovider_cli.sh:8` exports `MEMORY_TASK_PROVIDER=local`. No further hermeticity work is
needed; the new delete tests must preserve it (never delete against a live backend).

## Success criteria

Each is mechanically checkable; the Validator verifies pass/fail with evidence.

1. `TaskProvider` declares an **abstract** `delete(self, ref)`; a subclass omitting it fails to
   instantiate (`TypeError`), proven by a contract test.
2. `NotionProvider.delete(ref)` calls `_require_full_ref(ref)` then issues exactly one
   `PATCH /v1/pages/<ref>` with body `{"archived": true}` — asserted offline via the fake-request
   recorder (method, URL, body), and proven to reject a short id **before** any request goes out.
3. `FileTaskProvider.delete(ref)` unlinks `tasks/<ref>.md`; afterward `get(ref)` raises
   `ValueError` (unknown ref) and the task is absent from `list`. Deleting an unknown/absent ref
   raises `ValueError` (no silent success). A task already moved to `archive/tasks/` is **not**
   removed by `delete` (delete acts on the live file only) — asserted.
4. `taskctl delete <ref>` / `python -m taskprovider delete <ref>` prints `{"ok": true}` on success
   (exit 0) and a JSON `{"error": ...}` with non-zero exit on failure — asserted in the shell
   CLI test against the local provider.
5. Both provider unit suites, the contract suite, and the shell CLI tests pass; the full
   `run-tests.sh` stays green (python + bash + lint/doc-vs-code/shellcheck).
6. `docs/task-provider.md` documents the `delete` verb and its archive-vs-delete distinction; the
   doc-vs-code gate stays clean.

## Design

**Contract (`contract.py`).** Add `@abstractmethod def delete(self, ref)`. No `__init_subclass__`
validation wrapper — `delete` takes only a ref, nothing to pre-validate (ref-shape guarding is a
Notion concern, already handled in the provider). Update the three inline `TaskProvider` subclasses
in `test_contract.py` to add a `delete` stub so they still instantiate, and add a positive test
that a subclass missing only `delete` raises `TypeError`.

**Notion (`notion.py`).**
```python
def delete(self, ref):
    _require_full_ref(ref)
    self._request("PATCH", self.API_ROOT + "/pages/" + ref, {"archived": True})
```
Page-level `archived:true` is Notion's trash — distinct from the Status="Archived" property that
`set_status` writes. A trashed page drops out of `data_source` queries (so it leaves `list`), and
`get` on it will surface the API's archived response; we do not add special get handling.

**Local (`local.py`).**
```python
def delete(self, ref):
    path = self._live_path(ref)   # raises ValueError on unknown/absent live ref
    path.unlink()
```
Reuses `_live_path`, which already raises `unknown live task ref` — so unknown-ref and
already-archived (moved out of `tasks/`) both fail loudly, satisfying criterion 3.

**CLI (`__main__.py`).** Add a `delete` subparser (`ref` positional); dispatch
`provider.delete(args.ref)` → `emit({"ok": True})`. The `taskctl` wrapper needs no change (it
`exec`s the module verbatim); update its usage comment to list `delete`.

**Tests.** `test_notion.py`: assert the PATCH body + short-id rejection (mirror
`test_ref_methods_reject_short_ids`). `test_local.py`: extend the lifecycle — delete a backlog
task, assert file gone + `get` raises + absent from `list`; assert deleting an unknown ref raises;
assert deleting an archived ref raises. `test_taskprovider_cli.sh`: capture → delete → assert
`{"ok": true}` and the file is gone; delete a bogus ref → assert JSON error + non-zero exit.

## Risks / non-goals

- **Not** touching `set_status(archived)` semantics — archive and delete stay separate operations.
- **No** local recoverable trash (decision A). If that's ever wanted, it's a follow-up; the abstract
  method's signature (`delete(ref)`) does not preclude it.
- The Notion live test stays creds-gated and self-cleans; do not add a live delete test that could
  leak or hammer the real board — offline fake-request coverage is the floor.
- Adding an abstract method is a breaking contract change for any out-of-tree provider; the only
  providers are in-tree (local, notion), both updated here.
- **Accepted cross-backend idempotency asymmetry** (validator observation, 2026-07-10): a *double*
  delete raises locally (unknown live ref → `ValueError`, the intended "no silent success") but
  Notion accepts a repeat `PATCH {archived:true}` on an already-trashed page without error. Both end
  states are identical (task absent from `list`); only the double-delete failure behaviour differs.
  Left as-is — making Notion symmetric needs a GET-before-delete round-trip to check archived state,
  an extra API call and more code for a marginal guarantee.
