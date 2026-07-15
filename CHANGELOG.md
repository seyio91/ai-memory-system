# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Changed

- **Task providers are now self-contained folders** — `providers/<name>.py` becomes
  `providers/<name>/` with an `__init__.py` (exposing `PROVIDER`), a `README.md` documenting
  the backend's expected config/setup, and a captured setup image. The factory imports
  `taskprovider.providers.<name>` either way, so the flat form still resolves, but new
  providers use the folder. `check-provider-tests.sh` now discovers package providers as
  well as flat modules, and **fails closed** (exit 2) if it finds no providers at all rather
  than passing an empty set. `local/__init__.py` sits one level deeper, so its repo-root
  fallback moved from `parents[3]` to `parents[4]`.

## [1.3.0] - 2026-07-15

### Changed

- **`projects/<project>/brainstorms/` is now `projects/<project>/investigations/`.** An
  *investigation* is an artifact; a *brainstorm* is an activity. The old name conflated them and
  split the doctrine: this repo said long-form design belongs in `brainstorms/<slug>.md`, while the
  `brainstorming` skill said "do not create a separate spec document — the design lives in the plan
  file, in the memory tree." Both were right about **different files**. An investigation is the
  findings artifact written while exploring, *before a task exists*; it is conditional (only when an
  investigation was done and its output exceeds the 500-char `summary` cap), and it has two readers —
  the task summary names it, and `/start` hands it to the brainstorming skill as the seed. The
  brainstorm's only output is the **plan**. The tell: `release-automation.md` lived in `brainstorms/`
  carrying `kind: brainstorm-input` and `status: open (investigation only)`, and its task summary
  said "`/start` should skip the brainstorm gate."
  - The `validate_summary()` `ValueError` text in `scripts/taskprovider/contract.py` — the primary
    doc surface for this rule — now names `investigations/`. `docs/task-provider.md`, `/task` and
    `/start` follow.
  - The corresponding fix to the remote `brainstorming` skill lives in the `agent-skills` repo
    (this tree can only *reference* remote skills, never fork them), tracked as a PR there.

### Added

- **A doc-vs-code consistency gate on `run-tests.sh`** (`scripts/check-docs.sh`). Doc rot recurs
  because nothing tests a doc against the code it describes. The env-var table in `docs/scripts.md`
  is structured (`Var | Default | Used by`), so it yields two mechanical assertions: **forward** —
  every documented var exists somewhere in the code roots; **strict** — every documented var appears
  in the script its `Used by` names, *or in any file that script sources, transitively*. A
  `== doc-vs-code ==` stage gates the suite's exit code (0 clean / 1 findings / 2 setup error — an
  unparseable table can never read as clean).
  - Source-following is required, not a nicety: `lint-memory.sh` never mentions
    `AI_MEMORY_PROJECTS_ROOT`, it calls `projects_root()` in `_lib.sh`. One hop is not enough either
    — `inject_memory.sh` → `memory_common.sh` → `_lib.sh` is depth 2, and the inner source is
    conditional. The closure has a visited-set cycle guard; a runaway graph aborts (`CLOSURE_MAX`)
    rather than reporting a verdict from a traversal that never terminated.
  - A `Used by` cell naming no script **fails** unless listed in the new `.docscheck-exempt` with a
    reason, so prose cannot creep back into a machine-checked column.
  - **Scope is deliberately narrow.** It catches symbol drift. It cannot catch a semantic prose
    promise (`--dry-run` "mutates nothing" while running `git fetch --tags`), a hand-written count,
    a var documented outside the table, or a contradiction with a remote skill in another repo. Those
    are stated as non-goals in `docs/scripts.md`, not left as an implied stronger claim.
- **`MEMORY_STATE_DIR` is documented**, replacing `MEMORY_SESSIONS_DIR` — which was documented in two
  files and existed in **zero** code files. It was not a renamed var: the mechanism it described (a
  per-session marker at `~/.claude/memory_sessions/<session_id>`) no longer exists. `SessionStart`
  fires once per session and injects inline; the only per-session artifact is a
  `<session_id>.recompact` sentinel under `$MEMORY_DIR/.sessions`. Four doc call-sites were rewritten
  against the hooks. This is the drift the new gate would have caught, and the reason it exists.

- **shellcheck is now a gate on `run-tests.sh`**, not a suggestion. A `== shellcheck ==`
  stage sets a non-zero suite exit code on any finding, running two invocations against a
  single root `.shellcheckrc`: production code at `-S info` and `scripts/tests/` at
  `-S warning`. The floor is `info` **because `SC2086` — unquoted expansion — is an
  info-level check**, so a `warning` gate could never fire on the most consequential shell
  bug class; tests sit at `warning` because their info-level hits are idioms (`SC2015`
  assert-pairs, deliberate `SC2030`/`SC2031` subshells). A nested `tests/.shellcheckrc` was
  rejected: the nearest rc **replaces** the root rather than merging, so a later root disable
  would silently stop applying there.

  `.shellcheckrc` silences exactly four codes repo-wide (`SC1091`/`SC1090` unfollowable
  `source`, `SC2016` intentional single quotes, `SC2034` sourced-consumer and
  stdout-swallow variables). Everything else fires; site exemptions are **inline** with a
  justification. A `.shellcheck-baseline` of accepted findings was rejected as an artefact
  that records a verification instead of performing one.

  shellcheck is **dev/CI-only** — the runtime zero-dependency bet is untouched. When the
  binary is absent the stage prints a notice and skips **without gating**, so a consumer
  instance running the suite never fails for lacking a linter.

  The gate is proven to fire, not assumed to: an `SC2086` injected into a production script
  fails the suite; an `SC2155` in a test file fails it; an `SC2086` in a test file does not
  (by design); and removing shellcheck from `PATH` skips cleanly at exit 0.

- **`recurse` field on `skills.toml` — pull many skills from one repo subpath** (#61). One
  `[[skills]]` entry with `recurse = true` fetches a repo once and materializes every `SKILL.md`
  under `path` as its own cached skill, replacing one-entry-per-skill (grafana ships **46**, the
  first-party `agent-skills` repo **5**). Identity is frontmatter `name:` → dir basename → optional
  `prefix`; a nested `references/SKILL.md` is pruned (outermost-wins, not a second skill); optional
  `exclude` globs omit sub-paths. The lockfile gains a 6th `origin` column (`url#path`) and records
  the concrete expanded set, so a plain resolve **replays from the lock as an offline cache-hit** —
  a recurse entry is exactly as reproducible as explicit ones once locked (expansion runs only on
  first-resolve / `--update`). A name that collides with another source **or an existing authored
  skill** is a hard error naming both origins (`prefix` is the escape hatch), killing silent
  shadowing; `--update` prunes stale cache dirs + lock rows (origin-keyed, `--dry-run`-previewable).

- **Deterministic post-compaction memory recovery on Codex** (#60). A per-session
  `<session_id>.recompact` sentinel drives reliable re-injection of the full memory payload after a
  context compaction, rather than depending on a heuristic first-prompt detection.

- **Hook standardization — data-driven, manifest-wired hooks** (#57, #58, #59). Hook wiring moved off
  per-harness bespoke glue onto a single manifest `[hooks]` role map:
  - **P1** — data-driven hook wiring via the manifest role map (the engine reads roles, not hard-coded
    hook paths).
  - **P2** — shared hook scripts; Codex moved onto its native hook mechanism (hybrid).
  - **P3** — Claude moved onto the shared hook scripts, with a fail-closed `settings.json` auto-merge
    (a malformed merge refuses rather than silently dropping wiring).

- **`executor.sh --run --clean`** (#56) — uniform final-message output across executor planes, so a
  delegated run returns just its final message regardless of harness.

- **`/start --worktree`** (#55) — route a feature task into an isolated git worktree so its execution
  doesn't collide with other in-progress work; the per-session scratchpad auto-resolves to the
  worktree's overlay.

- **Per-worktree `working.md` overlay** (#54) — concurrent sessions in different worktrees get their
  own scratchpad (`working.<slug>.md`) instead of racing on one file.

- **Task-provider delete interface** (#53) — a `delete` capability threaded across the provider
  contract, the `local`/`notion` providers, and the `taskctl` CLI.

### Fixed

- **A `MEMORY_DIR` containing a space silently corrupted the derived state snapshot.**
  `regenerate-state.sh` and `regenerate-activity.sh` iterated `for f in $(find …)`, so an
  unquoted command substitution word-split every path: `/state` rendered a row with every
  column blank (`| — | alpha | — | — | 0 |`) *and* a phantom project invented from the
  split fragment. Both now materialize the `find` output and read it with
  `while IFS= read -r` — deliberately not `while … done < <(producer)`, whose non-zero
  producer exit is silently swallowed. Output is byte-identical on paths without spaces.
  Surfaced by `SC2044` while installing the shellcheck gate.

- **`${f#$MEMORY_DIR/}` treated `$MEMORY_DIR` as a glob pattern** in `archive-cleanup.sh`
  and `apply-partial.sh` (`SC2295`); the prefix is now quoted.

- **The executor deny-list guard passed its spec files as a space-joined string.**
  `pretooluse.sh` word-split `$DENY_SPEC_FILES` under a default `IFS` into paths that do not
  exist, so a `$REPO` containing a space made the guard load fewer rules than it believed it
  had — a command the local overlay was meant to deny would be allowed. It now passes an
  array. Latent (no checkout has a space today), but this is the enforcement guard.

## [1.2.0] - 2026-07-09

### Added

- **Task `summary` is capped at 500 characters**, enforced on write at the
  `TaskProvider` contract boundary (`validate_summary`, applied by
  `__init_subclass__` to `capture` and `update` — the same mechanism that already
  guards `set_status`). The cap is **backend-neutral**: it descends from the
  projection model, not from Notion's per-element limit, so a `local`-only task
  obeys it too, and it fires **before provider dispatch** — an over-cap Notion
  capture never issues an HTTP request. Long-form content belongs in
  `projects/<project>/brainstorms/<slug>.md`, referenced from the summary **by name,
  never by path** — a path rots the moment the work is archived, and the task record
  already carries its `project`. The error message says so. **Reads are not gated** —
  tasks captured before the cap still load, and are corrected on next write. No migration.
- **`scripts/check-provider-tests.sh`** — enforces that every
  `taskprovider/providers/<name>.py` ships a matching `tests/test_<name>.py`. Adding
  a provider needs no factory edit by design, so nothing else would notice one
  landing without tests.

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

- **`install.sh` aborted silently, mid-run, for any `hooks_json` harness that does not
  declare `guard_script`.** In `scripts/drivers/hook.sh`, the guard-registration notice
  `[ -n "$gs" ] && info …` was the last statement of `_hook_register_json`, so with no
  `guard_script` the test failed, the function returned 1, and `set -euo pipefail`
  killed the installer the moment it returned — after the hooks step, before skills,
  commands and config stamping, with no error printed. Latent for the shipped harnesses
  (Antigravity sets `guard_script`) but it broke the advertised extension point: a
  hook-archetype harness that wants injection **without** enforcement could not install.
  Now an `if` block, which yields 0 when the branch is not taken. Worth noting that
  **shellcheck does not detect this**, at default severity or under `-o all` (including
  `check-set-e-suppressed`) — the control for this class is a behavioural install test,
  not a linter.

- **The executor deny-list could be bypassed with a single interposed flag, and
  failed open without a JSON parser.** Its patterns anchored the binary directly to
  the subcommand (`terraform[[:space:]]+apply`), so `terraform -chdir=envs/prod apply`,
  `kubectl -n foo delete pod x`, `kubectl --context=prod apply -f x.yaml` and
  `gh --repo o/r pr merge 12` all reached running infrastructure — verified live.
  `helm uninstall`/`helm delete` were absent entirely, so the list blocked the additive
  helm verbs and permitted the destructive ones. Separately, `pretooluse.sh` gated its
  deny loop on a non-empty `CommandLine`, which is also what a missing `jq`/`python3`
  produces — so a machine without either ran **unguarded**.

  Matching now lives in `scripts/deny-match.sh`, which tokenizes the command line and
  recurses into shell re-entry and substitutions. It splits on `&&`, `||`, `;`, `|`,
  newline, **a lone `&`** (`sleep 1 & terraform apply` runs terraform) and subshell/brace
  punctuation; skips compound-statement leaders (`then`, `do`, …); strips `VAR=val`
  assignments and transparent exec-wrappers (`sudo`, `env`, `timeout`, `nice`, `flock`,
  `setsid`, `stdbuf`, `xargs`, `busybox`, `find`, …) — scanning the tail afterwards,
  because `sudo -u root kubectl …` puts a flag *value* where the binary should be; and
  follows `sh -c`, `bash -lc`, glued `-c"…"`, `bash <<< "…"`, `su`/`runuser -c`, `eval`,
  `trap`, `find -exec` (only what follows `-exec`/`-execdir`/`-ok`, never a `-name`
  value), `$(…)`, backticks and `<(…)`, with a depth cap that denies. Quote state models
  the shell: single quotes suppress substitution (`echo '$(terraform apply)'` is allowed),
  double quotes do not (`echo "$(terraform apply)"` is denied), and an apostrophe inside
  double quotes is a literal — `echo "it's $(terraform apply)"` is denied.

  The guard denies when no parser is available, and when the spec file is missing **or
  has no usable rules** — existence is not armed-ness; `: > deny-list.txt` disarms as
  well as `rm`. Every check sits *after* the `AI_MEMORY_ROLE` gate, so interactive `agy`
  is unaffected. Note `echo terraform apply` is now **allowed** (the binary is `echo`);
  the old substring regex denied it, but it also denied `git commit -m "kubectl delete"`.

  Hardened over seven adversarial validation rounds (the last two on a different model
  family), which found 24 bypass classes between them — every one *after* the suite was green,
  and three introduced by a previous round's fix. The sharpest classes: a wrapper whose flag
  takes a value then a bundled `sh -c` (`timeout 5 sh -c "terraform apply"`,
  `sudo -u root sh -c "…"`), closed by scanning the wrapper's tail for a payload-bearing
  binary; and a wrapper's *own* `-c` command flag (`flock <lock> -c "terraform apply"`, the
  canonical serialized-infra idiom), closed by extracting `flock`/`script` `-c` payloads.
  Each class has a named regression test (164 assertions). **This is a backstop against an
  honest agent, not a sandbox:** it matches command text, so obfuscation (base64, a script
  file, a remote `ssh host terraform apply`, or `eval "$(…)"` whose danger is only in runtime
  output) still passes.

  Instance rules go in a gitignored `scripts/deny-list.local.txt` (**additive only**);
  `scripts/deny-list.txt` stays tracked and un-hand-edited so new defaults keep reaching
  every instance on sync, and so editing it can never trip `dirty_tracked_guard`.
  The `explore`-role bypass shipped in 1.1.0.

- **`scripts/run-tests.sh` never ran the `scripts/taskprovider/tests/` Python
  suite.** The runner globbed only `scripts/tests/test_*.sh`, so the entire Python
  unittest suite sat outside the test gate — the reported pass count was bash-only,
  and adding a Python test file did not change it. The runner now executes the suite
  as its own hermetic stage and gates its exit code on the result.

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
