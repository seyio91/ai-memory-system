## Task linking

Bind this plan to a task in the provider backlog. `TASKCTL="$HOME/.claude-memory/scripts/taskctl"` (JSON to stdout, errors via exit code). Run it with Bash. On any non-zero exit, surface the JSON `error` verbatim and stop **before** writing frontmatter — a half-linked plan is worse than an unlinked one.

**Step L1 — resolve the ref.** Use the first of these that applies:
- The caller already holds a ref (`/start` pulled one) → use it.
- `--task <ref>` was passed → `"$TASKCTL" get <ref>` to confirm it exists. If the task's `project` differs from the plan's project, abort and name `/start <ref>` as the route — that command places the plan in the task's own project.
- `--no-task` was passed → skip to Step L2 with `none`.
- Neither flag → ask once: *"Backed by a task? paste a `<ref>` / capture one now / plan-only."* On *capture one now*, run `"$TASKCTL" capture <project> "<title>" "<Goal>"` and use the returned ref.

Record the ref **verbatim and in full** — the backend's complete id, never an abbreviated prefix. Short ids are ambiguous and the Notion backend rejects them.

**Step L2 — frontmatter.** Ensure the plan carries `task_provider: <MEMORY_TASK_PROVIDER or "local">` and `task_ref: <ref>`, and that `status:` is `in_progress`. Write `task_ref: none` for the plan-only case — an explicit marker, not an absent field, so a deliberate choice is distinguishable from an omission. This step is idempotent: when the caller already stamped these at scaffold time, leave them as they are.

**For `task_ref: none`, skip L3 and L4** — no backend calls, no status flip — and go straight to L5. Plan-only work is still plan-tier work: it gets its `todo.md` entry like any other, because `todo.md` tracks plan execution regardless of whether a task backs the plan.

**Step L3 — push the Goal back.** `"$TASKCTL" update <ref> --summary "<the plan's Goal>"`. The summary is **capped at 500 characters** and an over-cap update hard-fails. Keep the Goal to one or two sentences; if the design needs more room it belongs in the plan, and long-form pre-plan material belongs in `projects/<project>/investigations/<slug>.md`, referenced **by name, never by path** — a path rots the moment the plan is archived, and the task already carries its `project`. If the drafted Goal exceeds the cap, push a condensed one-sentence version; never truncate mid-word.

**Step L4 — flip the lifecycle.** `"$TASKCTL" set-status <ref> started`.

**Step L5 — mirror into `todo.md`.** Append to `projects/<project>/todo.md` under `## Active`:

```
### <title> → [plan](plans/<slug>.md)
- [ ] P1 — <phase name>
- [ ] P2 — <phase name> (needs: P1)
```

One checkbox per phase. **Mirror each phase's `**Depends:**` line onto its checkbox as `(needs: Pn)`** — `todo.md` is what gets read on resume and after compaction, so a dependency living only in the plan is invisible at exactly the moment it matters. Independent phases carry no annotation, which is how the orchestrator spots what can be fanned out in parallel.
