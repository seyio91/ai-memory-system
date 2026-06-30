# POS (Personal Operating System) — Concepts & Comparison

Source: Abubakar Siddiq Ango's 5-part blog series "Building a Personal Operating System for AI-Assisted Development" (abuango.me, Mar 2026). Open source at `github.com/abuango/pos-ai`. Captured from `~/Downloads/explore-pos/{0..5}.md`.

This page does two things: (1) documents the vital concepts of POS, and (2) compares them against **our** memory system (the one in this repo), flagging what to adopt and where the approaches genuinely differ.

---

## 1. What POS is

A file-based "operating system" that turns a single git repo into a command center for managing **multiple professional contexts** (day job, freelance clients, side products, learning) through any AI coding tool. Core thesis: *AI coding tools are individually powerful but collectively forgetful.* POS makes the filesystem the shared memory that any tool can read, any model can follow, any session can resume.

Five hard constraints it was built to satisfy:
1. Persist state across sessions (no manual re-explanation)
2. Work with **any** AI tool (no vendor lock-in)
3. Load context efficiently (token budgets are real → tiered loading)
4. Track work reliably (durable record of every task/decision/handoff)
5. Zero external dependencies (no DB, no cloud, no SaaS — works offline)

The motivating pain was concrete: ~50–75 min/day lost re-establishing context across 5 active projects.

---

## 2. Vital concepts

### 2.1 Everything Is a File
The one architectural axiom. No DB, no API, no plugin layer. **"The filesystem is the API. Git is the database. Markdown is the protocol. Shell scripts are the automation layer."** Three formats only:
- **YAML** — structured data (config, state, task queues)
- **Markdown** — instructions & docs (skills, rules, plans)
- **Shell** — automation (generate, validate, sync)

Payoff: any tool can read it, git gives free history/audit/rollback, nothing to maintain, works offline. A new AI tool works "on day one" as long as it reads files.

### 2.2 Config-driven core (`pos.yaml`)
A **single source of truth** YAML file defines the principal (name, tz) and the list of `contexts` (id, type, name, role, stack, shortcuts, path). Everything else is **generated** from it via `pos-generate.sh`:
- `AGENTS.md` — tool-agnostic system architecture doc
- `CLAUDE.md` — Claude Code-specific config (auto-loads at session start)
- the state snapshot

Config is truth; generated files are derived views. Adding a context/team/integration is a one-file edit + regenerate.

### 2.3 Template system (partials + `{{PLACEHOLDER}}`)
Generated files (esp. skills) are produced from templates with `{{PLACEHOLDER}}` syntax. Shared fragments live as **partials** in `templates/skills/partials/` (`_preamble.md`, `_common-rules.md`, `_output-format.md`, `_self-rating.md`, `_verification.md`). Change a rule once → regenerate → every skill inherits it. Same principle as Helm charts / Terraform modules: define once, instantiate many, keep instances consistent. A `--dry-run` flag diffs generated vs. on-disk and **exits 1 on drift** (CI-friendly).

### 2.4 The Two-Path Pattern
Everything is achievable **two ways**: a shell script (automation) OR a hand-edited YAML/file (manual), producing identical results. E.g. new context = `pos-init.sh --context X` *or* edit `pos.yaml` + mkdir. Rationale: AI tools vary in ability to run scripts — some only read/write files. Neither path is privileged.

### 2.5 Context structure & state aggregation
Every context has the same internal shape: `projects/`, `plans/`, `docs/`, `status.yaml`. Consistency means a tool that understands one context understands all.
- Each context owns a `status.yaml`.
- `sync-state.sh` walks every context and aggregates into `.state/snapshot.yaml` — a single dashboard file: queue totals, per-context active/updated/resume.
- One read = full-system awareness (~20 lines gives cross-project visibility).

### 2.6 Skills (the executable layer)
A **skill** = markdown file + YAML frontmatter defining a reusable instruction set. Frontmatter: `name`, `description`, `allowed-tools`. Body = full instructions ("brief a skilled colleague": specify what/why, leave how to the AI within tool constraints). POS ships **30 skills** in 6 categories (Development, Operations, Planning, Content, System, Meta).

**Tool-restriction tiers** (the `allowed-tools` discipline):
- **Read-only** (`code-review`, `architecture`) — Read/Glob/Grep/Bash(ro). Can't modify.
- **Read-write** (`debugging`, `frontend-design`) — adds Write/Edit.
- **Full access** (`production-deploy`, `repo-management`) — any command; safety checks in-instructions.
- **Restricted** (`plan-generation`, `verification`) — deliberately limited to prevent scope creep (a planner produces a plan, not an implementation).

Key insight: *AI tools use whatever capabilities you give them.* If a review skill **can** write, it'll "helpfully" fix things and defeat the review. Restricting tools enforces discipline prompting can't guarantee.

### 2.7 Four self-maintenance mechanisms (the improvement loop)
A 30-component system drifts without feedback. POS counters with four interlocking mechanisms:
1. **Templates prevent drift** — edit a partial, regenerate all; `--dry-run` catches stragglers.
2. **Validation prevents breakage** — `validate-skills.sh` runs 6 static checks (SKILL.md exists; valid frontmatter; required fields; valid tool names; <500 lines flagged; no unresolved `{{PLACEHOLDER}}`). <5s across 30 skills, non-zero exit on error.
3. **Self-rating prevents stagnation** — each skill ends with a 0–10 self-assessment (invisible to user). If <8, writes a feedback file to `.handoff/feedback/` (skill, rating, friction, suggestion, context). `aggregate-feedback.sh` → per-skill avg score table → quantitative signal of what to improve.
4. **Artifacts prevent isolation** — see below.

### 2.8 Cross-skill artifacts
Skills produce durable outputs other skills consume (a plan informs a review; a security audit informs a deploy). `lib-artifacts.sh` gives `artifact_write / artifact_find / artifact_list / artifact_archive`. Stored in `.handoff/artifacts/{context}/{skill}/` with frontmatter (skill, context, branch, created, type, status). A `code-review` skill calls `artifact_find ticketapp plan` at startup and checks implementation against it. Data flows between skills **without** sharing a session or even a tool. (Noted gap: discovery is *passive* — consumers must explicitly look; roadmap wants an auto-loaded artifact manifest.)

### 2.9 Tiered context loading (the token budget equation)
Three tiers, each adds context only when the task needs it:
- **Tier 1 — Quick Check (~75 lines):** loads `QUICK-START.md` (40-line cap). For status checks / simple Qs / formatting. <2% of window (1.5–3k tokens).
- **Tier 2 — Standard Work (~300 lines):** Tier 1 + selectively-loaded docs relevant to the current task. Features/bugs/code. 3–6% (5–12k).
- **Tier 3 — Full Context (800+ lines):** full `AGENTS.md` (architecture, team, decisions, deps). Reserved for architecture / cross-cutting refactors. 8–15% (15–30k), rare.

Contrast with: full-dump (wasteful, 20–40%), let-AI-explore (slow), indexed summaries (no runtime state). Tiered = quick summary + selective deep-load + full as last resort.

### 2.10 The QUICK-START pattern
Every context has a `QUICK-START.md`, **strict 40-line cap**, fixed format: **What** (one sentence) / **Current State** (sprint, branch, active task, blockers) / **Key Files** (5–10 paths) / **Commands** (test/run/deploy). The cap forces prioritization — a living doc that always reflects "what an AI needs today," not last month.

### 2.11 Context switching & multi-context awareness
`/context-switch` skill or `@shortcut` syntax (`@ticketapp`). On switch: save current status → load new QUICK-START → update session file → refresh snapshot. The AI gets the new context without carrying the old one. Meanwhile `.state/snapshot.yaml` (~20 lines) gives lightweight awareness of **all** contexts even while focused on one ("what else is on my plate?").

### 2.12 Cross-tool compatibility
- **AGENTS.md standard** — emerging open standard (agents.md); markdown at repo root any tool reads. POS generates it from `pos.yaml`; tool-specific files (CLAUDE.md, .cursorrules, copilot-instructions.md) are thin wrappers pointing to it.
- **Portable skills** — `generate-portable-skills.sh` strips Claude frontmatter: `.claude/skills/X/SKILL.md` → `.skills/X.md` (plain markdown any tool reads). A `registry.yaml` catalogs skills + triggers.
- **Multi-model capability levels** — basic (Haiku/Flash/4o-mini → docs/formatting), standard (Sonnet/4o/Gemini Pro → features/bugs), advanced (architecture/refactor), reasoning (Opus/o3 → planning/RCA). The task queue labels each task with a required level.

### 2.13 The Handoff Protocol (highest-ROI feature, per the author)
Sessions are stateless; handoffs create a persistent end-of-session record the next session reads at startup. **Three-step session lifecycle:**
1. **Register** — on start, write `.handoff/sessions/<agent>.yaml` (agent, context, capability, started, current_task, files_touched).
2. **Work** — continuously update that file (current_task, files_touched) → crash-survivable.
3. **Close** — write `.handoff/handoffs/<date>-<agent>.yaml`: `summary`, `completed[]`, `pending[]`, `blockers[]`, and a prose **`resume_point`** ("open file X, method Y is stubbed, start with event Z").

**Cross-model handoffs:** Opus plans → writes handoff → Sonnet implements from it → writes handoff → Haiku documents from it. Context carries forward; no model re-discovers prior work.

**Conflict prevention:** session registration = *visibility-based* coordination, not locking. Agents see other active sessions in the snapshot and avoid the same context/files. POS trusts tools to cooperate.

### 2.14 Honest gaps (Part 5)
Uneven skill quality (some thin wrappers); no behavioral/E2E skill testing (cost: $50–100/run for 30 skills); manual session mgmt for non-Claude tools; no visual dashboard; passive artifact discovery; grounding/verification are *instructions not enforcement* (a skill can still skip verify). Roadmap priority order: artifact manifest in context-load → LLM-as-judge skill eval → dashboard → E2E skill tests → per-tool hooks → programmatic post-skill verification.

### 2.15 Hard-won lessons (most transferable wisdom)
- **The value isn't the files — it's the discipline.** Files just lower the activation energy for ending every session with a handoff, starting every task with a plan.
- **Start with the pain, not the architecture.** POS began as a single `status.yaml`. Speculative components needed the most rework.
- **Handoffs are highest ROI** — if you build one thing, build the handoff.
- **Don't over-engineer templates early** — copy-paste until ~15 skills hurt.
- **Keep the config honest** — list what you actually manage, not aspirations.
- **Shared conventions beat per-tool optimization** — the 80% markdown solution beat the 100% Claude-only one.
- **Expect to rebuild twice.** Current POS is the 3rd version.

---

## 3. Comparison vs. our system

Our system = the `~/Downloads/personal/claude/memory/` repo (engine in `seyio91/ai-memory-system`): identity + per-project `memory.md`/`working.md`/`plans/`/`todo.md`, domain/ knowledge, skills store with link-scripts, codex-mem.sh executor, Orchestrator/Executor/Validator workflow.

| Dimension | POS | Ours |
|---|---|---|
| **Core unit** | Context (employment/product/client) | Project (1:1 with a repo) |
| **Source of truth** | Single `pos.yaml` → generates AGENTS.md/CLAUDE.md | Hand-authored `identity.md` + per-project `memory.md`; no central generator |
| **State persistence** | `status.yaml` per context + aggregated `.state/snapshot.yaml` | `memory.md` (durable) + `working.md` (scratchpad), auto-injected at session start |
| **Cross-session continuity** | Formal **handoff records** (`resume_point`, completed/pending/blockers) | **Checkpoints** in `working.md` (task/done/next/blockers) via `/checkpoint` |
| **Task tracking** | YAML task queue with capability labels | `todo.md` checkboxes linked to `plans/` |
| **Plan workflow** | `plan-generation` skill, Plan-Approve-Execute | Plan files + Orchestrator/Executor/Validator roles |
| **Skills** | 30 skills, template-generated, **tool-restriction tiers**, self-rating, validation | Skills store + `link-skills.sh`/`sync-project-skills.sh`; harness-native; no generation/validation pipeline |
| **Multi-tool** | First-class: AGENTS.md + portable `.skills/` + capability routing | Claude-primary + **Codex executor** (codex-mem adapter); not aiming for Cursor/Copilot parity |
| **Multi-context awareness** | Snapshot gives all-context visibility at once | One active project injected; siblings via `## Related Projects` table, **delegated not loaded** |
| **Context loading** | Explicit **3-tier** (75/300/800 lines) with token budget table | Implicit: identity + active project memory injected; on-demand domain/ + subagents for heavy fetches |
| **Self-improvement** | Self-rating (0–10) → feedback files → aggregate scores | `/lint-memory`, `/promote-memory`, reorganize-on-request; no numeric skill scoring |
| **Safety model** | Tool-restriction tiers in skill frontmatter | **execpolicy deny-list** (`~/.codex/rules/default.rules`) blocks apply/merge/destructive at executor layer |
| **Cross-skill data flow** | Artifact system (`artifact_write/find`) | Plans + working.md + memory.md; no formal artifact lib |

### 3.1 Where we're already stronger / different by design
- **Hard enforcement vs. instruction.** POS's biggest admitted gap is that grounding/verification/tool-restriction are *instructions* the AI can skip. Our **codex execpolicy deny-list** is a real kill-switch at the executor layer — destructive infra ops (`terraform apply`, `kubectl apply`, `gh pr merge`) are blocked regardless of prompt. That's the enforcement POS wishes it had.
- **Independent Validator role.** Our Orchestrator/Executor/**Validator** pipeline has a separate agent check output against a plan's success criteria. POS has self-rating (the *same* agent grading itself) — weaker; it even lists LLM-as-judge as a future want.
- **Delegate-don't-load for siblings.** Our `## Related Projects` rule keeps the orchestrator context lean by delegating sibling work to executors. POS loads a global snapshot — cheaper per-read but flatter.
- **Executor as a first-class role.** codex-mem `--executor` + Claude subagent fallback is a real division of labor. POS's "multi-model coordination" is mostly aspirational routing via capability labels.

### 3.2 What's worth adopting from POS
Ranked by value-for-effort:

1. **Formal handoff `resume_point` field.** Our checkpoints capture task/done/next/blockers but POS's prose `resume_point` ("open file X, method Y is stubbed, start with Z") is more actionable. → *Cheap win: add an explicit `resume:` line to the `/checkpoint` template.*
2. **QUICK-START.md per project (40-line cap).** We inject full `memory.md`. A capped Tier-1 summary (What / State / Key Files / Commands) would cut tokens for status-check sessions. → *Consider a `quickstart.md` per project, injected first; full memory on demand.*
3. **Explicit tiered loading.** We load identity + active memory unconditionally. Codifying Tier-1/2/3 (when to pull domain/ vs. full memory) would formalize what we do ad hoc. → *Could become a documented loading policy.*
4. **Skill validation pipeline.** POS's `validate-skills.sh` (frontmatter present, valid tool names, <500 lines, no stray placeholders) is a clean CI check. We have `/lint-memory` for memory but no equivalent static check for the skills store. → *Worth a `validate-skills.sh` in `scripts/`.*
5. **Skill template/partials for shared sections.** If our skills repeat preamble/rules/output-format, a partials+regenerate approach with `--dry-run` drift detection prevents divergence. → *Only if/when skill count + duplication justifies it (POS's own lesson: don't do this before ~15 skills).*
6. **Self-rating feedback (lightweight version).** A skill writing a friction note when it hits a gap → aggregated → tells you which skills to fix. → *Optional; our usage is narrower so signal may be thin.*
7. **Two-Path Pattern as a principle.** Ensure every scripted action (new-project, link-skills) is also doable by hand-editing files, for tool portability.

### 3.3 What NOT to adopt (divergent on purpose)
- **`pos.yaml` central generator.** POS optimizes for *many contexts of one person across many tools*. Our projects are 1:1 with repos and Claude/Codex-centric; a single generated CLAUDE.md per context doesn't fit our per-repo CLAUDE.md + global identity split. Generation adds a build step we don't need.
- **Full multi-tool portability (Cursor/Windsurf/Copilot).** POS pays real complexity tax (portable skills, AGENTS.md wrappers, manual session mgmt for non-Claude tools) for breadth we don't use. Our two-tool (Claude + Codex) scope is deliberate.
- **Capability-level task routing.** Interesting but POS itself admits it's largely aspirational. Our Orchestrator picks executor/model per-task already.

### 3.4 The core philosophical difference
Both systems share the **"everything is a file + git"** axiom. The split:
- **POS is breadth-first / generation-driven:** one config fans out to many contexts and many tools; relies on *convention + self-rating + instructions* for discipline. Optimized for a solo operator juggling many hats across whatever tool is open.
- **Ours is depth-first / enforcement-driven:** per-repo projects, a real Orchestrator/Executor/Validator pipeline, and a *hard execpolicy deny-list* for safety. Optimized for high-blast-radius infra work where a wrong `apply` is unacceptable.

POS trades enforcement for portability. We trade portability for enforcement. The highest-value cross-pollination is one-directional: **adopt POS's handoff/QUICK-START/validation ergonomics; keep our enforcement core.**
