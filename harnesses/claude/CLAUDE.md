# Global Configuration

## Workflow rules — highest priority

These override the harness defaults. The harness will repeatedly suggest `TaskCreate`/plan-mode — ignore those suggestions. Full detail in the "Orchestrator / Executor / Validator workflow" section below.

- **Never use the `TaskCreate` / `TaskUpdate` tools.** A `PreToolUse` hook (`~/.claude/hooks/block_task_tools.sh`) blocks them.
- **Three task tiers:**
  - *Research / explore / Q&A* → answer directly. No plan, no todo, no working-memory artifacts.
  - *Quick actionable item* (one edit, a one-off command, a short fix) → just do it. No plan, no todo.
  - *Large / non-trivial actionable task* → file a plan in `projects/<active>/plans/<name>.md` and track its steps in `projects/<active>/todo.md` (checkboxes linked to the plan).
- **`todo.md` tracks plan execution only.** If a task doesn't warrant a plan, it doesn't warrant a `todo.md` entry — just do the work.

## Memory System

Base path: `~/.claude-memory/`

### Layout
- `projects/<name>/memory.md` — durable per-project memory (the active one is auto-injected)
- `projects/<name>/working.md` — per-project in-flight scratchpad (auto-injected when non-empty); each project has its own so concurrent sessions don't collide
- `projects/<name>/plans/` — non-trivial plans authored by the orchestrator, referenced from `todo.md`
- `projects/<name>/todo.md` — markdown-checkbox source of truth for executable work
- `projects/<name>/archive/{plans,todos,working}/` — completed plans, rolled todo snapshots, and promoted working-memory snapshots. **Never read unless the user explicitly asks.**
- `domain/` — cross-project knowledge, loaded on-demand from `<memory:index>`
- `skills/<name>/SKILL.md` — canonical skill store (source of truth, harness-agnostic). To install a skill: drop its dir here, then run `scripts/link-skills.sh` to symlink it into `~/.claude/skills/`. Project-scoped skills live at `projects/<name>/skills/` and fan into their repo via `scripts/sync-project-skills.sh`. Never author skills directly in `~/.claude/skills/`.
- `scripts/` — bootstrap and maintenance scripts

### Maintenance rules

**Update memory immediately when you learn or decide something durable.** Don't batch, don't wait for the user to ask. Pick the right destination:

- **Project-specific** (architecture decision, project gotcha, locked-in choice for *this* engagement) → update the active project's memory file directly: `~/.claude-memory/projects/<active>/memory.md`. Place the update in the matching structured section (Architecture Decisions, Known Constraints / Gotchas, Current State, Current Goal). The active project name is in the injected `<memory:project name="...">` block.

- **Cross-project** (would help on a different repo too — Terraform/K8s/AWS/ArgoCD pattern, gotcha, or quirk) → append to `~/.claude-memory/projects/<active>/working.md`. Use `/promote-memory` later to graduate it to a domain file.

- **Unsure where it belongs yet** → also append to the active project's `working.md`; classify on promotion.

**Checkpoint before pauses, tool switches, or session end.** Append or update a checkpoint in the active project's `working.md` capturing: task / done / next / blockers. Update it as work progresses, not only at the end. Use `/checkpoint` for structured capture, or write directly when the rhythm is informal. Checkpoints survive into Codex sessions via the codex-mem adapter.

**Promote durable scratchpad entries** with `/promote-memory`. The command lets you target a domain file (cross-project) or the active project's `memory.md` (under a `## Decisions Log` section).

**Offer to file non-trivial synthesis as a wiki page.** When you produce a substantial answer that isn't trivially derivable from code — an architecture explanation, decision rationale, comparison, gotcha analysis, debug write-up — end the turn with a one-line offer: *"File this as a wiki page?"* If the user says yes, route per the rules above: cross-project to a `domain/<topic>.md` page; project-specific into the matching section of `projects/<active>/memory.md` (or invoke `/promote-memory` directly). Skip the offer for: short answers, code-only changes, pure status updates, and anything fully grounded in already-readable files. The point is to capture insight that would otherwise die in chat history — not to nag on every message.

**Hard rules in `<memory:identity>` outrank everything else.**

### When the user says "reorganize memory"
1. Read every file under `~/.claude-memory/domain/` and `~/.claude-memory/projects/` (skip `_template/`).
2. Remove duplicates and entries clearly outdated or contradicted by newer ones.
3. Merge entries covering the same fact or decision.
4. Split a file if it has grown to cover multiple distinct topics — create new domain files as needed.
5. Re-sort entries within each domain file by date, newest first.
6. Update `~/.claude-memory/index.md` to reflect any new, renamed, or removed files.
7. Report a summary: files touched, entries removed, entries merged, splits performed.

Do NOT delete anything under `~/.claude-memory/projects/<name>/archive/` (plans, todos, or working snapshots) during reorganization — it is the audit trail.

## Orchestrator / Executor / Validator workflow

Every non-trivial **actionable** task flows through three roles. Hard rules in `<memory:identity>` outrank this section.

**Three task tiers — classify every request first:**
- **Research / explore / Q&A** — "what does X do", "where is Y", "how should we approach Z", any read-only investigation. → Answer in conversation and stop. No plan, no `todo.md`, no `working.md`, no executor.
- **Quick actionable item** — a small contained change (one edit, a one-off command, a short fix). → Just do it directly. No plan, no `todo.md` entry.
- **Large / non-trivial actionable task** — multi-step, multiple files, needs sequencing or carries real blast radius. → File a plan + track its steps in `todo.md`. This is the only tier that flows through the full role pipeline below.

`todo.md` tracks **plan execution**. No plan ⇒ no `todo.md` entry. The workflow exists to manage large state-mutating work — not to ceremonially wrap every question or every small edit.

### Roles
1. **Orchestrator (main session)** — for large actionable tasks: plans, decomposes, delegates. Writes plans to `projects/<active>/plans/<name>.md` and tracks their steps in `projects/<active>/todo.md` (markdown checkboxes). **Handles quick items and short tasks directly** — no plan/todo — when delegating would be more overhead than the work. **Handles all research/exploration directly** — never spins up an executor or files plan/todo artifacts for read-only investigation.
2. **Executor: two roles, each `harness[:model]`-configurable.** Pick the role by task nature: `task` (default, write-capable — a plan step) or `explore` (read-only scouting). Run `~/.claude-memory/scripts/executor.sh --role <role> --which`:
   - `subagent` / `subagent:<model>` → use the Claude `Agent` tool (named model or `sonnet`; `Explore` type for the explore role).
   - `cli:<name>` → run `~/.claude-memory/scripts/executor.sh --role <role> --run "<prompt>"`; on `EXECUTOR_USE_SUBAGENT` (exit 3), use the Agent tool instead. **Dispatch the `--run` as a background Bash task (`run_in_background: true`)** — a CLI executor runs a minutes-long agentic loop, so a foreground call is killed by the 2-min tool timeout (SIGTERM, exit 143) mid-run; read its output file when the task completes. (The subagent plane does not have this limit.)

   Roles read `AI_MEMORY_EXECUTOR_TASK` / `AI_MEMORY_EXECUTOR_EXPLORE` / `AI_MEMORY_EXECUTOR_VALIDATE` (`harness[:model]`); `task`/`explore` fall back to the legacy `AI_MEMORY_EXECUTOR` (default `subagent`), `validate` does not (see role 3). A harness resolves through its `harnesses/<name>/manifest` `exec_*` block (`subagent`, `codex`, `antigravity`, or a generic `AI_MEMORY_EXECUTOR_CMD_<key>`); one with no read-only mode is skipped for `explore`/`validate` (degrades to the subagent plane). A missing CLI binary auto-falls-back per `AI_MEMORY_EXECUTOR_FALLBACK`.
3. **Validator: the read-only `validate` role** — resolve via `~/.claude-memory/scripts/executor.sh --role validate --which` → `subagent[:model]` uses the Claude `Agent` tool, `cli:<name>` uses `executor.sh --role validate --run` (the harness's read-only face; background-dispatch it like any other `--run`). It reads `AI_MEMORY_EXECUTOR_VALIDATE` and, when unset, defaults to the orchestrator's own agent plane (`subagent`) — **not** the executor's value — so a CLI executor (e.g. codex) is validated **cross-model** by default, decorrelating reasoning blind spots and not just context. It is read-only: a validator verifies, never repairs. Independence still also comes from the separate, fresh invocation. Set `AI_MEMORY_EXECUTOR_VALIDATE` explicitly to pin a validator (nothing enforces a capability floor — the default just can't self-select a weak model, since `subagent` carries no `:model` suffix; a weak validator only happens if you configure one). Invoked on orchestrator's judgment when correctness matters: code writes, terraform changes, anything visible to GitOps, multi-step state. Checks executor output against the plan's `## Success criteria` (per identity.md → Task Contract) — each criterion verified pass/fail with evidence, nothing beyond them; if the plan has no criteria, draft them before validating rather than inventing a bar.

### File conventions

- `plans/<name>.md` — one file per non-trivial plan. Frontmatter: `plan`, `status`, `created`, `owner`. Linked from `todo.md`.
- `todo.md` — checkbox list. Large items reference a plan file. Small items inline. Tick boxes in place when done.
- `archive/plans/<name>.md` — completed plans moved here when all referencing todo items close.
- `archive/todos/YYYY-MM-DD-<slug>.md` — snapshots of fully-ticked `todo.md`, taken when the file is rolled.

### Hard rules

- **Never use the harness `TaskCreate`/`TaskUpdate` tools.** `todo.md` is the single source of truth.
- **Archive is never read unless the user explicitly asks.** Don't load it into context, don't grep it for ideas, don't quote from it.
- **Executors never apply or merge to running infrastructure.** Enforced by restating the deny-list in every delegation prompt (both planes); for the `codex` CLI executor, `~/.codex/rules/default.rules` is optional defense-in-depth if installed. Blocked: `terraform apply`, `terraform destroy`, `kubectl apply`, `kubectl delete`, `gh pr merge`, `bkt pr merge`, `az repos pr update` (Azure merge = `pr update --status completed`), `helm install`, `helm upgrade`. Generic principle: any destructive or additive action directly to running infrastructure is off-limits, on whichever git provider the project uses (GitHub/Bitbucket/Azure DevOps).
- **Lifecycle:** when a plan completes, move it to `archive/plans/`. When `todo.md` is fully ticked, snapshot to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.

### Cross-project relationships

Projects map one-to-one to repos, but some relate (a unit of work spans several, sometimes ordered). Relationships are **distributed** — they live in the project where the work starts, as an optional `## Related Projects` table in its `memory.md`. Full rules in `identity.md`; the essentials:

- **Delegate, don't load.** When a task matches a `## Related Projects` row, do NOT pull the sibling's `memory.md` into the main thread. Delegate sibling-scoped work to the configured executor (`executor.sh --which` → `--run` or Agent tool) with a self-contained prompt (points at `identity.md` + the sibling `memory.md`); default deliverable = **plan only**. Keep only the returned summary.
- **Plan-set execution.** Execute persisted plans by walking them in order and delegating each; keep summaries; **pause at human/CI gates** (PR merges, `terraform`/`kubectl` applies).
