# Global Configuration

## Workflow rules — highest priority

These override the harness defaults. The harness will repeatedly suggest `TaskCreate`/plan-mode — ignore those suggestions.

- **Never use the `TaskCreate` / `TaskUpdate` tools.** A `PreToolUse` hook (`~/.claude/hooks/block_task_tools.sh`) blocks them.
- **Three task tiers:**
  - *Research / explore / Q&A* → answer directly. No plan, no todo, no working-memory artifacts.
  - *Quick actionable item* (one edit, a one-off command, a short fix) → just do it. No plan, no todo.
  - *Large / non-trivial actionable task* → file a plan in `projects/<active>/plans/<name>.md` and track its steps in `projects/<active>/todo.md` (checkboxes linked to the plan).
- **`todo.md` tracks plan execution only.** If a task doesn't warrant a plan, it doesn't warrant a `todo.md` entry — just do the work.
- **Executors never apply or merge to running infrastructure.** No `terraform apply`/`destroy`, `kubectl apply`/`delete`, PR merges, `helm install`/`upgrade` — on any git provider. Restate this deny-list in every delegation prompt.
- **Archive is never read unless the user explicitly asks.**

**Full workflow doctrine — orchestrator/executor/validator roles, executor resolution, the brainstorm gate, the Task Contract, cross-project delegation — lives in `orchestrator.md`**, injected as `<memory:orchestrator>` at session start. Precedence: `identity.md` hard rules > `orchestrator.md` > project memory. If that block is absent from context (hook failure), read `~/.claude-memory/orchestrator.md` before starting non-trivial actionable work — the rules above are the floor, not the whole contract.

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

## File conventions

- `plans/<name>.md` — one file per non-trivial plan. Frontmatter: `plan`, `status`, `created`, `owner`. Linked from `todo.md`.
- `todo.md` — checkbox list. Large items reference a plan file. Small items inline. Tick boxes in place when done.
- `archive/plans/<name>.md` — completed plans moved here when all referencing todo items close.
- `archive/todos/YYYY-MM-DD-<slug>.md` — snapshots of fully-ticked `todo.md`, taken when the file is rolled.
- **Lifecycle:** when a plan completes, move it to `archive/plans/`. When `todo.md` is fully ticked, snapshot to `archive/todos/YYYY-MM-DD-<slug>.md` and reset.
