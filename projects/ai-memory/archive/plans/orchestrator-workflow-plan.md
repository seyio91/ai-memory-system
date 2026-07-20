---
plan: orchestrator-workflow
status: done
created: 2026-05-19
owner: claude (orchestrator)
---

# Plan — Orchestrator/Executor/Validator Workflow

## Goal
Codify a three-role workflow into the memory system so every non-trivial task is:
1. **Planned** by Claude (orchestrator) → file in `projects/<active>/plans/`
2. **Tracked** in `projects/<active>/todo.md` (checkboxes, one item = one unit of executable work, large items link to a per-item plan)
3. **Executed** by Codex via `codex-mem.sh` (workspace-write sandbox, never apply/merge). Fallback: Claude subagent with `sonnet` or `haiku`.
4. **Validated** when the orchestrator's judgment says it's warranted (writes, irreversible ops, ambiguous correctness). Validator is a Claude subagent.
5. **Archived** to `projects/<active>/archive/{plans,todos}/` when complete. Archive is never read unless the user explicitly asks.

## Roles
| Role | Tool | Model | Notes |
|------|------|-------|-------|
| Orchestrator | Claude main session | Opus | Plans, decomposes into todos, delegates non-trivial work. Handles short tasks directly when executor handover would be more overhead than the work itself. |
| Executor (primary) | `codex-mem.sh exec` | gpt-5.5 | Workspace-write sandbox, network on for `gh`, deny list blocks apply/merge |
| Executor (fallback) | Claude `Agent` subagent | sonnet (default) or haiku (lightweight tasks) | Used if Codex stalls, errors, or produces wrong output |
| Validator | Claude `Agent` subagent | sonnet | Independent read of executor output + plan + diff; reports pass/fail with reasons |

## Decisions (locked)
1. **Archive scope:** per-project at `projects/<active>/archive/{plans,todos}/`.
2. **Validation policy:** orchestrator's judgment — not always, not never. Triggers: code writes, terraform changes, anything visible to GitOps, multi-step changes where intermediate state matters.
3. **Codex permissions:** `--sandbox workspace-write` + `-c sandbox_workspace_write.network_access=true` + rules file deny list. The hard "never apply/merge" stays in `identity.md` and `~/.codex/rules/default.rules`.
4. **Todo lifecycle:** check the box in place when done. When `todo.md` is fully checked (or the orchestrator decides to roll), snapshot it to `archive/todos/YYYY-MM-DD-<slug>.md` and reset `todo.md`. Plans archived individually as their items close.
5. **TaskCreate banned:** the harness `TaskCreate`/`TaskUpdate` is not used. `todo.md` is the single source of truth for executable work.

## Phases

### Phase 1 — Rules & documentation
- Update `~/.claude/CLAUDE.md`: add Orchestrator/Executor/Validator section + maintenance rules pointing to `plans/`, `todo.md`, `archive/`.
- Update `identity.md`: add a short "Orchestration" section with the codex-first / subagent-fallback rule and the never-apply/never-merge hard rule for executors.
- Update `README.md`: document the workflow, role table, archive convention, file shapes.

### Phase 2 — Directory scaffolding
- Add `plans/`, `todo.md`, `archive/plans/.gitkeep`, `archive/todos/.gitkeep` to `projects/_template/`.
- Backfill the same in existing projects that don't have them: `claude-memory-system` (this one — partially done), `client-a-argo-apps`, `client-a-charts`, `client-a-infrastructure` (already has `plans/` and `todo.md`).
- Update `scripts/new-project.sh` to scaffold the new structure.
- Update `scripts/lint-memory.sh` to flag missing `todo.md` / `plans/` / `archive/`.

### Phase 3 — Codex permissions
- Edit `~/.codex/rules/default.rules`:
  - **allow**: `git *`, `gh *` (except `pr merge`), `terraform validate`, `terraform init`, `terraform fmt`, `terraform plan`, `helm template`, `kubectl get`, `kubectl describe`, `kubectl logs`.
  - **forbidden** (codex rule decision keyword — `decision="forbidden"`, NOT `deny`/`reject`): `terraform apply`, `terraform destroy`, `kubectl apply`, `kubectl delete`, `gh pr merge`, `helm install`, `helm upgrade`. Generic principle: any destructive or additive action directly to running infrastructure is off-limits to executors.
- Update `scripts/codex-mem.sh`:
  - Inject the orchestrator-workflow rules into `AGENTS.md` (read from `identity.md` after Phase 1).
  - Add a wrapper helper or document the recommended exec command: `codex-mem.sh exec --sandbox workspace-write -c sandbox_workspace_write.network_access=true "<prompt>"`.

### Phase 4 — Slash commands
- `/plan <name>` — scaffold a new plan file in `plans/` with frontmatter.
- `/todo-archive` — snapshot `todo.md` to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
- `/plan-archive <name>` — move a completed plan to `archive/plans/`.
- (Skip a `/todo` viewer command — it's just `cat todo.md`.)

### Phase 5 — Codex sees the workflow
Because `codex-mem.sh` already concatenates `identity.md` and project memory into `AGENTS.md`, Codex picks up the new workflow automatically after Phase 1. No code change beyond Phase 3's `codex-mem.sh` tweak.

## Risks / open questions
- **Codex network access in workspace-write**: needs verification that `gh` works with `-c sandbox_workspace_write.network_access=true`. Fallback: ad-hoc `--sandbox danger-full-access` for explicit gh-heavy tasks (with user nod).
- **Validator drift**: if the validator subagent re-reads the plan and disagrees with the orchestrator's intent, we need a tiebreaker — default: user adjudicates, not auto-retry.
- **Existing plans/todos in `client-a-infrastructure`**: don't migrate; existing structure already matches.

## Acceptance
- A new task started in any project flows through this loop end-to-end without me (orchestrator) executing the heavy work.
- `todo.md` ticks survive the session via the existing memory injection (working memory + project memory).
- Completed plans/todos leave `plans/` and `todo.md`, land in `archive/`, and never reappear in injected context.
