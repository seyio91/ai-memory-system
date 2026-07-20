# Claude Code

How the memory system wires into Claude Code: auto-injection, hooks, maintenance rules,
slash commands, and skills (including the self-rating loop).

## Auto-injection

`scripts/hooks/inject.sh` runs on every prompt as a `UserPromptSubmit` hook. It reads the hook's stdin JSON (for `session_id` and `cwd`) and emits the `<memory:*>` blocks via the `hookSpecificOutput.additionalContext` contract — **not** by appending to the user message:

```bash
printf '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":%s}}\n' "$esc"
```

`json_escape` falls back `jq -Rs .` → `python3 json.dumps` → a hand-rolled `sed`/`awk` escaper so the hook works without `jq`. If nothing would be injected it `exit 0`s with no output.

| Block | When |
|-------|------|
| `<memory:identity>` | Full payload — session start, `@memory`, or post-compaction |
| `<memory:orchestrator>` | Full payload (as above) |
| `<memory:project name="...">` | Full payload (as above), if active project resolved |
| `<memory:index>` | Full payload (as above) |
| `<memory:working>` | Full payload (as above), if `projects/<active>/working.md` is non-empty — **not** every prompt |
| `<memory:active>` | **Every prompt** — the lightweight breadcrumb: project pointer + memory-file paths (including the `working:` write-target) + a re-read directive. Also carries `session:` (the hook's `session_id`, which `/pin` needs to repin the live session — see below) and, only when cwd resolves to a different project than the one in force, one `pinned:` line naming both. This is the only per-prompt injection; the full-payload blocks above ride it only on session start / `@memory` / post-compaction. |

Claude never has to "remember to read" memory — it arrives in-band. Domain files are *not* auto-injected; Claude reads them on demand when the index entry matches the task.

**Once-per-session injection.** There is no per-session marker file. The full payload is emitted inline by the `SessionStart` hook (`session_start_memory.sh`), which by definition fires once per session — so nothing needs tracking. Concurrent sessions cannot collide, because no shared state is written on the hot path.

**Session project pin.** The active project is resolved **once**, at `SessionStart`, and recorded in `$MEMORY_STATE_DIR/<session_id>.project`. Every later prompt honours that pin regardless of where `cwd` wanders — without it, a session that `cd`s into another repo silently repoints every memory write (`/checkpoint`, `/promote-memory`, plan and todo edits) at the wrong project. Written on the non-compact path only, guarded by `hook_chunk_is_first` so the 12 chunk registrations write once; the compact path relies on the pin from startup, since compaction keeps the same `session_id`. Pins are swept after `AI_MEMORY_PIN_RETAIN_DAYS` (7).

Every failure path falls back to the pre-existing cwd walk: no `session_id`, no pin file, a pin naming a project whose directory is gone, or an unwritable state dir. It degrades, never corrupts.

**Executors and subagents deliberately keep cwd resolution** — that is what makes cross-project delegation work, since an executor launched in a sibling repo must resolve the *sibling*. A file keyed by session (rather than an environment variable) is what guarantees this: env inherits into child processes, so an exported project would follow the executor into the sibling repo and resolve the orchestrator's project instead. A probe on 2026-07-20 further established that `UserPromptSubmit` never fires for Claude subagents and that they receive **no** memory injection at all — so a session-keyed pin cannot reach delegated work by any path.

**Post-compaction sentinels.** The one piece of per-session state is a compaction sentinel. `SessionStart` with `source=compact` cannot inject reliably, so instead it writes `<session_id>.recompact` under `$MEMORY_DIR/.sessions` and prunes sentinels older than 2 days (`find "$STATE_DIR" -name '*.recompact' -mtime +2 -delete`) — for sessions that compacted but never resumed. The next `UserPromptSubmit` (`scripts/hooks/inject.sh`) consumes the sentinel, re-injects the full payload once, and removes it. The state dir honors the `MEMORY_STATE_DIR` override (`scripts/hooks/lib.sh`); the test suite sandboxes it implicitly by setting `MEMORY_DIR`.

## Hooks

Three hooks, registered in `~/.claude/settings.json` by `install.sh`. The injection hook runs the shared `scripts/hooks/inject.sh`; the Claude-specific session and task-block hooks run by absolute path from the repo.

| Hook | Event | Script | Effect |
|------|-------|--------|--------|
| Memory injection | `UserPromptSubmit` | `scripts/hooks/inject.sh` | Emits the `<memory:*>` blocks above as `hookSpecificOutput.additionalContext`; otherwise the per-prompt breadcrumb. |
| Session start | `SessionStart` | shared `scripts/hooks/session_start_memory.sh` | Full injection once on session load; on `source=compact` arms a sentinel so the next prompt re-injects (compaction recovery). Shared with Codex (which runs it in `md` format, chunked). |
| Task-tool block | `PreToolUse` (matcher `TaskCreate\|TaskUpdate`) | `harnesses/claude/hooks/block_task_tools.sh` | Consumes stdin, writes the tier-classification reminder to stderr, `exit 2` — blocking the call. Forces all executable-work tracking into `projects/<active>/todo.md`. |

The three entries are auto-merged into `settings.json`; `harnesses/claude/settings.hooks.json` is the reference shape:

```json
{
  "SessionStart": [
    { "hooks": [{ "type": "command", "command": "env MEMORY_DIR=$MEMORY_DIR AI_MEMORY_HOOK_FORMAT=xml AI_MEMORY_HOOK_EVENT=SessionStart bash $MEMORY_DIR/scripts/hooks/session_start_memory.sh" }] }
  ],
  "UserPromptSubmit": [
    { "hooks": [{ "type": "command", "command": "env MEMORY_DIR=$MEMORY_DIR AI_MEMORY_HOOK_FORMAT=xml AI_MEMORY_HOOK_EVENT=UserPromptSubmit bash $MEMORY_DIR/scripts/hooks/inject.sh" }] }
  ],
  "PreToolUse": [
    { "matcher": "TaskCreate|TaskUpdate",
      "hooks": [{ "type": "command", "command": "bash $MEMORY_DIR/harnesses/claude/hooks/block_task_tools.sh" }] }
  ]
}
```

All hook scripts must be `chmod +x` (`install.sh` does this). A setup that skips `block_task_tools.sh` leaves the harness free to call `TaskCreate` — the workflow rule "`todo.md` is the single source of truth" is *enforced* here, not just documented.

### Chunked injection (`session_chunks` / `inject_chunks`)

The shape above is the *reference* single-entry form. In practice both memory events are registered **N times**, because **Claude caps each hook's `additionalContext` at 10,000 chars** (`jLt/mou=1e4` in `@anthropic-ai/claude-code` 2.1.214) — the same class of cap as Codex's ~10,100B, and likewise budgeted **per registered entry**. A single oversized message is silently spilled to a file leaving only a ~2KB preview in context, with the hook still exiting 0: memory vanishes and nothing reports it.

So `harnesses/claude/manifest` sets `session_chunks` / `inject_chunks`, and `_hook_chunked_commands` (`scripts/drivers/hook.sh`) registers one entry per chunk, each passing `AI_MEMORY_HOOK_CHUNK=i/N`. `emit_hook_chunk` (`scripts/hooks/lib.sh`) cuts the rendered payload into ≤9,000B **line-boundary** slices and emits the i-th. Chunks past the natural slice count emit nothing; a payload needing more than N slices emits a loud truncation marker in the last one rather than dropping bytes silently. Per-entry budgeting is confirmed live (2026-07-18: 5 chunks of ≤9,045B all delivered whole).

**Delivery order is not guaranteed.** Codex delivers registered entries in registration order; **Claude does not** — it runs same-event hooks concurrently and concatenates by completion. Observed 2026-07-18: entries registered 1..12 arrived as **2, 3, 4, 1, 5**, splicing `<memory:identity>` into the middle of the `<memory:index>` Domain table. Since slices are cut at arbitrary line boundaries, an out-of-order chunk bisects a `<memory:*>` block.

Every non-empty slice is therefore wrapped in an ordering envelope:

```
<memory:chunk index="2" of="5">
…slice bytes, verbatim…
</memory:chunk>
```

- `of` is the **actual** slice count, not the registered chunk total — `of="5"` with 12 entries registered means 7 are empty headroom.
- Chunk 1 alone carries a `note=` attribute explaining that fragments concatenate by index. One note suffices regardless of arrival order, since all chunks sit in context simultaneously.
- The envelope is a **transport frame**, deliberately not balanced against the content tags it may bisect.
- No separator is inserted before the footer: whether a trailing newline was original or added would be ambiguous on strip, breaking byte-identical reassembly. Only the final slice can lack one, so at most one chunk closes on the same line as its last byte.
- `1/1` and an unset spec stay raw passthrough — a single chunk has no ordering problem.

Tests reassemble with the shared `strip_chunks` helper (`scripts/tests/_assert.sh`), deliberately passing chunks **out of order** and asserting byte-identity against the unchunked render.

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
| `/checkpoint-archive [<slug>]` | Snapshot `working.md`'s `## Checkpoints` section to `archive/working/` and reset only that section; warns before rolling entries that do not say `CLOSED` or `DONE`. |
| `/promote-memory` | Agent extracts candidate learnings from `working.md`'s `## Cross-project learnings` **and** `## Checkpoints`, labels each with inferred destination (`[domain:<topic>]` or `[project]`); user multi-selects which to keep; then rolls **only** `## Cross-project learnings` (via `checkpoint-archive.sh --section`), leaving `## Checkpoints` and any other section byte-identical; regenerates `index.md`. `/checkpoint-archive` owns checkpoints — a learning promoted out of one stays put and may be re-offered until checkpoints are rolled. |
| `/archive-cleanup [--all-projects] [--days N]` | Dry-run first, then on confirmation delete `archive/{plans,todos,working}/` files older than retention threshold (default 30 days; override via `MEMORY_ARCHIVE_RETAIN_DAYS`). `.gitkeep` preserved. |
| `/reindex` | Run `regenerate-index.sh`, show diff |
| `/state [<category>]` | Show the derived cross-project **In Flight** snapshot — `category \| project \| last touched \| current goal \| open todos`, **grouped by category** (uncategorized last), newest first within each. `/state <category>` filters to one client. On-demand projection (`regenerate-state.sh`), never auto-injected. |
| `/activity (<category>\|--all) [--since <N>d]` | **Activity report** — the plans *created* in a window (default 30 days), grouped by category, for reviewing/invoicing a client's work. Scans live **and** archived plans; counts a plan by its `created` date (decoupled from the task backend). On-demand (`regenerate-activity.sh`); output `activity.md` is gitignored/personal. |
| `/lint-memory` | Mechanical checks + LLM-judgment (contradictions, stale paths, broken refs) |
| `/task [verb] [@project] ...` | Capture/manage [task-provider](../task-provider.md) backlog tasks (`add`/`list`/`done`/`archive`/`show`). Project defaults to the active marker; `@project` overrides. Capturing does **not** create a plan — that's `/start`. Thin wrapper over `scripts/taskctl`. |
| `/start [<ref>] [--worktree]` | Begin a captured task: pull it (project-agnostic by `ref`), run the [brainstorm gate](#skills) (feature-with-open-design → `brainstorming` skill; settled/quick → straight to plan), scaffold the linked plan in the task's project (`task_provider`/`task_ref` frontmatter), push the clarified Goal back via `update`, flip status to `started`. Bare `/start` lists the active backlog to pick. `--worktree` (a Tier-3 feature only) enters a fresh git worktree as the final step — see below. |

**Derived state snapshot (`/state`).** `regenerate-state.sh` projects a single **In Flight** table across every project — `category | project | last touched | current goal | open todos`, **grouped by category** (client/group; uncategorized last), newest first within each group — every column derived (category from `memory.md` frontmatter; last-touched from newest file mtime; current goal from `memory.md`'s `## Current Goal`; open todos from `todo.md`'s unchecked boxes). `/state <category>` narrows to one client. Like `index.md` it's a projection that can't drift from its sources, but unlike `index.md` it is **on-demand only — never added to the SessionStart injection payload**: it surfaces *that* sibling work exists without pulling any sibling `memory.md` into context (depth-first / delegate-don't-load). Output `state.md` is gitignored (it lists every project's goals; regenerated, never authored). `last touched` uses mtime, not `git log`, because most project trees are gitignored.

**Project categories & the activity report (`/activity`).** A project can belong to a **category** (a client/group) via an optional `category:` in its `memory.md` frontmatter — **per-instance personal data**: the engine supports the field, but real project `memory.md` files are gitignored, so values never enter git history. Set it with `/pin <project> --category <client>`, during `/new-project`, or by hand. Categories power the `/state` grouping above and **`/activity`**: `regenerate-activity.sh` lists the plans *created* within a window (default 30 days, `--since <N>d`), grouped by category, scanning both live `plans/` and `archive/plans/` — for reviewing or invoicing a client's work over a period. The unit is a **plan** (each has `created:`), so the report is independent of the task backend; output `activity.md` is gitignored/personal, on-demand, never auto-injected.

**Feature-isolation worktrees (`/start --worktree`).** Two features worked concurrently on one repo must live in separate git worktrees (a checkout has one HEAD). `/start --worktree` on a Tier-3 feature task calls Claude Code's native `EnterWorktree` as its **final** step — after the plan/todo are written and the task is linked from the main checkout — so only the execution moves into `.claude/worktrees/<slug>` (a fresh branch off `origin/<default>` per `worktree.baseRef`). The [per-worktree overlay](../file-formats.md#per-worktree-overlays-workingkeymd) then routes this feature's scratchpad to `working.<slug>.md` automatically — no collision with the other session's `working.md`. Guards: if you are already in a worktree, or not in a git repo, `/start` skips the enter and says so. The overlay outlives a removed worktree harmlessly (gitignored; lint nudges if it goes stale); a dedicated `/prune-overlays` sweep is a possible future addition. On Codex/Antigravity — which have no in-session worktree switch — the same isolation is reached by creating the worktree with `git worktree add` and opening the session in it (see their harness docs); the overlay keys off the session cwd identically.

## Skills

Claude Code skills live under `~/.claude/skills/<name>/SKILL.md` — symlinked from the skill stores by `link-skills.sh` — and are auto-discovered by their frontmatter `description` (not listed in `index.md` — they are capabilities, not memory). Scaffold a new authored skill with `scripts/new-skill.sh --name <n>` (writes the schema, validates, optional `--link`; `--kind workflow` also injects the self-rating block — see below); seed an authored skill from an existing dir with `scripts/install-skill.sh --from <dir>`, or **reference** an external skill from a git source with `scripts/install-skill.sh --remote <url> --ref <r>` (declared in a manifest, never copied). List everything you have with `scripts/list-skills.sh` (or `/list-skills`). The one wired into the workflow is `brainstorming`:

| Skill | Gate | Effect |
|-------|------|--------|
| `brainstorming` | **Tier-3 feature tasks with open design questions only** — silent on Tier 1 (research/Q&A), Tier 2 (quick edits), and settled Tier-3 work (mechanical refactors, renames, migrations) | Runs the collaborative design pass (clarify → 2-3 approaches → sectioned design), then hands off to `/new-plan`, folding the approved design into the plan's `## Goal` / `## Success criteria` / `## Design` / `## Risks`. Never writes code or scaffolds the plan itself. |

The gate lives in two places that must agree: the skill's `description` (what Claude Code matches on) and the routing rule in `orchestrator.md` → Orchestration (the injected-every-session anchor). The skill is **orchestrator-role only** (executors never brainstorm) and **seed-agnostic**: it accepts either a fresh user request or a pulled task summary, so a future `/start` can delegate to it without changing the skill.

### Skill file conventions

A skill writes skill-owned files (notes, reviews, self-rating) into its **own folder** (`skills/<name>/`). Stateful skills persist local data in `.skill-data/<name>/` (gitignored, `AI_MEMORY_SKILL_DATA`), decoupled from the possibly-ephemeral skill dir so remote-referenced skills don't lose state on re-resolve; for example, `renovate-manager` writes review memory under `.skill-data/renovate-manager/renovate-reviews/`. There is no write-boundary declaration or enforcement: execpolicy is the destructive-class floor and the Validator catches a skill that mutated something it shouldn't (against the plan's success criteria).

### Self-rating loop (`apply-partial.sh` · `skill-ratings.sh`)

First-party **workflow** skills carry a managed *self-rating* block — a signal about the skill's own friction (where its instructions were unclear or slow), distinct from the Validator (which judges output correctness). The block is a **partial**: its canonical text lives once at `scripts/partials/self-rating.md` and is spliced into a skill between `<!-- partial:self-rating START/END -->` markers, so editing the source and re-running re-syncs every copy.

- **Inject / re-sync:** `scripts/apply-partial.sh --skill <name>` (re-sync; idempotent) or `--all` (re-sync every carrier). The **first** injection into a skill requires `--force` — a deliberate act — which `new-skill.sh --kind workflow` passes automatically. Imported/remote skills get the block only on explicit `--force`, as a clearly machine-managed (fork-safe) section; `install-skill.sh` never injects it.
- **Membership is marker-derived, not a hand-list.** A skill is "in the loop" exactly when its `SKILL.md` carries the block — so the set never drifts (`scripts/_lib.sh:skills_with_partial`).
- **On-request only.** The block tells the skill to append a dated rating (`score 1-5` + friction + improve) to its *own* `skills/<name>/self-rating.md` **only when the user asks** — never automatically. An empty log is healthy.
- **Aggregate:** `scripts/skill-ratings.sh` (per-skill latest/avg/count; `--all` also lists in-loop skills with no ratings yet).

### Skill Source (Authored/Remote)

Skills now have one meaningful axis: **source**.

- **Authored skills** live in `skills/<name>/` under the memory root. `skills/` is per-instance and gitignored except `.gitkeep`: drop a skill dir in, then run `scripts/link-skills.sh` to fan it into the harness skill dirs. These are owned and edited on this instance.
  `link-skills.sh` also **prunes dangling store-shaped links** — a link stranded by a skill rename or a move of the memory tree is never revisited by the link pass (which walks only skills that still exist), so it would otherwise persist forever. A link is removed only when it is dangling *and* its target sits directly under a `skills/` or `.skill-cache/` dir *and* the target basename matches the link name; anything else is reported as a `WARN` and left alone. `--dry-run` reports prunes without removing.
- **Remote skills** live in `.skill-cache/<name>/`, materialized from the root `skills.toml` manifest. They are referenced, pinned, and re-fetchable, not copied into source control.

The old generic/local authored split is retired. There is no tracked in-tree authored skill store. Sharing an authored skill means publishing it to a remote repo and adding it to the catalog/manifest; there is no copy-fork middle category.

**The manifest (TOML, you maintain the list).** Remote skills are declared one `[[skills]]` entry per skill in a single root manifest. The repo ships a tracked `templates/skills.toml.example` catalog; `install.sh` seeds a per-instance `skills.toml` from it only when missing, then you prune what you do not want and run `scripts/resolve-skills.sh`.

| File | Scope | Tracked? |
|------|-------|----------|
| `templates/skills.toml.example` | catalog template | yes |
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

**Authoring & sync.** `new-skill.sh` and `install-skill.sh --from` write authored skills under `skills/`. `install-skill.sh --remote <url> --ref <r> [--path <p>] [--name <n>]` appends the entry to root `skills.toml` **and** resolves it (`--save` is the default; `--no-save` skips the write; a duplicate name needs `--force`). `install.sh` only seeds `skills.toml` from the template; it does not resolve remotes automatically. `sync-system.sh --update` re-resolves refs across an update. Bumping a `ref` + `--update` is how a remote skill updates — its content is never committed, so it can't drift.

**Enumeration is the linchpin.** `scripts/_lib.sh:list_skill_dirs` (built on `skill_roots`) is the single source of "what skills exist and where," across both roots (`skills/`, `.skill-cache/`, precedence in that order; override with `AI_MEMORY_SKILL_ROOTS`). Every skills tool routes through it — link/fan-out, validation, ratings, authoring — so a new root is added once, not in each of the globbing scripts. `list-skills.sh` derives each skill's row from which root holds it (+ root `skills.toml` and the lockfile for remotes): `SKILL · SOURCE · SYNCED · PIN`, with a `--remote` filter.

> The per-repo `projects/<name>/skills/` axis (`sync-project-skills.sh`) is separate and unchanged — that fans project-scoped skills into a specific checkout, orthogonal to the per-instance authored/remote stores here.
