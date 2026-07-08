# Claude Code

How the memory system wires into Claude Code: auto-injection, hooks, maintenance rules,
slash commands, and skills (including the skill write boundary and the self-rating loop).

## Auto-injection

`~/.claude/hooks/inject_memory.sh` runs on every prompt as a `UserPromptSubmit` hook. It reads the hook's stdin JSON (for `session_id` and `cwd`) and emits the `<memory:*>` blocks via the `hookSpecificOutput.additionalContext` contract — **not** by appending to the user message:

```bash
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$esc"
```

`json_escape` falls back `jq -Rs .` → `python3 json.dumps` → a hand-rolled `sed`/`awk` escaper so the hook works without `jq`. If nothing would be injected it `exit 0`s with no output.

| Block | When |
|-------|------|
| `<memory:identity>` | First prompt of a session |
| `<memory:project name="...">` | First prompt of a session, if active project resolved |
| `<memory:index>` | First prompt of a session |
| `<memory:working>` | **Every prompt** if `projects/<active>/working.md` is non-empty |

Claude never has to "remember to read" memory — it arrives in-band. Domain files are *not* auto-injected; Claude reads them on demand when the index entry matches the task.

**Per-session markers.** "First prompt" is the absence of a per-session marker file at `~/.claude/memory_sessions/<session_id>` — not a single shared `memory_last_session` file. Concurrent sessions don't clobber each other's once-per-session injection. On the first-prompt branch the hook writes the marker (`: > "$marker"`) and opportunistically sweeps markers older than 2 days (`find "$MARKDIR" -type f -mtime +2 -delete`), keeping `memory_sessions/` self-maintaining off the hot path. The hook honors `MEMORY_DIR` and `MEMORY_SESSIONS_DIR` env overrides (used by the test suite to sandbox).

## Hooks

Three hooks, registered in `~/.claude/settings.json`. The scripts are symlinked from `harnesses/claude/hooks/` by `install.sh`; `memory_common.sh` is sourced by the others, not registered.

| Hook | Event | Script | Effect |
|------|-------|--------|--------|
| Memory injection | `UserPromptSubmit` | `hooks/inject_memory.sh` | Emits the `<memory:*>` blocks above as `hookSpecificOutput.additionalContext`; otherwise the per-prompt breadcrumb. |
| Session start | `SessionStart` | `hooks/session_start_memory.sh` | Full injection once on session load; on `source=compact` arms a sentinel so the next prompt re-injects (compaction recovery). |
| Task-tool block | `PreToolUse` (matcher `TaskCreate\|TaskUpdate`) | `hooks/block_task_tools.sh` | Consumes stdin, writes the tier-classification reminder to stderr, `exit 2` — blocking the call. Forces all executable-work tracking into `projects/<active>/todo.md`. |

The three entries to merge into `settings.json` ship in `harnesses/claude/settings.hooks.json`:

```json
{
  "SessionStart": [
    { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/session_start_memory.sh" }] }
  ],
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/inject_memory.sh" }] }
  ],
  "PreToolUse": [
    { "matcher": "TaskCreate|TaskUpdate",
      "hooks": [{ "type": "command", "command": "$HOME/.claude/hooks/block_task_tools.sh" }] }
  ]
}
```

All hook scripts must be `chmod +x` (`install.sh` does this). A setup that skips `block_task_tools.sh` leaves the harness free to call `TaskCreate` — the workflow rule "`todo.md` is the single source of truth" is *enforced* here, not just documented.

## Maintenance rules (from `~/.claude/CLAUDE.md`)

- **Update memory immediately** when you learn or decide something durable. Don't batch.
- **Project-specific** → `projects/<active>/memory.md` (place under the matching section).
- **Cross-project** → `projects/<active>/working.md` first, then `/promote-memory` later.
- **Checkpoint before pauses, tool switches, or session end** → `/checkpoint`.
- **Offer to file non-trivial synthesis as a wiki page** — Claude prompts at the end of substantial answers (architecture, comparisons, gotcha analyses). Skipped for short or code-only answers.

## Slash commands

| Command | Purpose |
|---------|---------|
| `/new-project <name>` | Copy `_template` into `projects/<name>`, prompt for the repo's absolute path and place the `.agents/memory-project` marker there (pins the project — no separate `/pin` needed), then interview to fill `memory.md`. Blank path → scaffold only. |
| `/pin <name> [--category <client>]` | (Re)pin — needed when the checkout **location changes** or to pin an already-scaffolded project. From inside a checkout, runs `memory-pin.sh <name>` — writes the forward `.agents/memory-project` marker **and** the reverse `repo`/`repo_path` frontmatter (readers check `.agents/memory-project` first, fall back to the legacy `.claude/memory-project`; migrate with `scripts/migrate-marker.sh`). `--category <client>` also sets the project's (personal, gitignored) `category:` |
| `/checkpoint` | Synthesize task/done/next/blockers from session context (no questions); append a dated entry to `## Checkpoints` in `working.md` |
| `/new-plan <name>` | Scaffold a new plan file in `projects/<active>/plans/` with frontmatter and a required `## Success criteria` section (the [Task Contract](../workflow.md#task-contract)). Renamed from `/plan` to avoid colliding with the native `/plan` plan-mode command. |
| `/plan-done <name>` | Flip a plan's `status:` to `done` and stamp `completed:` date |
| `/plan-archive <name>` | Move a completed plan from `plans/` to `archive/plans/` |
| `/todo-archive [<slug>]` | Snapshot a fully-ticked `todo.md` to `archive/todos/` and reset. Auto-derives the slug when `todo.md` references exactly one plan and no `<slug>` was passed. |
| `/promote-memory` | Agent extracts candidate learnings from `working.md`, labels each with inferred destination (`[domain:<topic>]` or `[project]`); user multi-selects which to keep; archive `working.md`; regenerate `index.md` |
| `/archive-cleanup [--all-projects] [--days N]` | Dry-run first, then on confirmation delete `archive/{plans,todos,working}/` files older than retention threshold (default 30 days; override via `MEMORY_ARCHIVE_RETAIN_DAYS`). `.gitkeep` preserved. |
| `/reindex` | Run `regenerate-index.sh`, show diff |
| `/state [<category>]` | Show the derived cross-project **In Flight** snapshot — `category \| project \| last touched \| current goal \| open todos`, **grouped by category** (uncategorized last), newest first within each. `/state <category>` filters to one client. On-demand projection (`regenerate-state.sh`), never auto-injected. |
| `/activity (<category>\|--all) [--since <N>d]` | **Activity report** — the plans *created* in a window (default 30 days), grouped by category, for reviewing/invoicing a client's work. Scans live **and** archived plans; counts a plan by its `created` date (decoupled from the task backend). On-demand (`regenerate-activity.sh`); output `activity.md` is gitignored/personal. |
| `/lint-memory` | Mechanical checks + LLM-judgment (contradictions, stale paths, broken refs) |
| `/task [verb] [@project] ...` | Capture/manage [task-provider](../task-provider.md) backlog tasks (`add`/`list`/`done`/`archive`/`show`). Project defaults to the active marker; `@project` overrides. Capturing does **not** create a plan — that's `/start`. Thin wrapper over `scripts/taskctl`. |
| `/start [<ref>]` | Begin a captured task: pull it (project-agnostic by `ref`), run the [brainstorm gate](#skills) (feature-with-open-design → `brainstorming` skill; settled/quick → straight to plan), scaffold the linked plan in the task's project (`task_provider`/`task_ref` frontmatter), push the clarified Goal back via `update`, flip status to `started`. Bare `/start` lists the active backlog to pick. |

**Derived state snapshot (`/state`).** `regenerate-state.sh` projects a single **In Flight** table across every project — `category | project | last touched | current goal | open todos`, **grouped by category** (client/group; uncategorized last), newest first within each group — every column derived (category from `memory.md` frontmatter; last-touched from newest file mtime; current goal from `memory.md`'s `## Current Goal`; open todos from `todo.md`'s unchecked boxes). `/state <category>` narrows to one client. Like `index.md` it's a projection that can't drift from its sources, but unlike `index.md` it is **on-demand only — never added to the SessionStart injection payload**: it surfaces *that* sibling work exists without pulling any sibling `memory.md` into context (depth-first / delegate-don't-load). Output `state.md` is gitignored (it lists every project's goals; regenerated, never authored). `last touched` uses mtime, not `git log`, because most project trees are gitignored.

**Project categories & the activity report (`/activity`).** A project can belong to a **category** (a client/group) via an optional `category:` in its `memory.md` frontmatter — **per-instance personal data**: the engine supports the field, but real project `memory.md` files are gitignored, so values never enter git history. Set it with `/pin <project> --category <client>`, during `/new-project`, or by hand. Categories power the `/state` grouping above and **`/activity`**: `regenerate-activity.sh` lists the plans *created* within a window (default 30 days, `--since <N>d`), grouped by category, scanning both live `plans/` and `archive/plans/` — for reviewing or invoicing a client's work over a period. The unit is a **plan** (each has `created:`), so the report is independent of the task backend; output `activity.md` is gitignored/personal, on-demand, never auto-injected.

## Skills

Claude Code skills live under `~/.claude/skills/<name>/SKILL.md` — symlinked from the skill stores by `link-skills.sh` — and are auto-discovered by their frontmatter `description` (not listed in `index.md` — they are capabilities, not memory). Scaffold a new one with `scripts/new-skill.sh --name <n> --tier <t>` (writes the schema, validates, optional `--link`; `--kind workflow` also injects the self-rating block — see below; `--local` scaffolds a per-instance skill — see [Skill scope & source](#skill-scope--source-localgeneric--authoredremote)); seed a local skill from an existing dir with `scripts/install-skill.sh --from <dir> --tier <t>`, or **reference** an external skill from a git source with `scripts/install-skill.sh --remote <url> --ref <r>` (declared in a manifest, never copied). Several ship in `skills/` (e.g. `renovate-manager`, `grafana-oss`, `prometheus`, `tempo`, `dashboarding`, `observability-check`, `terraform-example-gen`, `bkt`, `teach`, `excalidraw-diagram`). List everything you have with `scripts/list-skills.sh` (or `/list-skills`). The one wired into the workflow is `brainstorming`:

| Skill | Gate | Effect |
|-------|------|--------|
| `brainstorming` | **Tier-3 feature tasks with open design questions only** — silent on Tier 1 (research/Q&A), Tier 2 (quick edits), and settled Tier-3 work (mechanical refactors, renames, migrations) | Runs the collaborative design pass (clarify → 2-3 approaches → sectioned design), then hands off to `/new-plan`, folding the approved design into the plan's `## Goal` / `## Success criteria` / `## Design` / `## Risks`. Never writes code or scaffolds the plan itself. |

The gate lives in two places that must agree: the skill's `description` (what Claude Code matches on) and the routing rule in `identity.md` → Orchestration (the injected-every-session anchor). The skill is **orchestrator-only** (Claude main session — Codex never brainstorms) and **seed-agnostic**: it accepts either a fresh user request or a pulled task summary, so a future `/start` can delegate to it without changing the skill.

### Skill write boundary (`metadata.tier`)

Every skill declares one neutral frontmatter field under `metadata:`:

```yaml
metadata:
  tier: target-read-only   # or: target-write
```

`tier` is a **coarse label, not a tool list** — deliberately *not* Claude's `allowed-tools` (that's Claude-only; Codex ignores it). Enforcement stays harness-agnostic: the label is what *we* check, identically for Claude and Codex.

- **`target-read-only`** — the skill must not modify the thing it operates on (the project/repo under review). Review, analysis, planning, and reference skills: `renovate-manager`, `observability-check`, `prometheus`, `tempo`, `teach`, `brainstorming`.
- **`target-write`** — the skill may modify the target. Generators and action skills: `terraform-example-gen`, `dashboarding`, `excalidraw-diagram`, `fiter-infrastructure-analyzer`, `grafana-oss`, `bkt`.

The label resolves **three write zones**:

1. **Target tree** — the project/repo being worked on. Gated by `tier` (read-only ⇒ hands off).
2. **The skill's own folder** (`skills/<name>/`) — **always writable, at any time, regardless of tier**, with no declaration needed. This is where a read-only skill puts skill-owned files. Stateful skills persist local data in `.skill-data/<name>/` (gitignored, `AI_MEMORY_SKILL_DATA`), decoupled from the possibly-ephemeral skill dir; for example, `renovate-manager` writes review memory under `.skill-data/renovate-manager/renovate-reviews/`. No `memory_store` field — the rule is universal, so there's nothing to declare.
3. **Everything else** (`projects/*/memory.md`, `working.md`, `index.md`, and *other* skills' folders) — **off-limits by default**, even though it's in the memory repo.

Enforcement is harness-agnostic and *detective* (a post-run check, layered under the codex execpolicy which prevents the destructive class) — see `projects/ai-memory/plans/skill-subsystem.md` for the `tier` schema (#10), the `validate-skills.sh` static check (#4), and the post-run git-diff boundary check (#11).

**Boundary enforcement (in-session).** `scripts/skill-boundary-check.sh` is the engine: `snapshot` a repo's git state before a skill runs, `check` after. The Claude trigger is two hooks (in `harnesses/claude/settings.hooks.json`):
- `skill_boundary_marker.sh` (PostToolUse:Skill) — when a `target-read-only` skill is invoked, captures a memory-repo baseline.
- `skill_boundary_check.sh` (Stop) — at turn end, verifies the skill didn't write outside its own folder in the memory repo (scope `others-only`, so the orchestrator's own `memory.md`/`todo.md` edits don't count) and, if a target was registered, that the target repo is untouched. Exits 2 to surface a violation.

A read-only skill that resolves a **target** repo registers it for the target-half check by writing `skills/<skill>/.boundary-target` (= `<repo-path>` on line 1, a `snapshot` baseline file on line 2) — a write into its *own* folder, which is always allowed. (Codex executor enforcement is deferred — Codex mostly runs target-write work; read-only skills run in-session.)

### Self-rating loop (`apply-partial.sh` · `skill-ratings.sh`)

First-party **workflow** skills carry a managed *self-rating* block — a signal about the skill's own friction (where its instructions were unclear or slow), distinct from the Validator (which judges output correctness). The block is a **partial**: its canonical text lives once at `scripts/partials/self-rating.md` and is spliced into a skill between `<!-- partial:self-rating START/END -->` markers, so editing the source and re-running re-syncs every copy.

- **Inject / re-sync:** `scripts/apply-partial.sh --skill <name>` (re-sync; idempotent) or `--all` (re-sync every carrier). The **first** injection into a skill requires `--force` — a deliberate act — which `new-skill.sh --kind workflow` passes automatically. Imported/remote skills get the block only on explicit `--force`, as a clearly machine-managed (fork-safe) section; `install-skill.sh` never injects it.
- **Membership is marker-derived, not a hand-list.** A skill is "in the loop" exactly when its `SKILL.md` carries the block — so the set never drifts (`scripts/_lib.sh:skills_with_partial`).
- **On-request only.** The block tells the skill to append a dated rating (`score 1-5` + friction + improve) to its *own* `skills/<name>/self-rating.md` **only when the user asks** — never automatically. An empty log is healthy.
- **Aggregate:** `scripts/skill-ratings.sh` (per-skill latest/avg/count; `--all` also lists in-loop skills with no ratings yet).

### Skill scope & source (local/generic × authored/remote)

Skills vary on two independent axes. **Scope** — does it sync to your other instances? **Source** — did you author it here, or is it referenced from elsewhere? Every skills tool understands both, and `list-skills.sh` shows them.

- **Scope = which folder.** `skills/` is **generic**: git-tracked, synced to every instance (the default). `skills-local/` is **local**: gitignored wholesale by one `/skills-local/*` line, per-instance, never synced. Location is the only signal — no per-skill metadata, no per-skill gitignore. Moving a skill generic↔local is a `git mv`. Scaffold local with `new-skill.sh --local`; a generic one is the default.
- **Source = authored vs remote.** **Authored** skills live in one of those folders (content is yours to edit). **Remote** skills are *referenced, not forked*: declared in a TOML manifest and fetched per-instance into a gitignored cache. The rule that keeps them distinct: **modify it → make it local (authored); just use it → reference it (remote).** There is no copy-fork middle category.

**The manifest (TOML, you maintain the list).** Remote skills are declared one `[[skills]]` entry per skill in a single root manifest. The repo ships a tracked `skills.toml.example` catalog; `install.sh` seeds a per-instance `skills.toml` from it only when missing, then you prune what you do not want and run `scripts/resolve-skills.sh`.

| File | Scope | Tracked? |
|------|-------|----------|
| `skills.toml.example` | catalog template | yes |
| `skills.toml` | per-instance remote choices | no (gitignored) |

```toml
[[skills]]
name = "renovate-pro"
url  = "https://github.com/org/skills.git"
ref  = "v1.2.0"          # branch, tag, or sha — pinned for reproducibility
path = "skills/renovate" # optional subdir holding SKILL.md
```

TOML is parsed by python3's stdlib `tomllib` (3.11+) — **no pip dependency** (the task provider already sets the bar at "python3 stdlib, no pip"; the per-instance manifest is gitignored so private remotes stay local).

**The resolver & cache.** `scripts/resolve-skills.sh` reads root `skills.toml` and materializes each remote into the gitignored **`.skill-cache/<name>/`**, pinned by **`.skill-cache/skills.lock`**:
- **Fetch is sparse + shallow** — `git init` → `fetch --depth 1 <ref>` (full-fetch fallback for by-sha refs) → `sparse-checkout <path>` → copy the resolved skill (no nested `.git`).
- **A plain resolve is a cache hit** (no network) for anything already locked, so re-linking is offline-safe. Only a first-resolve or `--update` fetches, and a fetch that *must* run **hard-fails** (strict reproducibility). `resolve-skills.sh --update` re-fetches pinned refs; `--list` shows declared remotes; `--dry-run` shows intent.

**Authoring & sync (the config-driven flow).** `install-skill.sh --remote <url> --ref <r> [--path <p>] [--name <n>]` appends the entry to root `skills.toml` **and** resolves it (`--save` is the default; `--no-save` skips the write; a duplicate name needs `--force`). `install.sh` only seeds `skills.toml` from the template; it does not resolve remotes automatically. `sync-system.sh --update` re-resolves refs across an update. Bumping a `ref` + `--update` is how a remote skill updates — its content is never committed, so it can't drift.

**Enumeration is the linchpin.** `scripts/_lib.sh:list_skill_dirs` (built on `skill_roots`) is the single source of "what skills exist and where," across all three roots (`skills/`, `skills-local/`, `.skill-cache/`, precedence in that order; override with `AI_MEMORY_SKILL_ROOTS`). Every skills tool routes through it — link/fan-out, validation, boundary, ratings, authoring — so a new root is added once, not in each of the globbing scripts. `list-skills.sh` derives each skill's row from which root holds it (+ root `skills.toml` and the lockfile for remotes): `SKILL · SCOPE · SOURCE · SYNCED · PIN`, with `--remote` / `--local` filters.

> The per-repo `projects/<name>/skills/` axis (`sync-project-skills.sh`) is separate and unchanged — that fans project-scoped skills into a specific checkout, orthogonal to the per-instance generic/local split here.
