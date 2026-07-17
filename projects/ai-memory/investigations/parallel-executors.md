---
kind: investigation
task_ref: 3a0f6850-c619-8181-8476-d7b8e8c45dd7
slug: parallel-executors
status: scoped (agent-persona + parallel, all harnesses); awaiting /start brainstorm gate
created: 2026-07-17
---

# Agent-specialized & parallel executors

**Product vision (user, 2026-07-17):** run executors as *specialized agents* — e.g.
review work as a kubernetes-engineer AND a security-engineer in parallel; and when a
task matches a known agent's domain, auto-select that agent to run with the executor.
The parallel-dispatch mechanism (below) is the substrate; the **persona dimension** is
the headline.

## Persona dimension — most of it already exists
- `agents/` is a **tracked engine store**: each `<name>.md` carries `name`,
  `description`, `tools`, `model` frontmatter (kubernetes-specialist,
  terraform-engineer, azure-infra-engineer, devops-engineer, …). The `description`
  field is the **same match-by-description model skills use** for auto-discovery.
- Delivered to Claude only: `agents_dir` is declared solely in
  `harnesses/claude/manifest` → `~/.claude/agents/`, picked by the Agent tool's
  `subagent_type` (Workflow's `agent()` takes `agentType:`).

### Gaps to close
1. `executor.sh` has **no persona dimension** — it resolves `harness[:model]`
   (which backend), never *what persona*. Add `--agent <name>`.
2. **Only Claude receives agents.** No CLI-plane path to run "as" an agent.
3. **No auto-match reader** on the harness-neutral path — nothing scores
   `agents/*.md` descriptions against a task to pick one.

### Unifying design — agent = persona layered onto an executor
An agent is a persona (system-prompt body + `tools` scope + `model`) that layers onto
any executor. Harness-neutral because the agent `.md` body is portable prompt text.
- **Subagent plane (Claude):** `--agent k8s-specialist` → Agent tool
  `subagent_type: k8s-specialist` (exists at the tool layer; just not exposed via
  executor.sh).
- **CLI plane (codex/copilot):** prefer the harness-native agent mechanism (copilot
  custom agents); else **prepend the agent body** as persona to the `--run` prompt and
  apply its `tools`/`model`. No per-harness agent system required.

### The two modes
- **Multi-persona review** = the parallel `--run-many` below where the axis is the
  persona (same diff, N lenses). Natural home: the **validate role** (perspective-
  diverse verify).
- **Agent auto-match** = a matcher scoring the task against `agents/*.md` descriptions
  — reuse the skills-discovery approach.

---

# Parallel executors — coordination layer over the reentrant core

## Current state (verified this session)
- `executor.sh` is **stateless + reentrant**: pure resolution + a single `--run`
  exec, no lock/state file. Concurrent `--run` invocations are already safe.
- **Dispatch parallelism already exists**: the orchestrator fires CLI executors
  as `run_in_background` tasks (independent processes); the Claude subagent plane
  runs concurrent Agents, and the **Workflow tool** offers real fan-out
  (`parallel`/`pipeline`, concurrency cap, aggregation) — but that is
  harness-specific, not part of the cross-harness `executor.sh` abstraction.
- Heterogeneous executors already work per-invocation via env override
  (`AI_MEMORY_EXECUTOR_TASK=codex …` alongside `…=copilot …`) — the config model
  is a default, not a singleton lock.

## The gap
No **coordination** primitive in the harness-neutral layer: no work-splitting,
shared queue, result fan-in/merge, or cross-executor dedup. A codex/copilot
orchestrator can only hand-fire N background `--run` calls. Claude's Workflow
tool fills this for Claude only — closing that gap for the other harnesses is the
actual design question.

## The real hazard
Concurrent **read** executors are trivially safe (injection is read-only;
session/sentinel state is UUID-keyed — copilot validator confirmed no
cross-session collision). Concurrent **write** executors colliding on shared
files or a project's `working.md` is the danger; the engine has no lock there.
**Worktrees** are the existing answer (`/start --worktree`, `isolation:
"worktree"` on Agent/Workflow) — just not wired into `executor.sh`.

## Options (cheapest first)
1. **Doctrine-only** — document a fan-out pattern in `orchestrator.md`: N
   background `--run`s, each self-contained, own worktree for write roles,
   aggregate summaries. Zero engine change; codifies what already works.
2. **`executor.sh --run-many`** — batch wrapper: list of prompts →
   bounded-concurrency dispatch → per-item output paths. Thin coordination over
   the reentrant core; cross-harness.
3. **Manifest `exec_parallel` capability + worktree-per-task** — executors that
   declare safe parallel write get auto-isolated worktrees; wrapper handles
   branch create/cleanup + result collection. Generalizes the Workflow model
   into the harness-neutral layer.

## Scope (user, 2026-07-17): BOTH, all harnesses
Agent-specialized executors **and** parallel dispatch, supported across every
harness (not Claude-only). The persona dimension must work on the CLI plane
(codex/copilot) via prompt-prefix where no native agent mechanism exists.

## Open design questions (for the brainstorm)
Persona dimension:
- `executor.sh --agent <name>` surface: how does it thread to `subagent_type`
  (Claude) vs prompt-prefix (CLI)? Precedence when the harness has a native agent
  mechanism (copilot) vs not (codex)?
- Auto-match: who runs the description-scoring — a new `executor.sh --match-agent`
  helper, or orchestrator doctrine? How is a low-confidence match handled (skip vs
  ask)? Reuse skills-discovery matching or a separate scorer?
- Agent `tools` scope on the CLI plane — map to `--available-tools` (copilot) /
  sandbox flags (codex)? Does an agent's tool scope compose with the role's
  read-only face for validate?
- Fan agents out to non-Claude harnesses (add `agents_dir` to their manifests) vs
  keep them executor-injected only? The latter avoids per-harness agent systems.

Parallel dispatch:
- Where does result aggregation live — wrapper, or orchestrator doctrine?
- Worktree lifecycle for CLI executors (Agent/Workflow auto-manage; a bare
  `codex --run` does not) — who creates/cleans the branch?
- Failure semantics: one item fails → partial results vs abort-all.
- Does this stay a wrapper, or does the Workflow model get pushed down so all
  harnesses share one fan-out engine? (Cross-harness parity is a hard requirement.)
