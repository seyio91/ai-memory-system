# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.4.1] - 2026-07-20
### Fixed

- **The codex `arm_recompact.sh` compatibility shim is deleted.** It survived one release (v1.4.0) so a
  stale pre-flip `~/.codex/hooks.json` — from a manual `git pull` that never re-ran `install.sh` — kept
  working by delegating to the shared session-start script. That grace period is over.
  **Its name is deliberately retained in the hook-registration sweep set** (`scripts/drivers/hook.sh`), and
  that retention is what makes the deletion safe: re-running `install.sh` (or `sync-system.sh`, which calls
  it) rewrites the stale entry to point at `scripts/hooks/session_start_memory.sh`. Dropping the marker
  along with the file would leave a stale entry aimed at a path that no longer exists, and codex would
  error on every `SessionStart` — deleting a hook script and retiring its sweep marker are two different
  releases. The sweep is now covered by a test that was mutation-verified against exactly that mistake.
- **`test_codex_arm_recompact.sh` → `test_session_start_memory.sh`.** Every assertion in it was always
  about `scripts/hooks/session_start_memory.sh`'s compaction-arm behaviour rather than the shim's, so all
  six carry over unchanged. The rename also makes `run-tests.sh --changed` map
  `session_start_memory.sh` → `test_session_start_memory.sh` by naming convention instead of relying on
  the basename-grep fallback.
- **The five seed templates moved from the repo root into `templates/`.**
  `config.local.sh.example`, `identity.template.md`, `index.template.md`, `orchestrator.template.md`,
  and `skills.toml.example` are engine inputs that `install.sh` copies when a target is missing — not
  files a user opens — and they crowded the root alongside the actual front door (`README.md`,
  `install.sh`, `UPGRADING.md`). Basenames are unchanged; this is a path move only, so every mention
  in older `CHANGELOG.md` / `UPGRADING.md` sections still greps.
  **No migration is needed and none is shipped:** `install.sh` seeds only when the target is absent,
  an existing instance already has all five live files, and the new `install.sh` ships in the same tag
  as the moved templates. Nothing on a consumer instance resolves a template path at runtime.
- **`skill_manifest_template()` now returns `templates/skills.toml.example`.** The `.gitignore`
  negation that kept the old root path tracked is dropped rather than repointed — the `/skills.toml`
  rule is root-anchored, so the `templates/` copy was never in its scope. Both directions are now
  asserted: the five templates are tracked, and their five live counterparts stay ignored.

## [1.4.0] - 2026-07-20
### Added

- **`/plan-archive` now moves the plan's linked investigation too.** It resolves the
  investigation by the plan's frontmatter `task_ref` first, falling back to a same-slug
  filename match, and moves it from `investigations/` to `archive/investigations/` in the
  same invocation. A destination collision aborts only the investigation move (reported,
  not silent) and never blocks the plan's own archival.
- **`lint-memory` gains rule 10: stale investigation detection.** A live
  `investigations/<slug>.md` whose `task_ref` matches a plan already in `archive/plans/`
  now warns — the work shipped and the investigation was left behind. The check is
  purely local frontmatter comparison and never calls the task provider.
Codex memory base moves from a generated `~/.codex/AGENTS.md` to live `SessionStart`
hook injection — a plain `codex` (no alias, no wrapper) now gets full memory.
`AGENTS.md` becomes a hand-owned static base (migration converts a generated one,
seeding from `AGENTS.local.md`); `codex-mem.sh --executor-bare` suppresses all
injection via `AI_MEMORY_SKIP_INJECT=1`.
- **GitHub Copilot CLI is now a first-class harness.** `install.sh --harness copilot`
  wires user-level `sessionStart`, `preToolUse`, `preCompact`, and `postToolUse` hooks
  for live markdown memory injection, guarded executor runs, compaction recovery, and
  a Copilot CLI executor face with a read-only `view,grep,glob` mode.
- **Identity and orchestration doctrine are now separate files.** `install.sh` seeds a gitignored `orchestrator.md` from tracked `orchestrator.template.md`, injects it directly after `identity.md` in every harness payload, and ships the `brainstorming` workflow skill in-engine under `skills/brainstorming/` instead of as a remote catalog entry.
Investigations are tied to the task lifecycle: a live `investigations/<slug>.md`
must carry a frontmatter `task_ref` (`lint-memory` warns on orphans), and moves to
`archive/investigations/` when its task closes and the consuming plan ships.
- **Release pipeline — Phase B: fully automated publish via GitHub Actions.** When
  `changelog.d/` fragments land on `main`, `release-pr.yml` opens a "Release vX.Y.Z" PR carrying
  the assembled CHANGELOG for review; merging it triggers `release-publish.yml`, which tags,
  pushes, and creates the GitHub Release. The human merge is the sole authorization gate.
  - `release.sh` gains `--prepare` (assemble + delete fragments + commit on a `release/*` branch;
    no tag, no push; refuses on `main`) and `--publish` (tag the merged release commit + push +
    GitHub Release). It stays the single release implementation — the Actions are thin triggers.
  - `--publish` is keyed on the CHANGELOG carrying the `## [version]` section, not on a commit
    subject, so it works whatever merge strategy the Release PR uses (merge commit, squash, or
    rebase), and is idempotent on re-run.
  - The auto-opened Release PR uses the `RELEASE_PAT` secret (not the default `GITHUB_TOKEN`) so
    it actually gets CI — PRs opened with `GITHUB_TOKEN` don't trigger workflow runs.
- **Release pipeline automation — Phase A** (changelog fragments + computed versioning).
  - CI now runs the full suite on every PR and `main` push (`.github/workflows/tests.yml`),
    matrix ubuntu + macOS — macOS holds the Bash 3.2 portability line; shellcheck is installed
    so the gate fires.
  - Per-PR **news fragments** land in `changelog.d/<id>.<kind>.md`
    (`breaking | feature | fix | upgrade`). `scripts/assemble-changelog.sh` turns them into a
    CHANGELOG section deterministically and computes the next version from the fragment kinds.
  - `release.sh` consumes fragments when present (assembling the section and deleting the
    fragments in the release commit), makes the version argument optional (computed from
    fragments when omitted), and gains a non-interactive `--ci` mode that also creates the
    GitHub Release. It stays the single release implementation — CI is a trigger, not a second
    code path.
- **The active project is now resolved once per session, not on every prompt.** `SessionStart` records the
  resolved project in `$MEMORY_STATE_DIR/<session_id>.project` and every later prompt honours it, so a session
  that `cd`s into another repository keeps writing memory to the project it is *about*. Previously resolution
  re-walked from `cwd` each prompt, so a shell command that changed directory silently repointed
  `/checkpoint`, `/promote-memory`, and every plan or todo edit at a different project's memory — with the
  breadcrumb reporting the new project as if it were correct.
- **`<memory:active>` gained two lines.** `session:` always (the hook's `session_id`, which `/pin` needs to
  repin a live session — the agent cannot learn it otherwise, since the hook stdin carrying it is consumed by
  a separate process), and `pinned:` only when `cwd` resolves to a different project than the one in force,
  so a deliberate `cd` is explained rather than silently ignored.
- **`/pin` and `memory-pin.sh` take `--session <id>`**, rewriting the live session's pin alongside the marker
  and reverse map. Without it the marker is still written, but the running session keeps its project until
  restart — `/pin` now says so explicitly instead of appearing to work.
- **Executors and subagents keep resolving from their own `cwd`, by design.** That is what makes cross-project
  delegation work. The pin is a session-keyed *file* rather than an environment variable precisely because env
  inherits into child processes: an exported project would follow an executor into a sibling repo and resolve
  the orchestrator's project there — worse than the bug being fixed, and a live defect in the antigravity
  harness today, tracked separately.
- Every failure path degrades to the previous behaviour rather than corrupting: no `session_id`, no pin file,
  a pin naming a deleted or renamed project, or an unwritable state directory all fall back to the `cwd` walk.
  Pins are swept after `AI_MEMORY_PIN_RETAIN_DAYS` (default 7) — deliberately longer than the `.recompact`
  sweep, because a sentinel is consumed on the next prompt while a pin must outlive a multi-day session.
The executor/validator sentinel is now `subagent` — orchestrator-relative: it means the calling harness's own subagent plane (Claude's Agent tool, Copilot's background agents), never a specific harness. `claude-subagent` remains an accepted legacy alias, so existing `config.local.sh` files keep working. Defaults, error messages, docs, and doctrine updated to the role-based name.

### Fixed

- **Three latent portability bugs surfaced by the new CI** (first run on ubuntu + macOS).
  - `file_mtime`/lint read mtime with BSD `stat -f %m` first; on GNU/Linux `-f` is
    `--file-system` (a valid *different* mode, not a clean failure), so it polluted the value
    → `/state` last-touched ordering was wrong and stale files went unflagged on Linux. Now the
    GNU form (`stat -c %Y`) is tried first — it fails cleanly on BSD.
  - `manifest_get` returned on the first key match while reading `< <(_mf_pairs …)`, closing the
    pipe mid-write so the producer's `printf` took `SIGPIPE` ("write error: Broken pipe"). It now
    buffers the pairs before searching.
  - The Antigravity statusline built its Nerd-Font glyphs with `$'\uXXXX'`, which needs bash
    4.2+; under the repo's own bash-3.2 target they stayed literal. Now emitted with `printf`
    octal, matching the emoji fallback.
  - CI pins shellcheck to an exact version (0.11.0) via the official binary instead of
    apt/brew, whose per-runner versions flagged `SC2015` differently → the lint is now
    deterministic and reproducible locally. Two pre-existing `A && B || C` lines
    (`drivers/hook.sh`, `deny-match.sh`) were rewritten clean regardless.
- **`check-docs.sh` no longer resolves a `Used by` cell to a test fixture.** `resolve_script()` matches by
  basename and takes `head -1` over the code roots, and `scripts/tests/fixtures/` was in scope — so
  `session_start_memory.sh` resolved to the `claude-legacy-hooks` fixture instead of the real
  `scripts/hooks/` consumer. Two failure modes, both live: a false FAIL against a legitimate row (which is
  what blocked documenting `AI_MEMORY_SKIP_INJECT`), and the fail-open mirror — a fixture that happens to
  contain the var certifies a consumer that no longer uses it, in the control built to prevent exactly that.
  `tests/fixtures/` is now pruned; `tests/` itself stays in scope, because the table legitimately names test
  scripts as consumers (`AI_MEMORY_UPGRADING_DOC` → `test_upgrading_doc.sh`). Mutation-verified in both
  directions.
- **Three more environment overrides are documented** (34 rows, up from 31). `AI_MEMORY_SKIP_INJECT` — the
  previously undiscoverable kill switch for *all* memory injection, the escape hatch when injection itself
  misbehaves. `AI_MEMORY_HARNESSES_DIR` — a test seam, labelled as one. `AI_MEMORY_ROLE` — set *by*
  `executor.sh` and read by `release.sh`, which refuses a release cut while it is set; documented so that
  refusal is diagnosable, not because anyone should set it by hand.
- **The gate's own "what it does not catch" section named a var that had since gained a row.** It cited
  `AI_MEMORY_SKILL_DATA` as the example of an unchecked var and stayed stale after that changed. It now names
  the *mechanism* — both axes iterate table rows, so an undocumented var is unreachable by construction, and
  `0 findings` describes the table's accuracy rather than the code's coverage. A prose section no axis reads
  is where citations rot silently.
- **Three user-facing environment overrides are now documented.** `MEMORY_RELOAD_TRIGGER` (the prompt
  token that forces a full re-injection, default `@memory`), `AI_MEMORY_SKILL_DATA` (per-skill local data
  root, default `$MEMORY_DIR/.skill-data`), and `MEMORY_ROOT` were all readable knobs — each consumed as a
  plain `${VAR:-default}` and settable by any user — but absent from the `docs/scripts.md` table, so
  `check-docs.sh` could not see them. The gate only checks documented vars *forward* into code; a knob that
  was never documented is invisible to it in both directions. The table now carries 30 rows, up from 27.
- **`MEMORY_ROOT` is documented as a legacy alias, not a general knob.** It is read by
  `sync-project-skills.sh` alone, filling the role `MEMORY_DIR` plays in every other script. The row says so
  explicitly and warns against new consumers, so documenting it records the inconsistency rather than
  blessing it.
- **`link-skills.sh` now prunes dangling store-shaped symlinks.** The link pass only ever walked
  skills that still exist, so a link stranded by a skill rename or by a move of the memory tree was
  never revisited and survived indefinitely — two such links (`dashboarding`, `tempo`) persisted
  across both a rename and a full tree relocation without any check noticing. A link is now removed
  only when it is dangling **and** its target sits directly under a `skills/` or `.skill-cache/`
  directory **and** the target basename matches the link name; anything else is reported as a `WARN`
  and left untouched. The match is deliberately on *shape* rather than on the currently-configured
  store roots, because a moved tree leaves links pointing at a root that is no longer configured —
  the exact case that would otherwise slip through. `--dry-run` reports prunes without removing, and
  the summary line gains a `N pruned` count.
- **`lint-memory` rule 8 now checks the plan `status:` vocabulary instead of one typo.** It previously
  flagged only the hyphenated `in-progress` — a spelling nothing in the tree had ever used — while real
  drift passed clean: synonyms like `active`, and plans carrying no `status:` at all. The rule now accepts
  exactly `draft`, `in_progress`, `done` (what the tooling itself produces: `/new-plan` scaffolds `draft`,
  `/plan-done` writes `done`) and warns on anything else, naming the offending value, with a dedicated hint
  for the `in-progress` near-miss and for a missing field. This matters because `/state` and `/activity`
  render `status:` verbatim — a synonym splits one report column into two, and an absent status renders
  blank.
- **The plan frontmatter contract is now documented.** `docs/file-formats.md` gains a *Plan frontmatter*
  section giving the full field list and the status vocabulary. Previously the only place the canonical set
  was written down was inside rule 8's own comment, so the convention was undiscoverable to anyone not
  reading the linter — which is how it drifted in the first place. The doc is the source of truth; the rule
  is the enforcement.
- **Memory injection reached the model whole again on Claude — it had been silently truncated to a
  2KB preview.** `harnesses/claude/manifest` declared no `session_chunks` / `inject_chunks`, so the
  count defaulted to `1` and `emit_hook_chunk` took a `1/1` fast path that returned the payload
  unmeasured. The entire memory base then went out as a single hook message against Claude Code's
  ~10,000-character `additionalContext` cap, so the harness spilled it to a file and only a 2KB
  preview of `identity.md` survived into context. The hook exited `0` and nothing reported the
  degradation — a session looked normal while running with almost no memory. The base is now fanned
  across 12 ordered entries of ≤9,000-byte slices, the same shape Codex already used.
- **Chunked injection no longer depends on hook delivery order.** Claude runs same-event hook entries
  **concurrently** and concatenates them by completion, so registration order is not delivery order
  (entries registered 1..12 were observed arriving 2,3,4,1,5). Because slicing happens on line
  boundaries, an out-of-order chunk bisects a content block and the reassembled payload is corrupt.
  Every slice now carries a self-describing `<memory:chunk index="N" of="M">` envelope so the model
  can reassemble regardless of arrival order. Codex delivers in registration order and was never
  affected — the behaviour was verified per-harness rather than assumed from one.
- **An oversized base is now loud instead of silent.** When the payload outgrows its chunk budget the
  existing overflow marker fires — `[ai-memory: memory base truncated — raise session_chunks in the
  harness manifest]` — rather than the harness quietly spilling to a file. Raising `session_chunks` /
  `inject_chunks` in the harness manifest is the fix when you see it.
- **`/plan-archive` now relinks the live `todo.md`.** Moving a plan to `archive/plans/` left every
  `todo.md` reference pointing at a file that no longer existed, and nothing caught it — the command
  read `todo.md` only to count unchecked boxes, and `lint-memory` checks that `plans/` exists as
  scaffold but never validates link targets. The dangling link then survived until the next
  `/todo-archive` roll, which can be weeks. A new Step 7b rewrites `plans/<slug>.md` to
  `archive/plans/<slug>.md` in the live file only. Snapshots under `archive/todos/` are deliberately
  left alone: they record what `todo.md` said the day it was rolled, so editing one to reflect a later
  move would falsify an audit record — a dangling link there is correct.
- **`/promote-memory` no longer destroys the rest of `working.md`.** Its Step 6 moved the *entire* file to
  `archive/working/` and started a fresh empty one, so a single promotion also wiped `## Checkpoints` —
  including mid-flight entries owned by `/checkpoint-archive` — and any free-form section such as
  `## Open threads` that no command owns. It now rolls only `## Cross-project learnings (pending
  promotion)`, leaving every sibling section byte-identical. This contradicted the command's own opening
  line, which had always said checkpoint archival was separate.
- **`checkpoint-archive.sh` grew a `--section <heading>` flag** (default `Checkpoints`, so the existing
  two-arg form is unchanged) and both commands now share it rather than keeping two copies of a
  fence-aware, overlay-aware section rewriter. The heading is matched as a literal string, not a regex:
  the learnings heading contains parentheses, which a regex reads as grouping — it would miss the section,
  roll nothing, and still exit 0.
- **`/promote-memory`'s abort condition was inconsistent with its own candidate scan.** Step 3 reads both
  `## Cross-project learnings` and `## Checkpoints`, but Step 2 aborted whenever the learnings section held
  only its placeholder — making a lesson recorded in a checkpoint unpromotable. It now aborts only when
  both sources are empty. A learning promoted out of a checkpoint leaves that checkpoint in place and may
  be offered again until checkpoints are rolled; `/checkpoint-archive` remains the sole owner of that
  section.
- **`release-pr.yml` no longer stalls after a Release PR is closed.** Its "is a Release PR
  already open?" guard used `gh pr view <branch>`, which also matches a *closed* PR — so once a
  Release PR was closed (rather than merged), the next fragment change saw the stale closed PR
  and skipped opening a fresh one, silently halting auto-proposed releases. It now checks for an
  **open** PR only (`gh pr list --head <branch> --state open`).
- **`sync-project-skills.sh` now honours `MEMORY_DIR` — it was silently ignoring it.** The script resolved
  the tree into its own `MEMORY_ROOT` and then assigned `MEMORY_DIR="$MEM"` *before* sourcing `_lib.sh`, so a
  user-set `MEMORY_DIR` was discarded and the self-located tree was synced instead. It was the one script in
  the tree that ignored the system's universal tree override, and it did so without a word: pointed at a
  sandbox with `MEMORY_DIR=…`, it happily wrote skill symlinks into the real repos named by the *other*
  tree's `repo_path`s. Tree resolution is now delegated to `_lib.sh`, the same `${MEMORY_DIR:-self-locate}`
  path every other script uses, so `config.local.sh` is also read from the tree actually being synced.
- **`MEMORY_ROOT` is deprecated.** It is still read and still takes precedence, but prints a deprecation
  notice to stderr. Honouring it is deliberate: silently ignoring it would reintroduce the identical
  wrong-tree failure for anyone who had set it. It is removed at the next major.
- **The `working:` breadcrumb no longer advertises a file that does not exist.** From any subdirectory of a
  main checkout — at any depth, in any repo — `resolve_session_key` reported a linked worktree and keyed the
  scratchpad on the literal string `.git`, so the per-prompt breadcrumb named
  `projects/<project>/working..git.md`. Nothing on disk matched. `/checkpoint` is instructed to use that path
  *verbatim* and explicitly warned against hand-building `working.md`, so following it would have created a
  phantom file, reported success, and left the real working memory untouched — the guard rail that exists to
  protect concurrent sessions was what routed the write into nowhere.
- **Cause: two `git rev-parse` forms were compared in different shapes.** git returns `--git-dir` absolute
  from a subdirectory but `--git-common-dir` relative, with a depth-dependent prefix (`../.git`,
  `../../.git`). They only compared equal at the repo root, so every other cwd looked like a linked worktree.
  Both are now resolved to real absolute paths before comparison, which also makes a repo reached through a
  symlink compare equal to the same repo reached directly.
- **A derived worktree key is now validated, and rejected rather than coerced.** Empty, dot-leading, or
  separator-bearing keys fall back to the shared `working.md`; a wrong-but-well-formed key is harder to
  notice than no key at all. The check deliberately does not reuse the marker sanitizer, which lowercases —
  that would have silently moved an existing `working.wt-featureB.md` to `working.wt-featureb.md`.

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
