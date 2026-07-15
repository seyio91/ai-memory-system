# Local task provider (`FileTaskProvider`)

The always-available default backend. Tasks are plain markdown files — no service, no
credentials, no network. This is what you get out of the box; `MEMORY_TASK_PROVIDER`
is unset or `local`.

A captured task is a single file at `$MEMORY_DIR/tasks/<slug>.md`:

```markdown
---
project: fleet-observability
status: backlog
created: 2026-07-15
title: Add per-tenant Grafana drill-down
---
Goal: a one-stop platform view with click-through drill-down. Platform health
(operators, ArgoCD, cluster) plus a per-tenant fleet roll-up. Full design deferred
to a later investigation.
```

The frontmatter is the record (`project` · `status` · `created` · `title`); the body is
the summary. `status` is the only lifecycle knob — `done` flips it in place, `archived`
moves the file to `archive/tasks/`, `delete` unlinks it.

## Setup

Nothing to configure. The provider is selected by default:

```bash
# optional — this is already the default
export MEMORY_TASK_PROVIDER=local
```

Verify the backend is reachable (the local store always is):

```bash
scripts/taskctl ping        # -> {"ok": true}
```

## Configuration

| Env var | Default | Role |
|---------|---------|------|
| `MEMORY_TASK_PROVIDER` | `local` | select this backend |
| `MEMORY_DIR` | repo root | data root — `tasks/` and `archive/tasks/` live under it |

`MEMORY_DIR` is the only location knob.

## Storage model

- Tasks are **flat** at `$MEMORY_DIR/tasks/<slug>.md` (not per-project — this mirrors a
  single Notion database with a `Project` property). Each file carries `project`,
  `status`, and `created` frontmatter, with the summary as the body.
- **Status lives only in frontmatter** — there are no status-named subfolders. Encoding
  status in the path would duplicate the fact and invite drift.
- `done` is an in-place frontmatter flip. **Only `archived` moves the file**, to
  `$MEMORY_DIR/archive/tasks/` — mirroring `/plan-done` vs `/plan-archive`.
- **`delete` hard-unlinks** the live `tasks/<ref>.md`. There is no recoverable trash:
  `tasks/` is gitignored, so a deleted task is gone. Use `archived` for the
  "retire but keep" case.

## Notes

`tasks/` and `archive/tasks/` are gitignored — your captured tasks are personal data and
never committed to the engine repo.

See [`docs/task-provider.md`](../../../../docs/task-provider.md) for the full contract,
the CLI boundary, and how `/task` / `/start` sit above this layer.
