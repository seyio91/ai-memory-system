---
plan: cross-model-validator
status: done
completed: 2026-07-09
created: 2026-07-08
owner: claude (orchestrator)
task_provider: notion
task_ref: 397f6850-c619-8173-9ba9-f699cbe30596
---

# Configurable cross-model Validator role

## Goal

Add a configurable `validate` role to the executor machinery: `AI_MEMORY_EXECUTOR_VALIDATE` (`harness[:model]`, same grammar and manifest resolution as the executor roles) resolved via `executor.sh --role validate`. Unset defaults to the orchestrator's agent plane (`claude-subagent`) — deliberately NOT the legacy `AI_MEMORY_EXECUTOR` chain — so validation is cross-model by default whenever the executor is a CLI harness. The role is read-only.

## Success criteria

- [x] `executor.sh --role validate --which` prints `subagent` when `AI_MEMORY_EXECUTOR_VALIDATE` is unset, **even with** `AI_MEMORY_EXECUTOR=codex` (or `_TASK`) set — validate does not chain to the executor vars.
- [x] `AI_MEMORY_EXECUTOR_VALIDATE="codex"` → `--role validate --which` prints `cli:codex`, and `--run` execs the manifest's `exec_readonly` command (`codex exec --sandbox read-only …`) with `AI_MEMORY_ROLE=validate` exported.
- [x] `AI_MEMORY_EXECUTOR_VALIDATE="codex:<model>"` appends the filled `exec_model_flag`; `claude-subagent`/`claude:sonnet` style values resolve to `subagent[:model]`.
- [x] A harness with no `exec_readonly` degrades to the subagent plane (same behavior as `explore`), never runs write-capable.
- [x] A configured-but-unavailable CLI validator falls back per `AI_MEMORY_EXECUTOR_FALLBACK` (existing `resolve()` chain, unchanged).
- [x] Antigravity `pretooluse.sh` enforces the read-only allowlist for `AI_MEMORY_ROLE=validate` (not just `explore`); deny-list layer still applies.
- [x] `--show` reports the validate-role vars; `--role` validation and usage string accept `validate`.
- [x] `scripts/run-tests.sh` passes, with new cases in `test_executor.sh` (default, explicit, model suffix, degrade, no-chaining) and `test_antigravity.sh` (validate-role guard).
- [x] Doctrine updated: `identity.md` (Validator bullet), `docs/workflow.md`, `config.local.sh.example`, `projects/ai-memory/memory.md` Architecture Decision (and dropped the now-actioned "Cross-model validator" working note).

## Design

**Chosen: structural default to the orchestrator plane, read-only, uniform role machinery.**

- `executor.sh` grows a third role `validate`. `role_value()` for validate: `$AI_MEMORY_EXECUTOR_VALIDATE` → `claude-subagent`. No fallthrough to `AI_MEMORY_EXECUTOR_TASK`/legacy — that fallthrough is exactly what would re-correlate validator and executor models.
- Resolution reuses `resolve_value()` with the `explore` code path for command selection: `exec_readonly`, degrade-to-subagent when absent. `--run` exports `AI_MEMORY_ROLE=validate` (already generic).
- Guard: `harnesses/antigravity/hooks/pretooluse.sh` widens the read-only gate from `$ROLE = explore` to `explore|validate`.
- Capability floor: auto-selection never appends a `:model` suffix, so the default can never be a deliberately-weak model; a weak validator requires the user to explicitly configure one.
- Rationale: cross-model validation decorrelates *reasoning* errors, not just context. The orchestrator plane is structurally guaranteed to be a different family from any CLI executor and needs no metadata.

**Rejected alternatives**
- *Manifest `exec_family`/`exec_tier` registry + auto-scan* — family and tier are properties of the model, not the harness; a hand-maintained model-tier table rots the week a new model ships.
- *Explicit-only (no default; unset → legacy chain)* — smallest diff, but keeps same-model validation as the default, losing the task's headline benefit.
- *Write-capable validate role* — a validator that can edit can silently repair what it was asked to judge and report PASS.

## Decisions (locked)

- Var name `AI_MEMORY_EXECUTOR_VALIDATE` — symmetric with `_TASK`/`_EXPLORE`.
- Unset → `claude-subagent` (orchestrator plane), never the executor's value.
- `validate` is read-only (`exec_readonly` path + guard enforcement).
- No manifest schema changes; no model-family metadata.

## Phases

- [x] **Phase 1 — executor.sh**: add `validate` to role validation/usage, `role_value()` (no legacy chaining), `resolve_value()` read-only path shared with explore, `--show` output.
- [x] **Phase 2 — Antigravity guard**: widen `pretooluse.sh` read-only gate to `explore|validate`.
- [x] **Phase 3 — tests**: extend `scripts/tests/test_executor.sh` (default/explicit/model/degrade/no-chaining/fallback/ROLE-export) and `scripts/tests/test_antigravity.sh` (validate guard).
- [x] **Phase 4 — docs + doctrine**: `identity.md` Validator bullet + role-var line; `docs/workflow.md` (intro, role table, callout, config table, plan-set note); `docs/system-overview.md`; `docs/scripts.md` env table; `docs/showcase.md` (prose + mermaid); `config.local.sh.example`; `harnesses/claude/CLAUDE.md` roles 2-3; `projects/ai-memory/memory.md` Architecture Decision + cleared the backlog note.

## Risks / open questions

- Precision cost of heterogeneous validation (flags non-issues from unfamiliarity with conventions) — accepted; the orchestrator adjudicates findings.
- Other harness surfaces that restate the validator doctrine (e.g. Codex AGENTS.md build via `content-core.sh`) pick the change up from `identity.md` automatically — verify during Phase 4 rather than assuming.
- `~/.claude/CLAUDE.md` (user-global, outside the repo) also restates the validator doctrine; needs a manual edit or a sync-system pass — flag to the user at the end.
