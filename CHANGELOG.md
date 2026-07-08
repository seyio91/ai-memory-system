# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- **Configurable cross-model Validator role.** A third executor role, `validate`
  (`AI_MEMORY_EXECUTOR_VALIDATE`, `harness[:model]`), resolved via
  `scripts/executor.sh --role validate`. It is **read-only** — it resolves through the
  harness's `exec_readonly` face and degrades to the subagent plane when a harness has
  no read-only mode — so a validator verifies but never repairs what it is judging.
  When unset it defaults to the orchestrator's own agent plane (`claude-subagent`),
  **not** the executor's value, so a CLI executor (e.g. `codex`) is validated
  **cross-model by default**, decorrelating reasoning blind spots and not just context.
  The Antigravity `PreToolUse` guard now enforces the read-only allowlist for
  `AI_MEMORY_ROLE=validate` as well as `explore`.

### Changed

- **Install guidance for the Claude workflow-rules base now recommends an
  `@`-import** over copy/merge. A thin `~/.claude/CLAUDE.md` that `@`-imports the
  versioned `harnesses/claude/CLAUDE.md` tracks the repo automatically (no drift) while
  keeping machine-specific lines like `@RTK.md`; merging the body inline freezes a copy
  that silently drifts from the doctrine on every change. (`scripts/drivers/hook.sh`.)

### Fixed

- **A foreign harness model no longer leaks onto the subagent plane when a read-only
  role degrades.** When `explore` (or `validate`) selects a `harness:model` whose harness
  has no `exec_readonly`, `executor.sh` degrades to the subagent plane and now clears the
  model, so `--which` prints `subagent` rather than `subagent:<foreign-model>`. (Surfaced
  by the 2026-07-09 system review; `explore` shipped with this leak in 1.1.0.)

## [1.1.0] - 2026-07-08

> **Upgrading from `1.0.0` needs one manual step.** `identity.md` is no longer
> tracked. Back it up first — see [UPGRADING.md](UPGRADING.md#110). Do not point an
> instance at `v1.0.0` or earlier: that tag still tracks `identity.md` and checking
> it out silently overwrites a personalised copy.

### Removed

- **`identity.md` is no longer under version control.** It is per-instance and
  git-ignored, like `config.local.sh` and `skills.toml`. `install.sh` seeds it from
  the tracked `identity.template.md` whenever it is missing.

### Fixed

- **A tracked `identity.md` bricked the release channel.** `install.sh` tells you to
  edit `identity.md`; `sync-system.sh`'s dirty-tracked-file guard then aborted every
  subsequent sync. An instance stopped syncing the moment it was personalised.
- **Annotated tag messages lost every markdown heading.** `git tag -a -m` defaults to
  `--cleanup=strip`, which deletes lines beginning with `#`. `release.sh` now passes
  `--cleanup=verbatim` on both the normal and resume-at-tag paths. `v1.0.0` was
  retagged with its headings restored.
- `release.sh` seeds `CHANGELOG.md` atomically, keeps exactly one blank line before
  `## [Unreleased]` across repeated releases, and handles a changelog whose first
  line is `## [Unreleased]`.

### Changed

- The `/sync-system` command documented the pre-release script — an `--ff-only` pull
  and two flags. Rewritten for channels, `--to`, the migration runner, and detached
  HEAD.
- `UPGRADING.md` gains a **Converting an existing instance to the release channel**
  runbook, and no longer claims that no stable tags exist.
- A downgrade can clobber a file the older tag tracked and the newer one does not;
  `UPGRADING.md` now says so.
- Renamed a client-named test fixture and domain reference ahead of open-sourcing.

## [1.0.0] - 2026-07-08

First tagged release. The system has been in daily use for some time; `1.0.0`
marks the point at which instances stop tracking a moving `main` and start
syncing to tested cuts. Entries below describe what `1.0.0` contains, not a
delta from an earlier release.

### Added — release engineering

- **Versioned release channel.** `sync-system.sh` is channel-aware: instances on
  `AI_MEMORY_CHANNEL=release` (the default) sync to the latest stable `v*` tag
  and never to raw `main`. `AI_MEMORY_CHANNEL=dev` keeps the fast-forward pull.
- **`--to <ref>`** for one-shot pin, rollback, dogfood, or bisect. Ephemeral: it
  never changes the channel, and the next plain sync returns the instance to its
  channel default on both channels.
- **Migration runner.** `migrations/<semver>-<slug>.sh` run between checkout and
  `install.sh`, forward-only, idempotent, in ascending semver order. The
  gitignored `.applied-version` marker is written after each success, so a
  failed migration is resumable. Downgrades run nothing.
- **`release.sh`** — a guarded, idempotent, resumable tag cut. Refuses on a dirty
  tree, a non-`main` branch, divergence from `origin/main`, an existing tag, a
  non-monotonic version, or a failing test suite. Refuses outright when
  `AI_MEMORY_ROLE` is set, so a delegated executor can never publish a release.
- **`CHANGELOG.md` and `UPGRADING.md`**, the latter carrying the two standing
  rules: migrations are forward-only and idempotent, and a migration must not
  break the previous release's code (N/N+1 compatibility).

### Added — the memory system

- **Markdown-only memory** across three layers: `identity.md` (hard rules),
  `domain/*.md` and `projects/*/memory.md` (durable), `projects/*/working.md`
  (scratchpad). No database, no daemon, no MCP server.
- **Hook-injected context.** The full payload arrives at session start, on
  `@memory`, and on the first prompt after compaction; every other prompt gets a
  lightweight breadcrumb.
- **Harness-agnostic, manifest-driven engine.** `install.sh` resolves a harness
  from `harnesses/<name>/manifest` and wires it. Registered: `claude` and
  `antigravity` (hook archetype) and `codex` (file archetype). Adding a harness
  is a manifest, not engine code.
- **Orchestrator / Executor / Validator workflow**, with `executor.sh` resolving
  `--role task` and `--role explore` through the harness manifest.
- **Task-provider layer** — a pluggable capture/track backend (`local`, `notion`)
  behind `/task` and `/start`, with `/start` running a design gate before
  scaffolding a plan.
- **Skill subsystem** — authored skills in `skills/`, remote skills declared in
  `skills.toml` and materialized into a lockfile-pinned cache. Referenced, not
  forked.
- **Derived projections** — `/state` (in-flight work across projects) and
  `/activity` (plans created in a window, grouped by category). Regenerated,
  never authored.
- **Harness-neutral project marker** `.agents/memory-project`, with a legacy
  `.claude/memory-project` fallback and `migrate-marker.sh` to bulk-migrate.
