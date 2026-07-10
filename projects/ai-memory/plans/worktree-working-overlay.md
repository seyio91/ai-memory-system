---
plan: worktree-working-overlay
status: in_progress
created: 2026-07-10
owner: claude (orchestrator)
task_provider: notion
task_ref: 385f6850-c619-8020-b6ce-fadc098f4f08
---

# Plan — Per-worktree `working.md` overlay (concurrent sessions on one repo)

## Goal

Let two concurrent agent sessions work distinct features in the same repo without clobbering each
other's in-flight scratchpad. Today `detect_project()` returns a project **slug**, and both git
worktrees of a repo carry the same `.agents/memory-project` marker, so both sessions resolve to the
one `projects/<slug>/working.md` and overwrite each other's checkpoints. Give `working.md` a
per-session overlay — `working.<key>.md` — keyed automatically by the git worktree (the exact
condition under which concurrency is even possible), with an explicit `.agents/memory-session`
marker as a visible override. Everything durable (`memory.md`, `index`, `plans/`, `todo.md`) stays
shared. The resolver lives in the **shared engine plane**, so Claude, Codex, Antigravity, and any
future harness inherit it with zero per-harness code.

## Success criteria

Each is mechanically checkable; the Validator verifies pass/fail with evidence.

1. **Resolver, single source.** A shared `resolve_working_file(project, cwd)` (with helper
   `resolve_session_key(cwd)`) returns `projects/<project>/working.<key>.md` when a key exists, else
   `projects/<project>/working.md`. Both readers and writers call it — no second copy of the path
   logic anywhere.
2. **Precedence: marker > worktree > none.** With a `.agents/memory-session` marker found by
   walking up from `cwd`, the key is its sanitized (`[a-z0-9-]`) content. With no marker but `cwd`
   inside a **linked** git worktree (`git -C cwd rev-parse --git-dir` ≠ `--git-common-dir`), the key
   is `basename(git-dir)`. In a main checkout, or with no git, the key is empty → shared
   `working.md`. Proven by unit tests including a marker that overrides a worktree key.
3. **Main checkout unchanged.** With no key, the resolved path is byte-for-byte the current
   `projects/<slug>/working.md`; no migration, existing scratchpads untouched.
4. **Read wiring (all three harnesses).** Given a linked-worktree `cwd`, `content_sections` emits
   the overlay path and the injected `<memory:active working=…>` breadcrumb carries it — proven in
   the Claude inject test, the Codex context test, and the Antigravity inject test. A main checkout
   emits the base path. `content_sections`' positional signature is unchanged (cwd arrives via env).
5. **Write wiring.** Codex's `codex-mem-checkpoint.sh` appends to the overlay (not the base) when in
   a linked worktree; the Claude `/checkpoint` command targets the working file named in the
   breadcrumb rather than a hardcoded `working.md`.
6. **Isolation guarantee.** Two distinct worktree keys → two distinct overlay files → a checkpoint
   in one never appears in the other (direct two-worktree test).
7. **Housekeeping.** `.gitignore` ignores overlay files (`working*.md`), verified against the
   `ai-memory` tracked-exception; `lint-memory` staleness scan also sees `working.*.md`; the full
   `run-tests.sh` stays green (bash + python + lint/doc-vs-code/shellcheck).

## Design

**Chosen approach — auto per-worktree key + explicit marker override, resolver in the shared plane.**

- **Resolver (Section A).** Two pure functions in `scripts/_lib.sh` (the shared, harness-neutral
  plane), reachable by `content-core.sh`:
  - `resolve_session_key(cwd)` → precedence: (1) `.agents/memory-session` marker content (sanitized)
    walking up from `cwd`; (2) linked-worktree name via `git -C cwd rev-parse --git-dir` when it
    differs from `--git-common-dir`, key = `basename`; (3) empty.
  - `resolve_working_file(project, cwd)` → `…/working.<key>.md` or `…/working.md`.
  - Fail-safe: git absent/error/detached → empty key → shared file; the overlay never errors a hook.
- **Split boundary (Section B).** Overlay `working.md` only (checkpoints live inside it). Shared and
  untouched: `memory.md`, `index`, `plans/` (distinct filenames, no clash), `domain/`, and
  deliberately `todo.md` — two concurrent features carry distinct plan files and `todo.md` churns at
  task boundaries, not every checkpoint, so its collision risk is low; splitting it is deferred, not
  built.
- **cwd seam (Section C).** `content-core.sh` reads `cwd` from env (`AI_MEMORY_CWD`, fallback
  `$PWD`) exactly as it already reads `MEMORY_DIR`, so `content_sections(project, [kinds…])` keeps
  its signature across all three call sites. Its `working)` case calls `resolve_working_file`.
  - Read: Claude (`memory_common.sh`), Antigravity (`preinvocation.sh`), Codex
    (`build-context-md.sh`) all funnel through `content_sections` → overlay path flows into the
    breadcrumb automatically. Each harness exports `AI_MEMORY_CWD` (Antigravity already does).
  - Write: Claude/Antigravity `/checkpoint` = model following the breadcrumb path (make the command
    text reference the breadcrumb's working file); Codex's `codex-mem-checkpoint.sh` (a script)
    calls `resolve_working_file` directly.

**Alternatives considered:**
- *Session-id key* → rejected: the hook's session id is fresh per launch, so the scratchpad would
  not survive a restart — defeats "resume where I left off."
- *Manual marker only (no auto)* → rejected as the default: forgetting the marker in a worktree is a
  silent regression to today's collision. Kept as the explicit override, not the primary path.
- *Branch-name key* → rejected: a branch can change under one checkout and two worktrees can share a
  branch; the worktree is the stable 1:1 identity for concurrency.
- *Overlay in the Claude hook* → rejected: it would not reach Codex/Antigravity. The shared
  `content-core.sh` seam is what makes it harness-agnostic.

## Decisions (locked)

- **1+2:** auto worktree key by default, `.agents/memory-session` marker as a visible override
  (marker > worktree > none).
- **Resolver in the shared plane** (`_lib.sh` + `content-core.sh`), not any harness hook.
- **Overlay `working.md` only**; `todo.md` and everything durable stay shared.
- **cwd via `AI_MEMORY_CWD` env**, not a new positional arg to `content_sections`.
- Scale = lightweight (user is in case **B**, occasional concurrent worktrees).

## Phases

### Phase 1 — Shared resolver + unit tests
- Add `resolve_session_key` / `resolve_working_file` to `_lib.sh`; unit-test every precedence branch
  and sanitization (criteria 1, 2, 3). Mutation-verify each assertion.

### Phase 2 — Read path through `content-core.sh`
- `content_sections` `working)` case → `resolve_working_file`, cwd from `AI_MEMORY_CWD`/`$PWD`.
  Export `AI_MEMORY_CWD` from the Claude hook and the Codex adapter (Antigravity already sets it).
- Extend `test_inject_memory` (Claude), `test_codex_mem` (Codex), and the Antigravity inject test to
  prove the overlay path is injected under a linked-worktree cwd (criterion 4 — the multi-harness proof).

### Phase 3 — Write path (checkpoints)
- `codex-mem-checkpoint.sh` → `resolve_working_file`; test it appends to the overlay (criterion 5).
- Update the Claude `/checkpoint` (and check `promote-memory`) command text to target the working
  file named in the breadcrumb, not a hardcoded `working.md`.
- Two-worktree isolation test (criterion 6).

### Phase 4 — Housekeeping + docs + full green
- `.gitignore` → `working*.md` (verify `ai-memory` exception); `lint-memory` sees `working.*.md`
  (criterion 7).
- Document the overlay in `docs/` (the memory-model / harness pages) and the `.agents/memory-session`
  marker. Full `run-tests.sh` green.

## Risks / open questions

- **`todo.md` overlay** — deferred (Section B). Revisit only if concurrent features collide on it;
  the same resolver extends to it.
- **Sibling visibility** — full isolation assumed; a session does not see another worktree's overlay.
  Revisit if a "peek at the other feature's scratchpad (read-only)" need appears.
- **Stale overlay cleanup** — when a worktree is deleted, its `working.<key>.md` lingers (gitignored,
  harmless). Manual for now; a future `git worktree prune`-style sweep could clear them.
- **System-managed worktree creation** (follow-up, task `399f6850`, 2026-07-10) — this plan makes the
  overlay work *given* a worktree, but the user still runs `git worktree add` by hand. The system
  should provision the worktree (create it, set the session key, seed the overlay) so launching a
  parallel feature is one action. Deferred to its own task; the cleanup point above folds in there.
- **Two-Path friction** — an auto-derived overlay name means a human hand-writing a checkpoint must
  read the breadcrumb for the path. The explicit marker mitigates this by making the name visible;
  the docs must state the resolution rule so the manual path stays reproducible.
- **`AI_MEMORY_CWD` correctness for Codex** — relies on `$PWD` being the repo checkout at adapter
  run time, the same assumption today's project detection already makes; if that ever breaks, project
  detection breaks first, so no new failure surface.
