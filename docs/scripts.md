# Scripts reference

| Script | Purpose | Common invocations |
|--------|---------|---------------------|
| `manifest.sh` | Parse a harness manifest (sourced) | `manifest_get <file> <key>`, `manifest_keys <file>` |
| `validate-manifest.sh` | Static-check harness manifests | `validate-manifest.sh [<file>]` (exit 1 on ERROR) |
| `build-context-md.sh` | Build the md context (AGENTS.md-style) from the memory tree | `build-context-md.sh <out> <label> [overlay]` — generic `refresh=launch` builder; no registered consumer since the codex SessionStart flip |
| `drivers/{hook,file}.sh` | Archetype install drivers (sourced by install.sh) | `driver_install`, `driver_notes` |
| `link-command-skills.sh` | Deliver command bodies AS skills (`commands=skill`) | `link-command-skills.sh <commands-src> [skills-dir]` |
| `gen-commands-doc.sh` | Render a "Memory Commands" reference (`commands=doc`) | `gen-commands-doc.sh <commands-src> <out-file>` |
| `codex-mem.sh` | Run codex (executor sandbox/network flags; memory injects via the SessionStart hook, no file build) | `codex-mem.sh`, `codex-mem.sh exec --sandbox read-only "..."` |
| `codex-mem-checkpoint.sh` | Emit checkpoint scaffold | TTY → opens `$EDITOR`; `--for-codex` → stdout for Codex to consume |
| `agy.sh` | Antigravity launch wrapper (build context + `exec agy`) | `agy.sh [agy args...]` (alias `agy` to it) |
| `executor.sh` | Resolve + dispatch the configured executor/validator (manifest-driven) | `executor.sh [--role task\|explore\|validate] --which \| --run [--clean] "<prompt>" \| --show`; `--clean` emits only the final agent message (needs the harness's `exec_last_message`) |
| `regenerate-index.sh` | Rebuild `index.md` AUTOGEN block | `regenerate-index.sh` (idempotent) |
| `regenerate-state.sh` | Derive the on-demand **In Flight** snapshot (`/state`), grouped by category | `regenerate-state.sh [--stdout]`, `regenerate-state.sh <category> --stdout` → `state.md` (gitignored) |
| `regenerate-activity.sh` | **Activity report** (`/activity`) — plans created in a window, grouped by category | `regenerate-activity.sh (<category>\|--all) [--since <N>[d]] [--stdout]` → `activity.md` (gitignored) |
| `lint-memory.sh` | Mechanical lint | exit 0 if clean, 1 if any WARN/ERROR |
| `archive-cleanup.sh` | Prune old `archive/` files | `archive-cleanup.sh [--all-projects] [--days N]` (dry-run, then confirm) |
| `sync-system.sh` | Sync an instance to its configured channel, run pending migrations, then re-run `install.sh` | `sync-system.sh`, `sync-system.sh --to <ref>`, `sync-system.sh --to=<ref>`, `sync-system.sh --dry-run`, `sync-system.sh --no-pull`, `sync-system.sh --update`; `--to` with `--no-pull` is a usage error (exit 2) |
| `release.sh` | Orchestrator-only release cut; refuses when `AI_MEMORY_ROLE` is set. Consumes `changelog.d/` fragments when present (assembles the section + deletes them in the release commit) and computes the version from them when `<version>` is omitted. Also drives the CI release: `--prepare` assembles on a `release/*` branch (no tag/push, refuses on main) and `--publish` tags the merged release commit + creates the GitHub Release (idempotent) | `release.sh [<version>] [--ci] [--dry-run] [--no-push]`; CI-split: `release.sh [<version>] --prepare`, `release.sh <version> --publish` |
| `assemble-changelog.sh` | Turn `changelog.d/<id>.<kind>.md` news fragments into a CHANGELOG section, and compute the next version from the fragment kinds. Pure (no tree mutation); `release.sh` calls it | `assemble-changelog.sh [--dir <changelog.d>] assemble\|--bump\|--check` (exit 0 ok, 1 invalid fragments, 2 none) |
| `migrations/` | Forward-only instance migrations; see [Migrations](../migrations/README.md) | `migrations/<semver>-<slug>.sh` |
| `new-project.sh` | Scaffold a new project (pin a repo with `memory-pin.sh` → `.agents/memory-project` to activate) | `new-project.sh <name>` |
| `memory-pin.sh` | Pin a checkout ↔ project (forward `.agents/memory-project` marker + reverse `repo`/`repo_path`); `--category` sets the project's category; migrates a legacy `.claude` marker | `memory-pin.sh <name> [--category <client>]` (run from inside the checkout) |
| `migrate-marker.sh` | Migrate pinned checkouts `.claude/memory-project` → `.agents/memory-project` (walks each project's reverse map) | `migrate-marker.sh` (dry-run), `migrate-marker.sh --apply` |
| `_lib.sh` | Shared helpers (sourced) | `detect_active_project`, `extract_fm_field`, `projects_root`, `resolve_repo_path` |
| `taskctl` | Bash wrapper for the task-provider CLI (used by `/task`, `/start`) | `taskctl <capture\|list\|get\|update\|set-status\|ping> ...` |
| `taskprovider/` | Python (stdlib-only) task-provider CLI — see [Task-provider layer](task-provider.md) | `PYTHONPATH=$MEMORY_DIR/scripts python3 -m taskprovider <verb>`; tests: `cd scripts && python3 -m unittest discover -s taskprovider/tests -t .` |
| `check-docs.sh` | Assert the env-var table below matches the code (forward + strict-consumer axes) | `check-docs.sh [root]` (exit 0 clean, 1 findings, 2 setup error) |
| `run-tests.sh` | Suite runner: shell tests → python tests → lint → skills → doc-vs-code → shellcheck. Gates on all six | `run-tests.sh [--no-lint] [--tests-only] [--only PAT] [--changed [REF]] [-v]` (exit 0 clean, 1 otherwise) |
| `tests/*` | Dependency-free shell tests (bash 3.2) | `for t in scripts/tests/test_*.sh; do bash "$t"; done` |

### Selecting a subset locally

A full run is ~179s, and it is heavily skewed — `test_install_harness.sh` alone is 67s (40%),
the top three files are 60%, and the median test is 0.24s. `--only PAT` (repeatable) and
`--changed [REF]` cut that to seconds for a typical edit; `--changed` maps a changed file to
tests by naming convention (`foo-bar.sh` → `test_foo_bar.sh`) unioned with a basename grep
across the suite, which is what catches shared libs like `hooks/lib.sh`.

**Selection is a local fast path, never a gate.** CI (`.github/workflows/tests.yml`) runs the
full suite on ubuntu **and** macos for every PR and push to `main`, and that is what gates
merges. A selecting run prints a `SELECTED RUN` banner and a closing `*** NOT A FULL RUN ***`
line so a partial pass cannot be misread as green, and a changed shell script that maps to no
test at all is reported as `UNMAPPED` and **exits non-zero** — an edit no test covers is a
finding, not a pass.

`--tests-only` skips lint/skills/doc-vs-code/shellcheck, but those total only ~12s; `--no-lint`
saves ~1.1s and is a correctness toggle, not a speed control.

All scripts target macOS `bash` 3.2 (no `mapfile`, no associative arrays) and resolve the memory tree via `MEMORY_DIR`. Each test sets `MEMORY_DIR` to a `mktemp -d` sandbox so the suite never touches real memory; the hook's state dir derives from it (`$MEMORY_DIR/.sessions`).

## Static analysis (shellcheck)

`run-tests.sh` ends with a `== shellcheck ==` stage that gates the suite's exit code.
It runs **two invocations against the single root `.shellcheckrc`**:

| Scope | Floor | Why |
|-------|-------|-----|
| `scripts/` + `harnesses/` (excluding `scripts/tests/`) | `-S info` | `SC2086` (unquoted expansion → word-split/glob) is **`info`-level**. A `warning` floor could never fire on the most consequential shell bug class. |
| `scripts/tests/` | `-S warning` | Their info-level hits are test idioms: `SC2015` (`[ c ] && _ok … \|\| _bad …`, where `_ok` always returns 0) and `SC2030`/`SC2031` (deliberate subshell isolation). |

Do **not** add a `scripts/tests/.shellcheckrc`. The nearest rc **replaces** the root one
rather than merging with it, so a disable added at the root later would silently stop
applying to tests. The two floors come from two invocations, not two rc files.

### The four repo-wide disables

`.shellcheckrc` silences exactly four codes, each with a comment saying why:

- **`SC1091`, `SC1090`** — "source not followed". The `. "$SCRIPT_DIR/_lib.sh"` idiom is
  resolved at runtime and is unanalysable by design (76 hits).
- **`SC2016`** — single quotes intentionally suppress expansion (heredocs, `awk`/`perl` bodies).
- **`SC2034`** — variables set for a sourced `_lib.sh`, or captures that exist only to
  swallow stdout while an exit code is asserted.

Everything else fires. Site-specific exemptions are **inline**, never added to the rc:

```sh
# shellcheck disable=SC2086  # deliberate word-split, IFS=: scoped
set -- $roots
```

An inline disable must carry a justification and must be true. We deliberately rejected a
`.shellcheck-baseline` of accepted findings: a baseline rots, gets regenerated on autopilot,
and becomes an artefact that *records* a verification instead of performing one.

### Two things this gate is not

**It is not a substitute for a test.** shellcheck cannot see the `set -e` last-statement
class — `[ -n "$x" ] && cmd` as a function's trailing statement returns 1 and, under
`set -euo pipefail`, kills the caller. That bug shipped in `drivers/hook.sh` and is invisible
at every severity, including `-o all` with `check-set-e-suppressed`. The control for it is a
behavioural test (`test_install_harness.sh`, the `noguard` harness).

**A finding is a question, not an instruction.** `SC2155` on
`export AI_MEMORY_PROJECT="$(detect_active_project)"` in `agy.sh` is correct that the exit
status is masked — and the masking is deliberate, because `agy.sh` runs `set -euo pipefail`
and the launcher must start with no project pinned. "Fixing" it would introduce exactly the
abort class above. It carries an inline disable stating that reason.

### Dev-only dependency

shellcheck is **dev/CI-only**; the runtime bet is zero dependencies. When the binary is
absent the stage prints a notice and **skips without gating**, so a fresh machine or a
consumer instance running the suite never fails for lacking a linter.

## Doc-vs-code consistency (check-docs.sh)

`run-tests.sh` has a `== doc-vs-code ==` stage that gates the suite's exit code. Nothing else
tests a doc against the code it describes, and doc rot here is a recorded, recurring gotcha.

The **Environment overrides** table below is the input. Being structured
(`Var | Default | Used by`), it yields two mechanical assertions:

| Axis | Assertion | Catches |
|------|-----------|---------|
| **forward** | every documented var appears somewhere in the code roots | a var renamed or deleted but left documented |
| **strict** | every documented var appears in the script its `Used by` names — **or in any file that script sources, transitively** | a var documented against the wrong consumer |

Source-following is required, not a nicety. `lint-memory.sh` never mentions
`AI_MEMORY_PROJECTS_ROOT`; it calls `projects_root()` in `_lib.sh`. "Used by" means *whose
behaviour the var affects*, not *which file holds the string*. One hop is not enough either:
`scripts/hooks/inject.sh` → `scripts/hooks/lib.sh` → `_lib.sh` is depth 2. The closure
carries a visited-set cycle guard; a runaway graph (`CLOSURE_MAX`)
aborts with exit 2 rather than reporting a verdict from a traversal that never terminated.

**A `Used by` cell that names no script fails**, unless it is listed in `.docscheck-exempt` with a
reason. Five entries today (`MEMORY_DIR`, `MEMORY_TASK_PROVIDER`, three `NOTION_*`). That keeps
prose from silently creeping back into a machine-checked column. Every exemption is a deliberate
hole — before adding one, ask what it now fails to catch.

Write **one full var name per row**. The old shorthand row
`` `AI_MEMORY_EXECUTOR_TASK` / `_EXPLORE` `` was split into two rows rather than taught to a
parser: fix the data, not the reader.

### What it does not catch

Deliberate, and stated so nobody mistakes a green stage for a stronger claim:

- **Semantic prose promises.** `/sync-system --dry-run` once documented "mutates nothing" while
  running `git fetch --tags`. The flag *exists*, so no symbol check can see it.
- **Counts.** A hand-written "27 test files" is drift by construction. Delete the count; don't pin it.
- **Anything outside this table.** `AI_MEMORY_SKILL_DATA` is documented in
  [Claude harness](harnesses/claude.md) but has no row here, so it is unchecked.
- **Cross-repo contradictions.** A remote skill in `.skill-cache/` is *referenced, not forked*; its
  `SKILL.md` cannot be seen from this tree.
- **Comments count as matches.** `AI_MEMORY_EXECUTOR_CMD_<key>` passes the forward axis only because
  `executor.sh` names the placeholder in a comment (the code builds the name dynamically).

The checker excludes **itself** from the code roots. Its comments cite real var names as worked
examples; without the exclusion a deleted var could be re-documented and pass forever on the
strength of a comment inside the control written to catch it.

### Dev-only, and enumerated with `find`

No dependency beyond coreutils, `grep`, `awk`, `sed`, `find`. It never uses `ls`: a wrapper that
degrades `ls` to empty output would turn the check into a silent pass — the exact fail-open class
it exists to prevent.

## Environment overrides

Checked by [`check-docs.sh`](#doc-vs-code-consistency-check-docssh). One full var name per row; a
`Used by` cell naming no script must be exempted in `.docscheck-exempt`.

| Var | Default | Used by |
|-----|---------|---------|
| `MEMORY_DIR` | repo root (self-locating); `~/.claude-memory` when installed | All scripts |
| `AI_MEMORY_PROJECTS_ROOT` | `$HOME/Projects` | `memory-pin.sh`, `resolve_repo_path`, `lint-memory.sh` |
| `config.local.sh` (file, not a var) | unset — copy from `.example` | Sourced by `_lib.sh` + `taskctl` for per-env overrides |
| `CODEX_INSTRUCTIONS_FILE` | `~/.codex/AGENTS.md` | `1.4.0-codex-agents-handoff.sh` |
| `CODEX_OVERLAY_FILE` | `~/.codex/AGENTS.local.md` | `1.4.0-codex-agents-handoff.sh` |
| `CODEX_HISTORY_FILE` | `~/.codex/history.jsonl` | `codex-mem-checkpoint.sh` |
| `CODEX_HISTORY_LINES` | `20` | `codex-mem-checkpoint.sh` |
| `MEMORY_STALE_DAYS` | `30` | `lint-memory.sh` |
| `MEMORY_ARCHIVE_RETAIN_DAYS` | `30` | `archive-cleanup.sh` |
| `MEMORY_STATE_DIR` | `$MEMORY_DIR/.sessions` | `lib.sh` (per-session `<session_id>.recompact` sentinels) |
| `MEMORY_RELOAD_TRIGGER` | `@memory` | `inject.sh` — the prompt token that forces a full re-injection |
| `MEMORY_ROOT` | repo root (self-locating) | `sync-project-skills.sh` **only** — a legacy alias serving the role `MEMORY_DIR` plays everywhere else; do not add new consumers |
| `AI_MEMORY_CHANNEL` | `release` | `sync-system.sh` channel selection: `release` checks out the latest stable `v*` tag; `dev` ff-pulls the tracking branch |
| `AI_MEMORY_MIGRATIONS_DIR` | `$REPO_ROOT/migrations` | `sync-system.sh`, `test_upgrading_doc.sh` (migration directory override) |
| `AI_MEMORY_APPLIED_VERSION_FILE` | `$REPO_ROOT/.applied-version` | `sync-system.sh` (migration high-water marker override) |
| `AI_MEMORY_TEST_NO_SORT_V` | unset | Test seam, not for production use; `_lib.sh:sort_v_supported` override that forces the portable semver sorter |
| `AI_MEMORY_UPGRADING_DOC` | `$REPO_ROOT/UPGRADING.md` | Test seam, not for production use; `test_upgrading_doc.sh` doc path override |
| `AI_MEMORY_SKILL_ROOTS` | `skills:.skill-cache` | `_lib.sh:skill_roots` → all skills tools (enumeration roots, colon-separated) |
| `AI_MEMORY_SKILL_CACHE` | `$MEMORY_DIR/.skill-cache` | `_lib.sh:skill_cache_dir`, `resolve-skills.sh`, `list-skills.sh` (remote-skill cache) |
| `AI_MEMORY_SKILL_DATA` | `$MEMORY_DIR/.skill-data` | `_lib.sh:skill_data_root` — per-skill local data root (gitignored); stateful skills store instance-local data here |
| `MEMORY_TASK_PROVIDER` | `local` | task-provider factory (`local`/`notion`) — see [Task-provider layer](task-provider.md) |
| `NOTION_TOKEN` | — | `NotionProvider` (integration secret; set in `~/.zshenv`) |
| `NOTION_DATA_SOURCE_ID` | — | `NotionProvider` (the data-source id, not the database id) |
| `NOTION_STATUS_KIND` | `status` | `NotionProvider` — set `select` if the board's `Status` is a select property |
| `AI_MEMORY_EXECUTOR_TASK` | (legacy `AI_MEMORY_EXECUTOR` → `subagent`) | `executor.sh` — write-capable executor role — see [Workflow › Executor selection](workflow.md#executor-selection) |
| `AI_MEMORY_EXECUTOR_EXPLORE` | (legacy `AI_MEMORY_EXECUTOR` → `subagent`) | `executor.sh` — read-only executor role — see [Workflow › Executor selection](workflow.md#executor-selection) |
| `AI_MEMORY_EXECUTOR_VALIDATE` | `subagent` | `executor.sh` — read-only validator role; defaults to the orchestrator plane (does **not** chain to the legacy var) → cross-model validation by default |
| `AI_MEMORY_EXECUTOR` | `subagent` | `executor.sh` — legacy single var; fallback for `task`/`explore` only. `subagent` = the orchestrator's own subagent plane (`claude-subagent` accepted as legacy alias) |
| `AI_MEMORY_EXECUTOR_CMD_<key>` | — | `executor.sh` — command template for a generic CLI executor |
| `AI_MEMORY_EXECUTOR_FALLBACK` | `subagent` | `executor.sh` — used when the preferred CLI binary is absent |
| `AI_MEMORY_GUARD_OUTPUT` | unset | `guard.sh` — output envelope selector; `copilot-json` emits Copilot `permissionDecision` JSON instead of legacy exit-2 deny |

`REPO_ROOT` is the checkout root. In a normal install it is the same directory as
`MEMORY_DIR`, but they diverge if `MEMORY_DIR` is overridden.
