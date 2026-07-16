# Orchestrator / Executor / Validator workflow

**Three task tiers — every request is classified first:**

| Tier | Example | What happens |
|------|---------|--------------|
| Research / explore / Q&A | "what does X do", "how should we approach Y" | Answer directly. No plan, no todo, no working memory, no executor. |
| Quick actionable item | one edit, a one-off command, a short fix | Just do it. No plan, no `todo.md` entry. |
| Large / non-trivial actionable task | multi-step, multiple files, real blast radius | Plan file + `todo.md` step tracking; flows through the role pipeline below. |

`todo.md` tracks **plan execution** — no plan means no `todo.md` entry. Only the third tier flows through the orchestrator/executor/validator roles. The orchestrator is whichever harness is running the main session; the executor is selectable (`subagent` by default, or a configured CLI like `codex`); the validator is its own selectable, **read-only** role that defaults to the orchestrator's agent plane — so a CLI executor is checked **cross-model** by default.

## Roles

| Role | Tool | Model | Responsibility |
|------|------|-------|----------------|
| Orchestrator | main session | per harness | Plans, decomposes into `todo.md` items, delegates non-trivial work. **Handles short tasks directly when delegating would be more overhead than the work. Handles all research/exploration directly — no plan/todo/executor for read-only investigation.** |
| Executor | selectable via `AI_MEMORY_EXECUTOR[_TASK]` (see [Executor selection](#executor-selection)) | per executor | Writes code/config in the workspace; runs read-only commands; never applies/merges to infra. `subagent` (in-harness Agent tool, `sonnet`/`haiku`) by default; `codex` or another CLI when configured. |
| Validator | selectable via `AI_MEMORY_EXECUTOR_VALIDATE` (resolve via `executor.sh --role validate --which`); **read-only**; defaults to the orchestrator's agent plane | per validator | Independent check on executor output. **Read-only** — it verifies, never repairs — so it resolves through the harness's `exec_readonly` face and degrades to the subagent plane when a harness has no read-only mode. When its var is unset it defaults to `subagent` (the orchestrator's own plane), **not** the executor's value, so validation is **cross-model by default** — a CLI executor is checked by a decorrelated model. Independence still also comes from it being a **separate, fresh invocation** against the plan's `## Success criteria` (see [Task Contract](#task-contract)) — each criterion pass/fail with evidence, scope capped to exactly those. Invoked on orchestrator's judgment when correctness matters: code writes, terraform changes, GitOps-visible ops, multi-step state. |

> **Validator = read-only, cross-model by default, separate invocation.** The orchestrator runs
> `scripts/executor.sh --role validate --which` and invokes that backend (`subagent[:model]` →
> Claude `Agent` tool; `cli:<key>` → `executor.sh --role validate --run`) with a validation
> prompt. With `AI_MEMORY_EXECUTOR_VALIDATE` unset, that backend is the orchestrator's own agent
> plane — so if execution ran on `codex`, validation runs on a decorrelated model, catching
> shared *reasoning* blind spots, not just shared context. Set `AI_MEMORY_EXECUTOR_VALIDATE`
> explicitly to pin a specific validator (nothing enforces a capability floor — the default just
> can't self-select a weak model, as `subagent` carries no `:model` suffix). The
> independence that makes validation meaningful comes from the **separate invocation against the
> Success criteria** — now reinforced by model decorrelation.

## Task Contract

Every plan-tier task carries explicit **success criteria** — the observable, checkable conditions that define "done." This is the contract the validator checks against; without it, "done" is opinion. Defined in `orchestrator.md` → `### Task Contract` (injected every session).

- **Plan-tier only.** Quick items and research/Q&A are exempt — no criteria for a one-line edit or a question.
- **Best-effort by default.** If the user doesn't state criteria, the orchestrator drafts them from session context and surfaces them before executing — never blank. **For feature-tier tasks routed through the `brainstorming` skill, this seam is tighter:** success criteria are derived *with* the user during the clarify pass, so they are collaboratively-agreed rather than orchestrator-guessed — an upgrade of this rule for the one tier where the design is worth examining, not a parallel mechanism.
- **Checkable, not aspirational.** Each criterion is verifiable by reading output, running a command, or inspecting state ("`terraform validate` passes and the module exposes output `X`", not "works well").
- **Lives in the plan.** Captured in the plan's `## Success criteria` section, scaffolded by `/new-plan`. The validator checks executor output against exactly these.

Enforcement is **template-only** — `/new-plan` scaffolds the section; no hook gates it. The best-effort-fill rule is what keeps a criteria-less plan from slipping through.

## File conventions

- `projects/<active>/plans/<name>.md` — one file per non-trivial plan. Frontmatter: `plan`, `status`, `created`, `owner`, plus optional `task_provider`/`task_ref` (written by the `/start` task-linking step when a plan is backed by a captured task — see [Task-provider layer](task-provider.md)). Body carries `## Goal`, a required `## Success criteria` (the Task Contract), the `## Design` section (populated by the [`brainstorming`](harnesses/claude.md#skills) skill for feature-tier plans), `## Phases`, and `## Risks / open questions`. The frontmatter `task_*` fields and the body `## Design` section occupy different regions of the file and never conflict. Linked from `todo.md`.
- `projects/<active>/todo.md` — markdown-checkbox list. Large items reference a plan file. Small items inline. Tick boxes in place when done.
- `projects/<active>/archive/plans/<name>.md` — completed plans, moved when their referencing todo items all close.
- `projects/<active>/archive/todos/YYYY-MM-DD-<slug>.md` — snapshots of fully-ticked `todo.md`, taken when the file is rolled.

## Executor selection

The orchestrator delegates actionable work to a **selectable executor**, configured in `config.local.sh`. Selection is per **role** (`task`|`explore`|`validate`), each a `harness[:model]` value; the validator is its **own** knob, not the executor's.

| Key | Default | Meaning |
|-----|---------|---------|
| `AI_MEMORY_EXECUTOR_TASK` | (legacy `AI_MEMORY_EXECUTOR`, else `subagent`) | Write-capable executor for a plan step (`--role task`). |
| `AI_MEMORY_EXECUTOR_EXPLORE` | (legacy `AI_MEMORY_EXECUTOR`, else `subagent`) | Read-only scouting executor (`--role explore`); a harness with no read-only mode degrades to the subagent plane. |
| `AI_MEMORY_EXECUTOR_VALIDATE` | `subagent` (does **not** chain to the legacy var) | Read-only validator (`--role validate`). Defaulting to the orchestrator plane makes validation cross-model against any CLI executor; degrades to the subagent plane if a harness lacks a read-only mode. |
| `AI_MEMORY_EXECUTOR` | `subagent` | Legacy single var — fallback for `task`/`explore` only. Built-ins: `subagent` (the orchestrating harness's own subagent plane — Claude's Agent tool, Copilot's background agents; `claude-subagent` accepted as a legacy alias), `codex` (CLI via `codex-mem.sh --executor`). Any other value names a generic CLI executor. |
| `AI_MEMORY_EXECUTOR_CMD_<key>` | — | Command template for generic CLI executor `<key>` (`{prompt}` substituted, already shell-quoted; `<key>` is `[A-Za-z0-9_]+`). |
| `AI_MEMORY_EXECUTOR_FALLBACK` | `subagent` | Used when the preferred CLI binary is absent. Empty = hard-fail. |

To delegate (or to validate), the orchestrator runs `scripts/executor.sh --role <role> --which`, which resolves config + availability and prints `subagent[:model]` or `cli:<key>`:

- `subagent` → use the Claude `Agent` tool.
- `cli:<key>` → run `scripts/executor.sh --role <role> --run "<prompt>"`, which execs the CLI executor (for `codex`, `codex-mem.sh --executor "<prompt>"`; validation uses the harness's read-only face — e.g. `codex exec --sandbox read-only`); if it prints `EXECUTOR_USE_SUBAGENT` (exit 3), use the Agent tool instead. **Dispatch a `cli:` `--run` as a background task** (in Claude, `run_in_background: true`): the CLI runs a minutes-long agentic loop, so a foreground call is killed by the harness tool timeout (in Claude, 2 min → SIGTERM / exit 143) mid-run. It is one-shot and self-terminating — read its output when the task completes. The `subagent` plane runs in-harness and has no such timeout. Add `--clean` (`--run --clean`) to emit ONLY the final agent message — uniform across harnesses, so a backgrounded output file is directly consumable: codex via its `exec_last_message` (`-o <file>`), while a harness without that key (e.g. `agy -p`) passes its already-final stdout through. On success clean output is just the message (+ one trailing newline); on a non-zero exit the CLI's exit code propagates and its stderr is surfaced for debugging.

`--show` prints the resolved selection for debugging. A missing CLI binary auto-falls-back to `AI_MEMORY_EXECUTOR_FALLBACK` (default `subagent`), so an unconfigured machine always has a working executor — and, since `validate` defaults to the always-available subagent plane, a working validator.

## Hard rules

- **No `TaskCreate`.** `todo.md` is the single source of truth for executable work.
- **Archive is never read unless the user explicitly asks.** Don't load it, grep it, or quote from it.
- **Executors never apply or merge to running infrastructure.** Enforced by restating the deny-list in every delegation prompt (both planes) and in `orchestrator.md`; for the `codex` CLI executor, `~/.codex/rules/default.rules` is optional defense-in-depth if installed: `terraform apply`, `terraform destroy`, `kubectl apply`, `kubectl delete`, `gh pr merge`, `helm install`, `helm upgrade`. Generic principle: any destructive or additive action directly to running infrastructure is off-limits to executors.

---

# Cross-project relationships

Projects map one-to-one to repositories, but some repos relate: a single unit of work spans several, sometimes with ordering (e.g. infra in one repo must apply before deployment in another). Relationships are **distributed** — they live in the project where the work starts, not in an umbrella.

**The map — `## Related Projects`.** A project that reaches into others carries an optional `## Related Projects` table in its `memory.md`:

| Project | When it's involved | It owns / entry point |
|---------|--------------------|------------------------|
| <other> | <trigger condition> | <what it owns — entry file/path> |

Because `memory.md` is injected wholesale on the first prompt (Claude) and built into `AGENTS.md` on every launch (Codex), this table is always in context — so the active project *knows* its relationships before anything else is loaded. The "When it's involved" column is the trigger; "It owns / entry point" gives the sibling's starting file so a delegate lands somewhere concrete.

The table deliberately carries **no on-disk path**. A delegate that needs to inspect the sibling's *code* resolves the checkout with `resolve_repo_path <sibling>`, which reads `repo_path`/`repo` from the sibling's own frontmatter (see [Reverse map](install.md#reverse-map-project--checkout)). The path lives in one place — the sibling's `memory.md` — and is resolved per environment, so it is never duplicated into (and never goes stale in) the relationship table.

**The hop — delegate, don't load.** When a task matches a row, the orchestrator does **not** load the sibling's `memory.md` into its own thread (that would bloat context, especially across several siblings). Instead it delegates the sibling-scoped work to an **executor** (selected via `AI_MEMORY_EXECUTOR` — `subagent` by default, or a CLI like `codex`). The `orchestrator.md` rule makes this dependable.

**Delegation contract:**
- *Dispatch* — the prompt is self-contained, because the delegate does not inherit the orchestrator's context: it points at `identity.md` (hard rules / executor deny-list) and `projects/<sibling>/memory.md`, states the task, and sets the default deliverable to **plan only** (no edits to the sibling repo).
  - *Codex caveat:* a `codex-mem.sh` launch builds `AGENTS.md` from the **active** project, not the sibling. So when the executor is Codex, either (a) pin the sibling repo (`.agents/memory-project`) and launch Codex there so its `AGENTS.md` resolves to the sibling, or (b) pass the sibling's `memory.md` path explicitly in the prompt for Codex to read with its shell tool. A Claude `Agent` subagent has no such caveat — it just reads the files named in the prompt.
- *Work* — the delegate produces the core plan and persists it to `projects/<sibling>/plans/<name>.md` (frontmatter `plan`, `status: active`, `created`, `owner`).
- *Return* — a compact, structured summary: `project`, `goal` (one line), `plan` (ordered core steps), `entry points`, `depends on / ordering`, `plan file` (path), `blockers`.

The orchestrator keeps only the summary in context and re-opens the plan file on demand if it needs the detail — which is how the main thread coordinates a multi-repo sequence without resident sibling memory. Implementation is a separate, explicit delegation later. For a trivial one-line touch, the orchestrator just reads the single relevant file instead of delegating.

**Executing a plan set.** Planning and execution are separate. To *execute* persisted plans (e.g. the set an onboarding produces), the orchestrator walks them in their documented order and delegates **each** plan to an executor — Codex via `codex-mem.sh --executor`, or a Claude `Agent` subagent as fallback — with a self-contained prompt pointing at `identity.md`, the plan file, and the project `memory.md`; the executor implements the edits in the repo and returns a compact summary (changed files + the PR/apply action needed). A validator pass (the read-only `validate` role, cross-model by default) optionally checks correctness-sensitive edits (e.g. Terraform). The orchestrator keeps only the summaries, so execution stays context-lean, and it **pauses at human/CI gates** — PR merges and `terraform`/`kubectl` applies, which executors are forbidden to perform — resuming the next phase on the user's confirmation. This is generic: any multi-repo plan set is executed this way.
